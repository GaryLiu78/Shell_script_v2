#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/core.sh" ]]; then
    # shellcheck source=lib/core.sh
    source "$SCRIPT_DIR/lib/core.sh"
else
    echo "ERR: lib/core.sh not found" >&2
    exit 1
fi

VERSION="3.0.0"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

show_help() {
    cat <<EOF
${GREEN}Shellscript v${VERSION}${NC}

${YELLOW}Usage:${NC}
    ./run.sh ${BLUE}<command>${NC} [options]

${YELLOW}Commands:${NC}
    ${BLUE}nostream${NC}        Run the nostream pipeline
    ${BLUE}mcpacket${NC}        Run the multicast packet summary pipeline
    ${BLUE}hlsdaterange${NC}    Run the HLS daterange pipeline
    ${BLUE}pipeline${NC}        Run a named pipeline: ./run.sh pipeline <name>
    ${BLUE}list${NC}            List available pipelines
    ${BLUE}status${NC}          Show project status
    ${BLUE}clean${NC}           Clean old logs and temporary run files

${YELLOW}Options:${NC}
    ${BLUE}--debug${NC}     Enable debug logging
    ${BLUE}--help${NC}      Show this help

${YELLOW}Examples:${NC}
    ./run.sh nostream
    ./run.sh mcpacket
    ./run.sh hlsdaterange
    ./run.sh pipeline nostream --debug
EOF
}

cmd_list() {
    echo "${GREEN}Available pipelines:${NC}"
    local pipeline
    shopt -s nullglob
    for pipeline in "$PIPELINES_DIR"/*.pipeline.sh; do
        printf "  ${BLUE}%-16s${NC}\n" "$(basename "$pipeline" .pipeline.sh)"
    done
    shopt -u nullglob
    echo "  clean, status, list, help"
}

cmd_status() {
    echo "${GREEN}Project Status${NC}"
    echo "PROJECT_ROOT: $PROJECT_ROOT"
    echo "LOG_BASE_DIR: $LOG_BASE_DIR ($(du -sh "$LOG_BASE_DIR" 2>/dev/null | cut -f1))"
    echo "TEMP_BASE_DIR: $TEMP_BASE_DIR ($(du -sh "$TEMP_BASE_DIR" 2>/dev/null | cut -f1))"
    echo "RESULT_BASE_DIR: $RESULT_BASE_DIR ($(du -sh "$RESULT_BASE_DIR" 2>/dev/null | cut -f1))"
    echo "PIPELINES_DIR: $PIPELINES_DIR"
}

cmd_clean() {
    log_info "Cleaning old logs and temporary run files"
    [[ -d "$LOG_BASE_DIR" ]] && find "$LOG_BASE_DIR" -name "*.log" -mtime +"${CLEANUP_RETENTION_DAYS:-7}" -delete
    [[ -d "$TEMP_RUN_DIR" ]] && find "$TEMP_RUN_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
    log_success "Cleanup completed"
}

main() {
    local command="${1:-help}"
    shift || true

    local args=()
    local args_count=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --debug|-d)
                export DEBUG=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                args+=("$1")
		args_count=$((args_count + 1))
                shift
                ;;
        esac
    done

    init_project

   # simplify: 
   # nostream|mcpacket|hlsdaterange)
   #     run_pipeline "command" "${args[@]}"
   #     ;;

    case "$command" in
        nostream)
            if (( args_count > 0 )); then
                run_pipeline nostream "${args[@]}"
	    else
		run_pipeline nostream
	    fi
            ;;
        mcpacket)
            if (( args_count > 0 )); then
                run_pipeline mcpacket "${args[@]}"
            else
                run_pipeline mcpacket
            fi
            ;;
    hlsdaterange)
	    if (( args_count > 0 )); then
		run_pipeline hlsdaterange "${args[@]}"
	    else
		run_pipeline hlsdaterange
	    fi
	    ;;
        pipeline)
            # [[ "${#args[@]}" -gt 0 ]] || {
	    (( args_count > 0 )) || {
                log_error "Missing pipeline name"
                cmd_list
                exit 1
            }
            if (( args_count > 1 )); then
                run_pipeline "${args[0]}" "${args[@]:1}"
	    else
		run_pipeline "${args[0]}"
	    fi
            ;;
        clean)
            cmd_clean
            ;;
        status)
            cmd_status
            ;;
        list|ls)
            cmd_list
            ;;
        help|"")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            cmd_list
            exit 1
            ;;
    esac
}

main "$@"
