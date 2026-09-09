#!/bin/bash

PIPELINE_STEPS=(
    memdevassess
    memdbassess
)

find_step_index() {
    local target="$1"
    for idx in "${!PIPELINE_STEPS[@]}"; do
        if [[ "${PIPELINE_STEPS[$idx]}" == "$target" ]]; then
            echo "$idx"
            return
        fi
    done
        log_info "Step $target not found"
    exit 1
}

