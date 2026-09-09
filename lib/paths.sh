#!/bin/bash

init_paths() {
    : "${LOG_BASE_DIR:=$PROJECT_ROOT/var/log}"
    : "${TEMP_BASE_DIR:=$PROJECT_ROOT/var/tmp}"
    : "${TEMP_RUN_DIR:=$TEMP_BASE_DIR/run}"
    : "${TEMP_KEEP_DIR:=$TEMP_BASE_DIR/keep}"
    : "${RESULT_BASE_DIR:=$PROJECT_ROOT/var/result}"
    : "${MODULES_BASE_DIR:=$PROJECT_ROOT/modules}"
    : "${PIPELINES_DIR:=$PROJECT_ROOT/pipelines}"

    export LOG_BASE_DIR TEMP_BASE_DIR TEMP_RUN_DIR TEMP_KEEP_DIR
    export RESULT_BASE_DIR MODULES_BASE_DIR PIPELINES_DIR

    mkdir -p "$LOG_BASE_DIR" "$TEMP_RUN_DIR" "$TEMP_KEEP_DIR" "$RESULT_BASE_DIR"
}

module_base_dir() {
    echo "$MODULES_BASE_DIR/$1"
}

module_data_dir() {
    echo "$(module_base_dir "$1")/data"
}

module_temp_run_dir() {
    echo "$TEMP_RUN_DIR/$1/$RUN_ID"
}

module_temp_keep_dir() {
    echo "$TEMP_KEEP_DIR/$1/$RUN_ID"
}

module_result_dir() {
    echo "$RESULT_BASE_DIR/$1"
}

ensure_module_dirs() {
    local module_name="$1"
    MODULE_DIR="$(module_base_dir "$module_name")"
    MODULE_DATA_DIR="$(module_data_dir "$module_name")"
    MODULE_TMP_RUN_DIR="$(module_temp_run_dir "$module_name")"
    MODULE_TMP_KEEP_DIR="$(module_temp_keep_dir "$module_name")"
    MODULE_RESULT_DIR="$(module_result_dir "$module_name")"

    export MODULE_RESULT_DIR MODULE_DIR MODULE_DATA_DIR MODULE_TMP_RUN_DIR MODULE_TMP_KEEP_DIR
    mkdir -p "$MODULE_RESULT_DIR" "$MODULE_TMP_RUN_DIR" "$MODULE_TMP_KEEP_DIR"
}
