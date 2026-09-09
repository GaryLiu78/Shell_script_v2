#!/bin/bash

module_init() {
    local input_file="$1"
    local output_file="$2"

    check_dependencies date ssh timeout grep awk cat

    [[ -f "$input_file" ]] || {
        log_error "Formatted device list not found: $input_file"
        return 1
    }

    mkdir -p "$MODULE_TMP_RUN_DIR" "$(dirname "$output_file")"
}

_execute_rowsize_sql() {
    local db_id="$1"
    local conn_string="$2"   
    
    local rowsizesql_filename="${TARGETDB_ROWSIZE_SQL##*/}"
    local tmp_sql_rowsize="${MODULE_TMP_RUN_DIR}/tmp_rendered_${db_id}_${rowsizesql_filename}"
    
    local conn_string=$(build_targetdb_connstring "${db_id}")
        
    render_sql_template "${TARGETDB_ROWSIZE_SQL}" "${tmp_sql_rowsize}" \
        "__REALBEGINTIME__=${TARGETDB_TARGETDATE}" \
        "__STATUS__=${TARGETDB_RECORDSTATUS}" \
        "__SAMPLE_ROWS__=${TARGETDB_SAMPLEROWS}"
    
    local local_output_file="${MODULE_TMP_RUN_DIR}/tmp_${rowsizesql_filename%.*}_${db_id}.txt"
    local local_dberr_file="${MODULE_TMP_RUN_DIR}/tmp_dberr_rowsize_${db_id}.txt"
    
    cat "${tmp_sql_rowsize}" | \
            ssh -q -T "${DB_CLIENT}" \
                "su - oracle -c 'sqlplus -s ${conn_string}'" \
            > "${local_output_file}" \
                2> "${local_dberr_file}"
        
    local exit_code=$?
    
    if [ ${exit_code} -ne 0 ] || [ -s "${local_dberr_file}" ]; then
        log_error "DB ${db_id} ROWSIZE query failure"
        return 1
    fi
    
    local data_line=$(awk '
            /^[[:space:]]*[0-9.]+/ && !/SAMPLE_ROWS/ && !/AVG_ROW_LEN/ && !/^-/ {
                print $0
            exit
            }
        ' "${local_output_file}" | sed -E 's/[[:space:]]*\|[[:space:]]*/ /g' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    
        
    if [ -z "${data_line}" ]; then
        echo "0 0"
    else
        echo "${data_line}"
    fi
}

_execute_totalrows_sql() {
    local db_id="$1"
    local conn_string="$2"   
    
    local totalrowssql_filename="${TARGETDB_TOTALROWS_SQL##*/}"
    local tmp_sql_totalrows="${MODULE_TMP_RUN_DIR}/tmp_rendered_${db_id}_${totalrowssql_filename}"
   
    local conn_string=$(build_targetdb_connstring "${db_id}")
        
    render_sql_template "${TARGETDB_TOTALROWS_SQL}" "${tmp_sql_totalrows}" \
        "__REALBEGINTIME__=${TARGETDB_TARGETDATE}" \
        "__STATUS__=${TARGETDB_RECORDSTATUS}"
    
    local local_output_file="${MODULE_TMP_RUN_DIR}/tmp_${totalrowssql_filename%.*}_${db_id}.txt"
    local local_dberr_file="${MODULE_TMP_RUN_DIR}/tmp_dberr_totalrows_${db_id}.txt"
    
    cat "${tmp_sql_totalrows}" | \
            ssh -q -T "${DB_CLIENT}" \
                "su - oracle -c 'sqlplus -s ${conn_string}'" \
            > "${local_output_file}" \
            2> "${local_dberr_file}"
        
    local exit_code=$?
    
    if [ ${exit_code} -ne 0 ] || [ -s "${local_dberr_file}" ]; then
        log_error "DB ${db_id} TOTALROWS failure"
        return 1
    fi
    
    local data_line=$(awk '
            /^[[:space:]]*[0-9.]+/ && !/TOTAL_ROWS/ && !/^-/ {
            print $0
            exit
            }
        ' "${local_output_file}" | sed -E 's/[[:space:]]*\|[[:space:]]*/ /g' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
 
    if [ -z "${data_line}" ]; then
            echo "0"
    else
        echo "${data_line}"
    fi
}

_execute_batch_sql() {
    local db_id="$1"
    
    local conn_string=$(build_targetdb_connstring "${db_id}")
        
    local sample_rows=0
    local avg_row_len=0
    local total_rows=0
    
    local rows_result=$(_execute_rowsize_sql "${db_id}" "${conn_string}")
    if [ $? -eq 0 ]; then
        sample_rows=$(echo "${rows_result}" | awk '{print $1}')
        avg_row_len=$(echo "${rows_result}" | awk '{print $2}')
    fi
        
    local total_result=$(_execute_totalrows_sql "${db_id}" "${conn_string}")
    if [ $? -eq 0 ]; then
            total_rows=$(echo "${total_result}" | awk '{print $1}')
    fi
    
    echo "${sample_rows} ${avg_row_len} ${total_rows}"
}

module_run() {
    local input_file="$1"
    local output_file="$2"
    local db_id
        
    read -r -a ARRAY_IDS <<< "${TARGET_DB_IDS}"
    
    local total_sample=0
    local weighted_sum=0
    local total_rows_all=0
    local success_count=0
    local fail_count=0
    
    for i in "${!ARRAY_IDS[@]}"; do
        db_id="${ARRAY_IDS[$i]}"
        log_info "========== DB retriving: ${db_id} =========="
        
        local line=$(_execute_batch_sql "${db_id}")
        local sample=$(echo "${line}" | awk '{print $1}')
        local avg_len=$(echo "${line}" | awk '{print $2}')
        local total_rows=$(echo "${line}" | awk '{print $3}')

        log_info "db${db_id}: sample=${sample}, avg=${avg_len}, total_rows=${total_rows}"

        if [[ "${sample}" =~ ^[0-9.]+$ ]] && [[ "${avg_len}" =~ ^[0-9.]+$ ]] && [ "${sample}" != "0" ]; then
            total_sample=$((total_sample + sample))
            weighted_sum=$(echo "${weighted_sum} + ${sample} * ${avg_len}" | bc 2>/dev/null || echo "0")
            success_count=$((success_count + 1))
            log_info "Sample Rows=${sample}, AVG Size per row=${avg_len}"
        else
            fail_count=$((fail_count + 1))
            log_warn "  Invalid data: Sample Rows='${sample}', AVG Size per row='${avg_len}'"
        fi
        
        if [[ "${total_rows}" =~ ^[0-9]+$ ]] && [ "${total_rows}" -gt 0 ]; then
   	    total_rows_all=$((total_rows_all + total_rows))
        fi
    done
    
    local final_avg=0
    if [ "${total_sample}" -ne 0 ]; then
        final_avg=$(echo "scale=0; ${weighted_sum} / ${total_sample} + 1 " | bc 2>/dev/null || echo "0")
	      total_rowsize=$((final_avg * total_rows_all))
    fi
        
    {
        echo "=========================================="
        echo "Results"
        echo "=========================================="
        echo "Total (SAMPLE_ROWS): ${total_sample}"
        echo "Total (SAMPLE_ROWS_Size): ${weighted_sum}"
	      echo "Estimated (AVG_ROWSIZE): ${final_avg}"
        echo "Actual (TOTAL_ROWS): ${total_rows_all}"
	      echo "Estimated (TOTAL_ROWSIZE): ${total_rowsize}"
        echo "=========================================="
    } > "${output_file}"
        
    echo "${final_avg} ${total_rows_all} ${total_rowsize}"
}

module_cleanup() {
    safe_rm_dir "$MODULE_TMP_RUN_DIR" 2>/dev/null || true
}
