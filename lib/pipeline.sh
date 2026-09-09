#!/bin/bash

run_pipeline() {
    local pipeline_name="$1"
    shift || true

    PIPELINE_STEPS=()
    PIPELINE_INPUT=""
    PIPELINE_OUTPUT=""

    load_pipeline_config "$pipeline_name"
    local pipeline_file="$PIPELINES_DIR/$pipeline_name.pipeline.sh"
    [[ -f "$pipeline_file" ]] || {
        log_error "Pipeline not found: $pipeline_file"
        return 1
    }
    # shellcheck source=/dev/null
    source "$pipeline_file"
    local step_count="${#PIPELINE_STEPS[@]}"
    # [[ "${#PIPELINE_STEPS[@]}" -gt 0 ]] || {
    [[ "$step_count" -gt 0 ]] || {
        log_error "Pipeline has no steps: $pipeline_name"
        return 1
    }

    [[ -n "$PIPELINE_INPUT" ]] || {
        log_error "Pipeline input is empty: $pipeline_name"
        return 1
    }

    local pipeline_run_dir="$TEMP_RUN_DIR/pipelines/$pipeline_name/$RUN_ID"
    mkdir -p "$pipeline_run_dir"
    register_cleanup_dir "$pipeline_run_dir"

    log_info "Pipeline started: $pipeline_name"
    log_info "Pipeline input: $PIPELINE_INPUT"

    local current_effective_input="$PIPELINE_INPUT"
    local output_file step index next_step_file
    i=0
    while [[ $i -lt $step_count ]]; do
        local step="${PIPELINE_STEPS[$i]}"
        index=$((i + 1))
        load_module_config "$step"
        module_tmp_run_dir="$(module_temp_run_dir "$step")"
	      mkdir -p "$module_tmp_run_dir"
	      next_step_file="$module_tmp_run_dir/module.next_step"

	      log_info "NEXT STEP lookup $next_step_file"
        if [[ "$index" -eq "$step_count" && -n "$PIPELINE_OUTPUT" ]]; then    
            output_file="$PIPELINE_OUTPUT"
        else
            output_file="$pipeline_run_dir/${index}_${step}.out"
        fi
        log_info "Pipeline step $index/$step_count: $step"
	      NEXT_STEP=""

        if [[ ! -f "$current_effective_input" ]]; then
            log_info "no input/output file"
            run_module_step "$step"
        else
            log_info "with input/output fiile: $current_effective_input"
            run_module_step "$step" "$current_effective_input" "$output_file"
        fi
        local rc=$?
	      #input_file="$output_file"
        if [[ $rc -eq 99 ]]; then
            echo "Pipeline stopped by $step"
            break
	      elif [[ $rc -ne 0 ]]; then
	          log_error "Step $step failed unexpectedly with exit code $rc"
	          return "$rc" 
	      fi
	      if [[ -f "$output_file" ]]; then
            current_effective_input="$output_file"
        fi
	      if [[ -f "${next_step_file}" ]]; then
	          NEXT_STEP=$(cat "${next_step_file}")
        fi

        if [[ -n "${NEXT_STEP:-}" ]]; then
            i=$(find_step_index "$NEXT_STEP")
            unset NEXT_STEP
            continue
        fi

	      ((++i))
    done

    log_success "Pipeline completed: $pipeline_name"
    log_success "Pipeline output: $current_effective_input"
}
