#!/bin/bash

if [[ -n "${_CORE_LOADED:-}" ]]; then
    return 0
fi
readonly _CORE_LOADED=true

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"

export PROJECT_ROOT CONFIG_DIR

# shellcheck source=lib/logging.sh
source "$PROJECT_ROOT/lib/logging.sh"
# shellcheck source=lib/config.sh
source "$PROJECT_ROOT/lib/config.sh"
# shellcheck source=lib/paths.sh
source "$PROJECT_ROOT/lib/paths.sh"
# shellcheck source=lib/cleanup.sh
source "$PROJECT_ROOT/lib/cleanup.sh"
# shellcheck source=lib/modules.sh
source "$PROJECT_ROOT/lib/modules.sh"
# shellcheck source=lib/pipeline.sh
source "$PROJECT_ROOT/lib/pipeline.sh"
# shellcheck source=lib/oradbaccess.sh
source "$PROJECT_ROOT/lib/oradbaccess.sh"

init_project() {
    set -euo pipefail

    load_config global
    load_config oradbaccess
    init_paths

    : "${RUN_TS:=$(date +%Y%m%d_%H%M%S)}"
    : "${RUN_ID:=${RUN_TS}_$$}"
    export RUN_TS RUN_ID

    MODULE_NAME="${MODULE_NAME:-run}"
    export MODULE_NAME

    init_logging
    setup_traps
}

check_dependencies() {
    local missing=()
    local missing_count=0
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
	    missing_count=$((missing_count + 1))
        fi
    done

    # if [[ "${#missing[@]}" -gt 0 ]]; then
    if (( missing_count > 0 )); then
        log_error "Missing dependencies: ${missing[*]}"
        return 1
    fi
}
