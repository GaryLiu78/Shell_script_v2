#!/bin/bash

load_module_file() {
    local module_name="$1"
    local module_file="$MODULES_BASE_DIR/$module_name/module.sh"

    [[ -f "$module_file" ]] || {
        log_error "Module file not found: $module_file"
        return 1
    }

    # shellcheck source=/dev/null
    source "$module_file"
}

run_module_step() {
    local module_name="$1"
    shift

    (
        MODULE_NAME="$module_name"
	      MODULE_INPUT="${1:-}"
	      MODULE_OUTPUT="${2:-}"
        export MODULE_NAME MODULE_INPUT MODULE_OUTPUT

        load_config "$module_name"
        ensure_module_dirs "$module_name"
        load_module_file "$module_name"

        if declare -f module_init >/dev/null; then
            module_init "$@"
        fi

        module_run "$@"

        if declare -f module_cleanup >/dev/null; then
            module_cleanup "$@"
        fi
    )
}
