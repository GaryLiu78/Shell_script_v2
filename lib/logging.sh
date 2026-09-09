#!/bin/bash

LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

LOG_LEVEL="${LOG_LEVEL:-INFO}"
[[ "${DEBUG:-false}" == "true" ]] && LOG_LEVEL="DEBUG"

_log_level_num() {
    case "${1:-INFO}" in
        DEBUG) echo "$LOG_LEVEL_DEBUG" ;;
        INFO) echo "$LOG_LEVEL_INFO" ;;
        WARN) echo "$LOG_LEVEL_WARN" ;;
        ERROR) echo "$LOG_LEVEL_ERROR" ;;
        *) echo "$LOG_LEVEL_INFO" ;;
    esac
}

_should_log() {
    local current required
    current=$(_log_level_num "$LOG_LEVEL")
    required=$(_log_level_num "$1")
    [[ "$required" -ge "$current" ]]
}

_format_log_message() {
    local level="$1"
    shift
    local logger_name="${MODULE_NAME:-run}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$logger_name] $*"
}

log_debug() {
    if _should_log DEBUG; then
        echo "$(_format_log_message DEBUG "$@")"
    fi
    return 0
}

log_info() {
    if _should_log INFO; then
        echo "$(_format_log_message INFO "$@")"
    fi
    return 0
}

log_warn() {
    if _should_log WARN; then
        echo "$(_format_log_message WARN "$@")" >&2
    fi
    return 0
}

log_error() {
    if _should_log ERROR; then
        echo "$(_format_log_message ERROR "$@")" >&2
    fi
    return 0
}

log_success() {
    echo "$(_format_log_message SUCCESS "$@")"
}

init_logging() {
    if [[ "${_LOG_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi

    local log_name="${MODULE_NAME:-run}"
    LOG_DIR="${LOG_DIR:-$LOG_BASE_DIR/$log_name}"
    LOG_FILE="${LOG_FILE:-$LOG_DIR/$RUN_ID.log}"
    export LOG_DIR LOG_FILE

    mkdir -p "$LOG_DIR"
    exec 3>&1 4>&2

    if [[ "${DISABLE_LOGGING:-false}" != "true" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    _LOG_INITIALIZED=true
    echo "============================================================================"
    echo "Logging system initialized"
    echo "Script: ${SCRIPT_NAME:-run.sh} | Log Level: $LOG_LEVEL"
    echo "Log File: $LOG_FILE"
    echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"
}
