#!/bin/bash

module_init() {
    local input_file="$1"
    local output_file="$2"
    check_dependencies awk cat grep ssh timeout mkdir find sed wc tr
                
    [[ -f "$input_file" ]] || {
        log_error "Hlsdaterange device list not found: $input_file"
        return 1
    }
                
    : "${HLSDATERANGE_FILTER_KEY0:?HLSDATERANGE_FILTER_KEY0 is required}"
    : "${HLSDATERANGE_FILTER_KEY1:?HLSDATERANGE_FILTER_KEY1 is required}"
    : "${HLSDATERANGE_FILTER_KEY2:?HLSDATERANGE_FILTER_KEY2 is required}"
    : "${HLSDATERANGE_FILE_GLOB:?HLSDATERANGE_FILE_GLOB is required}"
    : "${HLSDATERANGE_MAX_PARALLEL:?HLSDATERANGE_MAX_PARALLEL is required}"
    : "${HLSDATERANGE_SSH_OPTS:?HLSDATERANGE_SSH_OPTS is required}"
                
    mkdir -p "$(dirname "$output_file")" 
}

_get_remote_data() {
    local host=$1
    local channel=$2
    local result
        
    result="$(
	      timeout 30s ssh ${HLSDATERANGE_SSH_OPTS} "$host" "
            cli_out=\$(show_status -c '$channel' 2>/dev/null)
            if [ -z \"\$cli_out\" ]; then
                echo \"NOT_FOUND|0|1\" 
                exit 0
            fi		
            key1_esc=\$(echo '$HLSDATERANGE_FILTER_KEY1' | sed 's/[][^\$.*+?{}|()]/\\\\&/g')
            key2_esc=\$(echo '$HLSDATERANGE_FILTER_KEY2' | sed 's/[][^\$.*+?{}|()]/\\\\&/g')

            tvod=\$(echo \"\$cli_out\" | awk -v pat=\"\$key1_esc\" '\$0 ~ pat {print \$NF}' | tr -d '[:space:]')
	          channelname=\$(echo \"\$cli_out\" | awk -v pat=\"\$key2_esc\" '\$0 ~ pat {print \$NF}' | tr -d '[:space:]')
                                                
            if [ -z \"\$tvod\" ]; then
		            echo \"\${channelname:-UNKNOWN}|NOT_FOUND\"
            elif [ ! -d \"\$tvod\" ]; then
		            echo \"\${channelname:-UNKNOWN}|DIR_MISSING\"
            else
                count=\$(find \"\$tvod\" -name '$HLSDATERANGE_FILE_GLOB' -exec grep -l '$HLSDATERANGE_FILTER_KEY0' {} + 2>/dev/null | wc -l)
                echo \"\${channelname:-UNKNOWN}|\$count\"
            fi
        " 2>/dev/null || echo "TIMEOUT_OR_FAILED|rc_$?"
    )"
    echo "${result:-"SSH_FAILED|0"}"
}

_hlsdaterange_worker() {
    local contentid="$1"
    local nodezone1="$2"
    local nodezone2="$3"
    local res1 res2 channelname1 count_zone1 channelname2 count_zone2
                
    set +e
    res1="$(_get_remote_data "$nodezone1" "$contentid")"
    if [[ "$res1" == *"rc_124"* ]]; then
	      log_warn "Hlsdaterange job timed out: $nodezone1 $contentid (Network or Environment Blocked)"
    elif [[ "$res1" == *"rc_"* ]]; then
	      local actual_rc="${res1##*rc_}"
	      log_warn "Hlsdaterange job failed: $nodezone1 rc=(${actual_rc:-UNKNOWN})"
    fi

    channelname1="${res1%|*}"
    count_zone1="${res1#*|}"
	        
    res2=i"$(_get_remote_data "$nodezone2" "$contentid")"
    if [[ "$res2" == *"rc_124"* ]]; then
        log_warn "Hlsdaterange job timed out: $nodezone2 $contentid (Network or Environment Blocked)"
    elif [[ \"$res2\" == *"rc_"* ]]; then
	      local actual_rc="${res2##*rc_}"
	      log_warn "Hlsdaterange job failed: $nodezone2 rc=(${actual_rc:-UNKNOWN})"
    fi

    channelname2="${res2%|*}"
    count_zone2="${res2#*|}"

    if [[ "$channelname1" == "$channelname2" ]]; then
        final_channelname="$channelname1"
    else
        final_channelname="FC1_${channelname1}__FC2_${channelname2}"
    fi

    echo "$contentid,$nodezone1,$count_zone1,$nodezone2,$count_zone2,$final_channelname" >>  "$MODULE_TMP_RUN_DIR/${contentid}_${RUN_ID}.data"       
    echo "-------check $MODULE_TMP_RUN_DIR-------"
    ls -l "$MODULE_TMP_RUN_DIR"
}

module_run() {
    local input_file="$1"
    local output_file="$2"
    local device 

    log_info "Starting hlsdaterange collection (Atomic Flow-Controlled Parallel Mode)"

    local fifo_file="${MODULE_TMP_RUN_DIR}/hlsdaterange_${RUN_ID}.fifo"
    echo "===========fifo file used for parallel processes: $fifo_file"
    mkfifo "$fifo_file"
    exec 6<>"$fifo_file"  
    rm -f "$fifo_file" 2>/dev/null || true

    local i
    for ((i=0; i<HLSDATERANGE_MAX_PARALLEL; i++)); do
         echo >&6
    done
    echo "ContentID,NodeZone1,Count_Daterange_1,NodeZone2,Count_Daterange_2,ChannelName" >> "$output_file"

    while IFS=',' read -u 3 -r cid nodezone1 nodezone2 || [[ -n "$cid" ]]; do
        [[ -z "$cid" || "$cid" =~ ^# ]] && continue
	      read -u 6
        (
            _hlsdaterange_worker  "$cid" "$nodezone1" "$nodezone2" 
	          echo >&6
	      ) &
	      sleep 0.2
    done 3< "$input_file"
                
    log_info "All background sync tasks submitted successfully, waiting for all data to land..."
    wait
    exec 6>&-

    shopt -s nullglob
    cat "$MODULE_TMP_RUN_DIR"/*.data 2>/dev/null >> "$output_file"
    shopt -u nullglob
    log_success "Hlsdaterange device report: $output_file"
}

module_cleanup() {
    safe_rm_dir "$MODULE_TMP_RUN_DIR" 2>/dev/null || true
}
