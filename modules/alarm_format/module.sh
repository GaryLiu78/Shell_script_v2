#!/bin/bash

module_init() {
    local input_file="$1"
    local output_file="$2"

    [[ -f "$input_file" ]] || {
        log_error "Alarm input file not found: $input_file"
        return 1
    }
    
    mkdir -p "$(dirname "$output_file")" 
}

module_run() {
    local input_file="$1"
    local output_file="$2"

    log_info "Formatting alarm list"
    awk -F'\t' -v OFS=',' 'NF {
        gsub(/^CS_/, "", $7);
        gsub(/ DST$/, "", $4);
        split($9, sub_fields, /[:;]/);
        line = $7 OFS $4 OFS sub_fields[10] OFS sub_fields[4] OFS sub_fields[6] OFS sub_fields[8] OFS sub_fields[2];
        if (!seen[line]++) {
            print line;
        }
    }' "$input_file" > "$output_file"

    log_success "Formatted alarm list: $output_file"
    cat $output_file
}

module_cleanup() {
    return 0
}
