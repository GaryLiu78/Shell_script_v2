#!/bin/bash

module_init() {
    local input_file="$1"
    local output_file="$2"

    check_dependencies date ssh timeout grep awk cat

    [[ -f "$input_file" ]] || {
        log_error "Formatted device list not found: $input_file"
        return 1
    }

    : "${MEMDEVASSESS_REMOTE_ATOP_DIR:?MEMDEVASSESS_REMOTE_ATOP_DIR is required}"
    : "${MEMDEVASSESS_SSH_OPTS:?MEMDEVASSESS_SSH_OPTS is required}"
    : "${MEMDEVASSESS_MEM_THRESHOLD:?MEMDEVASSESS_MEM_THRESHOLD is required}"
    : "${MEMDEVASSESS_MAX_PARALLEL:?MEMDEVASSESS_MAX_PARALLEL is required}"
    : "${MEMDEVASSESS_SSH_TIMEOUT:=30}"

    mkdir -p "$MODULE_TMP_RUN_DIR" "$(dirname "$output_file")"
}

_get_target_date() {
    local target_date="$1"
    if [ -z "${target_date}" ]; then
        date -d "yesterday" +%Y%m%d 2>/dev/null
    else
        date -d "${target_date} -1 day" +%Y%m%d 2>/dev/null || echo "${target_date}"
    fi
}

_get_atop_max_memory() {
    local remote_host="$1"
    local target_date="$2"
    local page_size=4096
    local tmp_f="$MODULE_TMP_RUN_DIR/${remote_host}_${target_date}.tmp"
    local atop_file="${MEMDEVASSESS_REMOTE_ATOP_DIR}/atop_${remote_host}_${target_date}"

    log_info "Check remote device ${remote_host} on atop file: ${atop_file}"

    local ssh_cmd="timeout ${MEMDEVASSESS_SSH_TIMEOUT} ssh ${MEMDEVASSESS_SSH_OPTS} ${remote_host}"
    local check_file="${ssh_cmd} \"[ -f ${atop_file} ] && echo 'EXISTS' || echo 'NOT_EXISTS'\" </dev/null"

    local file_exists
    local check_rc=0
    if file_exists=$(eval ${check_file} 2>/dev/null); then
        check_rc=0
    else
        check_rc=$?
    fi

    if [ ${check_rc} -eq 124 ]; then
        log_error "${remote_host} timed out after ${MEMDEVASSESS_SSH_TIMEOUT}s checking for atop file (unreachable, or waiting on an SSH prompt)"
        return 1
    fi

    if [ "${file_exists}" != "EXISTS" ]; then
        log_error "atop file ${atop_file} on ${remote_host} does not exists"
        return 1
    fi

    local extract_cmd="${ssh_cmd} \"atop -r ${atop_file} -P MEM 2>/dev/null | grep '^MEM' \" </dev/null"

    log_info "Extract MEM usage from ${remote_host} ..."
    local mem_data
    local extract_rc=0
    if mem_data=$(eval ${extract_cmd} 2>/dev/null); then
        extract_rc=0
    else
        extract_rc=$?
    fi

    if [ ${extract_rc} -eq 124 ]; then
        log_error "${remote_host} timed out after ${MEMDEVASSESS_SSH_TIMEOUT}s extracting MEM data"
        return 1
    fi

    if [ -z "${mem_data}" ]; then
        log_error "${remote_host} got MEM data failure"
        return 1
    fi

    local max_used_total_mb=0
    local max_used_total_gb=0
    local max_used_total_percent=0
    local max_used_app_mb=0
    local max_used_app_gb=0
    local max_used_app_percent=0
    local tot_mb=0
    local max_timestamp=""
    local line_count=0

    while IFS= read -r line; do
        local fields=($line)
        if [ ${#fields[@]} -lt 11 ]; then
            continue
        fi

        local pagesize="${fields[6]}"
        local physmem="${fields[7]}"
        local freemem="${fields[8]}"
        local cache="${fields[9]}"
        local buffer="${fields[10]}"
        local date_str="${fields[3]}"
        local time_str="${fields[4]}"

        if [[ ! "${pagesize}" =~ ^[0-9]+$ ]] || \
           [[ ! "${physmem}" =~ ^[0-9]+$ ]] || \
           [[ ! "${freemem}" =~ ^[0-9]+$ ]] || \
           [[ ! "${cache}" =~ ^[0-9]+$ ]] || \
           [[ ! "${buffer}" =~ ^[0-9]+$ ]]; then
           continue
        fi
        local current_tot_mb=$(echo "scale=2; ${physmem} * ${pagesize} / 1024 / 1024" | bc 2>/dev/null)

        local used_total_pages=$((physmem - freemem))
        local used_total_mb=$(echo "scale=2; ${used_total_pages} * ${pagesize} / 1024 / 1024" | bc 2>/dev/null)
        local used_total_percent=$(echo "scale=2; ${used_total_pages} * 100 / ${physmem}" | bc 2>/dev/null)

        local used_app_pages=$((physmem - freemem - cache - buffer))
        if [ ${used_app_pages} -lt 0 ]; then
            used_app_pages=0
        fi
        local used_app_mb=$(echo "scale=2; ${used_app_pages} * ${pagesize} / 1024 / 1024" | bc 2>/dev/null)
        local used_app_percent=$(echo "scale=2; ${used_app_pages} * 100 / ${physmem}" | bc 2>/dev/null)
        if [ "${tot_mb}" = "0" ] && [ -n "${current_tot_mb}" ] && [ "${current_tot_mb}" != "0" ]; then
            tot_mb="${current_tot_mb}"
        fi

        if (( $(echo "${used_total_mb} > ${max_used_total_mb}" | bc -l 2>/dev/null || echo 0) )); then
            max_used_total_mb="${used_total_mb}"
            max_used_total_gb=$(echo "scale=2; ${used_total_mb} / 1024" | bc 2>/dev/null)
            max_used_total_percent="${used_total_percent}"
        fi

        if (( $(echo "${used_app_mb} > ${max_used_app_mb}" | bc -l 2>/dev/null || echo 0) )); then
            max_used_app_mb="${used_app_mb}"
            max_used_app_gb=$(echo "scale=2; ${used_app_mb} / 1024" | bc 2>/dev/null)
            max_used_app_percent="${used_app_percent}"
            max_timestamp="${date_str} ${time_str}"
        fi
        line_count=$((line_count + 1))

   done <<< "${mem_data}"

   if [ ${line_count} -eq 0 ]; then
        log_error "${remote_host} parsed failure"
        return 1
   fi
       
   echo "${remote_host}|${target_date}|${max_used_app_mb}|${max_used_app_gb}|${tot_mb}|${max_used_app_percent}|${max_timestamp}" >> "${tmp_f}"
   return 0
}


module_run() {
    local input_file="$1"
    local output_file="$2"
    local tmp_atopmem_report="${MODULE_TMP_RUN_DIR}/tmp_atopmem_report_$(date +%Y%m%d).csv"

    if [ -z "${input_file}" ] || [ ! -f "${input_file}" ]; then
        log_error "Device List not found: ${input_file}"
        exit 1
    fi

    local query_date=$(_get_target_date "$(date +%Y%m%d)")
    local max_parallel="${MEMDEVASSESS_MAX_PARALLEL}"

    if [[ ! "${max_parallel}" =~ ^[0-9]+$ ]] || [ "${max_parallel}" -lt 1 ]; then
        log_error "MEMDEVASSESS_MAX_PARALLEL must be a positive integer, got '${max_parallel}'. Defaulting to 1."
        max_parallel=1
    fi

    log_info "Checking Date: ${query_date}"
    log_info "Device List: ${input_file}"
    log_info "Output file: ${tmp_atopmem_report}"
    log_info "Max parallel jobs: ${max_parallel}"

    echo "Remote_host|Check_Date|Max_MEM(MB)|Max_MEM(GB)|TOT_MEM(MB)|MAX_MEM_Percentage|TimeStamp" > "${tmp_atopmem_report}"

    local total_devices=0
    local pids=()

    while IFS= read -u 4 -r device || [ -n "${device}" ]; do
        [[ -z "${device}" || "${device}" =~ ^[[:space:]]*# ]] && continue

        device=$(echo "${device}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -z "${device}" ]] && continue

        total_devices=$((total_devices + 1))
        log_info "========== Dispatch Device [${total_devices}]: ${device} (parallel) =========="

        _get_atop_max_memory "${device}" "${query_date}" &
        sleep 0.5

        #pids+=($!)
	pids+=("$!")
        if (( ${#pids[@]} >= MEMDEVASSESS_MAX_PARALLEL )); then
            wait -n
        fi

    done 4< "${input_file}"
    wait

    shopt -s nullglob
    cat "$MODULE_TMP_RUN_DIR"/*.tmp >> "$tmp_atopmem_report" 2>/dev/null || true
    shopt -u nullglob
    
    if awk -F '|' 'NR > 1 && $6 > 50 {found=1; exit} END {exit !found}' $tmp_atopmem_report; then
        echo "memdbassess" > ${MODULE_TMP_RUN_DIR}/module.next_step
    else
	log_info "All device healthy are healthy, no need to clean up"
    fi

    log_info "=========================================="
    log_info "Done: total=${total_devices}" # Success=${success_count}, Failed=${fail_count}"
    log_info "=========================================="
}

#module_cleanup() {
#   safe_rm_dir "$MODULE_TMP_RUN_DIR" 2>/dev/null || true
#}

