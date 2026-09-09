#!/bin/bash

load_config() {
    local name="$1"
    local config_file="$CONFIG_DIR/$name.conf"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        log_info "Config loaded: $name"
    else
        log_debug "Config not found: $config_file"
    fi
    return 0
}

load_module_config() {
    local name="$1"
    local config_file="$MODULES_BASE_DIR/$name/$name.conf"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        log_info "Module Config loaded: $name"
    else
        log_debug "Module Config not found: $config_file"
    fi
    return 0
}

load_pipeline_config() {
    local name="$1"
    local config_file="$CONFIG_DIR/pipelines/$name.conf"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        log_info "Pipeline config loaded: $name"
    else
        log_debug "Pipeline config not found: $config_file"
    fi
    return 0
}

