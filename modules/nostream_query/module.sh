#!/bin/bash

module_init() {
    local input_file="$1"
    local output_file="$2"

    check_dependencies date ssh timeout grep awk cat

    [[ -f "$input_file" ]] || {
        log_error "Formatted device list not found: $input_file"
        return 1
    }

    : "${NOSTREAM_REMOTE_RUNLOG_DIR:?NOSTREAM_REMOTE_RUNLOG_DIR is required}"
    : "${NOSTREAM_FILTER_KEY1:?NOSTREAM_FILTER_KEY1 is required}"
    : "${NOSTREAM_SSH_OPTS:?NOSTREAM_SSH_OPTS is required}"
    : "${NOSTREAM_MAX_PARALLEL:?NOSTREAM_MAX_PARALLEL is required}"

    mkdir -p "$MODULE_TMP_RUN_DIR" "$(dirname "$output_file")"
    log_info "module_init:2 done"
}

_nostream_worker() {
    local id="$1"
    local remote_host="$2"
    local target_local="$3"
    local content_id="$4"
    local rest_str="$5"
    local tmp_f="$MODULE_TMP_RUN_DIR/${id}_${remote_host}_${content_id}.tmp"

    local utc_target utc_target_timestamp
    utc_target=$(date -d "$target_local +0200" -u +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
    utc_target_timestamp=$(date -d "$utc_target" +%s 2>/dev/null)

    if [[ -z "$utc_target_timestamp" ]]; then
        echo "$remote_host,$content_id,$(date '+%Y-%m-%d %H:%M:%S'),invalid target time,$rest_str" >> "$tmp_f"
        return 0
    fi

    local hour_curr hour_prev1 hour_prev2
    hour_curr=$(date -d "@$utc_target_timestamp" +"%Y%m%d%H")
    hour_prev1=$(date -d "@$((utc_target_timestamp - 3600))" +"%Y%m%d%H")
    hour_prev2=$(date -d "@$((utc_target_timestamp - 7200))" +"%Y%m%d%H")

    log_info "Dispatching job $id -> $remote_host contentID=$content_id utc=$utc_target"

    result="$(
  timeout 10s ssh ${NOSTREAM_SSH_OPTS} "$remote_host" bash -s "$content_id" "$utc_target_timestamp" "$NOSTREAM_REMOTE_RUNLOG_DIR" \"$NOSTREAM_FILTER_KEY1\" "$hour_curr" "$hour_prev1" "$hour_prev2" </dev/null  <<REMOTE_SCRIPT
set +e; set +u 

content_id="\$1"
utc_target_timestamp="\$2"
remote_runlog_dir="\$3"
filter_key="\$4"
hour_curr="\$5"
hour_prev1="\$6"
hour_prev2="\$7"

channel_status=\$(show_status 2>/dev/null | awk -v key="\$content_id" '\$2 == key {print \$3; exit}')  
channel_status=\${channel_status:-UNKNOWN}

target_key=\$(date -d "@\$utc_target_timestamp" +"%Y%m%d%H%M%S")
target_file=""

for file in "\${remote_runlog_dir}"/Rmsh_"\${hour_prev2}"*.log "\${remote_runlog_dir}"/Rmsh_"\${hour_prev1}"*.log "\${remote_runlog_dir}"/Rmsh_"\${hour_curr}"*.log
do
    [[ -e "\$file" ]] || continue
    filename="\${file##*/}"
    f_t="\${filename:5:14}"

    if [[ "\$f_t" < "\$target_key" ]] || [[ "\$f_t" == "\$target_key" ]]; then
        target_file="\$file"
    fi
done 

if [[ -n "\$target_file" ]]; then
    match=\$(grep  "\$filter_key" "\$target_file" 2>/dev/null | grep -m 1 "\$content_id" || true)   
    if [[ -n "\$match" ]]; then
        echo "\$match" | awk -v cst="\$channel_status" -F '[] ]+' -v OFS=',' '{
            gsub(/^\[/, "", \$1);
            gsub(/,\$/, "", \$10);
            found=1;
            print cst, \$1" "\$2, \$6, \$10;
        }' 2>/dev/null
    fi
fi
REMOTE_SCRIPT
    )"
    rc=$?

    if [[ "$rc" -eq 124 ]]; then
        echo "$remote_host,$content_id,$(date '+%Y-%m-%d %H:%M:%S'),timeout,$rest_str" >> "$tmp_f"
    elif [[ -n "$result" ]]; then
        echo "$remote_host,$content_id,$result,$rest_str" >> "$tmp_f"
    else
        echo "$remote_host,$content_id,$(date '+%Y-%m-%d %H:%M:%S'),no result,$rest_str" >> "$tmp_f"
    fi
}

module_run() {
    local input_file="$1"
    local output_file="$2"

    echo "Node,ContentID,Channel_Status,NostreamingAT(UTC),Missing_Profile,Missing_Segments,MediaID,Input_IP,Input_Port,ChannelName" > "$output_file"

    local -a pids=()
    local line_num=0
    local remote_host target_local content_id rest_str id

    set +e; set +u
    while IFS=',' read -r remote_host target_local content_id rest_str || [[ -n "$remote_host" ]]; do
        [[ -z "$remote_host" || "$remote_host" =~ ^# ]] && continue
        [[ -z "$content_id" || "$content_id" =~ ^# ]] && continue

        line_num=$((line_num + 1))
        id=$(printf "%03d" "$line_num")

        _nostream_worker "$id" "$remote_host" "$target_local" "$content_id" "$rest_str" &
        sleep 0.5

        pids+=("$!")

        if (( ${#pids[@]} >= NOSTREAM_MAX_PARALLEL )); then
            wait -n
        fi
    done < "$input_file"

    log_success "All jobs dispatched - waiting"
    wait

    shopt -s nullglob
    cat "$MODULE_TMP_RUN_DIR"/*.tmp >> "$output_file"
    shopt -u nullglob

    log_success "Nostream query completed: $output_file"
}

module_cleanup() {
    safe_rm_dir "$MODULE_TMP_RUN_DIR" 2>/dev/null || true
}
