#!/bin/bash/oradbaccess.sh

_sql_sanitize_value() {
    local raw_val="$1"
        
    if [[ "$raw_val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo -n "$raw_val"
        return 0
    fi
        
    if [[ "$raw_val" =~ ^[0-9a-zA-Z_-]+$ ]]; then
        echo -n "$raw_val"
        return 0
    fi
        
    local clean_val
    clean_val=$(echo -n "$raw_val" | sed "s|'|''|g" | sed 's|;||g')
        
    echo -n "$clean_val"
}

render_sql_template() {
    local template_file="$1"
    local target_file="$2"
    shift 2

    if [[ ! -f "$template_file" ]]; then
        log_error "Template missing: $template_file" && return 1
    fi

    cat "$template_file" > "$target_file"

    for pair in "$@"; do
        local key="${pair%%=*}"
        local raw_value="${pair#*=}"
            
        local safe_value
        safe_value=$(_sql_sanitize_value "$raw_value")
            
        sed -i "s|{{${key}}}|${safe_value}|g" "$target_file"
    done
}


_build_sqlplus_script() {
   local sql_content="$1"

   cat << EOF
SET PAGESIZE 50000
SET LINESIZE 4000
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON
SET TERMOUT OFF
SET TRIMSPOOL ON
SET COLSEP |
SET RECSEP OFF
ALTER SESSION SET NLS_DATE_FORMAT='${NLS_DATE_FORMAT}';

ALTER SESSION SET parallel_degree_policy=auto;
ALTER SESSION SET parallel_degree_limit=${PARALLEL_DEGREE};

${sql_content}

EXIT;
EOF
}

db_exec_remote_oracle() {
    local remote_host="$1"            
    local conn_str="$2" 
    local local_sql_file="$3"         
    local local_output_file="$4"

    log_info "SQL Delivery in progress to remote db client [${remote_host}] ..."

    local result=$(cat "${local_sql_file}" | \
        ssh -T "${remote_host}" \
            "sqlplus -S ${conn_str} @/dev/stdin" \
             > "${local_output_file}" \
             2> "${MODULE_TMP_RUN_DIR}/${MODUME_NAME}_remote_db_${RUN_ID}.err")

    local exit_code=$?
    if [ ${exit_code} -eq 0 ] && [ -n "${result}" ]; then
        local clean_result=$(echo "${result}" | \
            grep -v "^$" | \
            grep -v "^Connected" | \
            grep -v "^SQL>" | \
            grep -v "^\[" | \
            grep -v "^  ")
            
        if echo "${clean_result}" | grep -qi "ORA-\|ERROR\|SP2-"; then
            log_error  "SQL executed failed"
            echo "${clean_result}" | grep -i "ORA-\|ERROR\|SP2-" | head -5 >&2
            return 1
        fi
        log_success "Remote device [${remote_host}] successfully,result wrote back to ${local_output_file}"
        echo "${clean_result}"
        return 0
    else
        local err_msg=$(cat ${MODULE_TMP_RUN_DIR}/${MODUME_NAME}_remote_db_${RUN_ID}.err)
        log_error "Remote Oracle execute failed (Exit: $exit_code): ${err_msg}"
    
        if [ -n "${result}" ]; then
            log_error  "${result}"
        fi
        return 1
    fi
}
