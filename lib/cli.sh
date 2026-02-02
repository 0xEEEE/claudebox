#!/usr/bin/env bash
# Unified CLI parser for ClaudeBox
# Implements the four-bucket architecture for clean, predictable CLI handling

# ============================================================================
# CLI PARSER - SINGLE SOURCE OF TRUTH
# ============================================================================

# Four flag buckets (Bash 3.2 compatible - no associative arrays)
readonly HOST_ONLY_FLAGS=(--verbose rebuild)
readonly CONTROL_FLAGS=(--enable-sudo --disable-firewall --no-host-skills --no-host-lsp)
readonly SCRIPT_COMMANDS=(shell create slot slots revoke profiles projects profile info help -h --help add remove install allowlist clean save project tmux kill)

# Initialize global CLI arrays (Bash 3.2 requires this before any access)
CLI_HOST_FLAGS=()
CLI_CONTROL_FLAGS=()
CLI_SCRIPT_COMMAND=""
CLI_PASS_THROUGH=()

# parse_cli_args - Central CLI parsing with four-bucket architecture
# Usage: parse_cli_args "$@"
# Sets global variables:
#   host_flags: Array of host-only flags (help, version, etc)
#   control_flags: Array of control flags (verbose, enable-sudo, etc)
#   script_command: Single command for ClaudeBox to execute
#   pass_through: Array of args to pass to Claude in container
# Note: Each argument goes into exactly ONE bucket - no duplication
parse_cli_args() {
    # Bash 3.2 safe: handle case when no arguments are passed
    local all_args=()
    if [[ $# -gt 0 ]]; then
        all_args=("$@")
    fi

    # Initialize bucket arrays
    host_flags=()
    control_flags=()
    script_command=""
    pass_through=()

    # Single parsing loop - each arg goes into exactly ONE bucket
    local found_script_command=false

    # Bash 3.2 safe array expansion
    if [[ ${#all_args[@]} -gt 0 ]]; then
        for arg in "${all_args[@]}"; do
        if [[ " ${HOST_ONLY_FLAGS[*]} " == *" $arg "* ]]; then
            # Bucket 1: Host-only flags
            host_flags+=("$arg")
        elif [[ " ${CONTROL_FLAGS[*]} " == *" $arg "* ]]; then
            # Bucket 2: Control flags (pass to container)
            control_flags+=("$arg")
        elif [[ "$found_script_command" == "false" ]] && [[ " ${SCRIPT_COMMANDS[*]} " == *" $arg "* ]]; then
            # Bucket 3: Script commands (first one wins)
            script_command="$arg"
            found_script_command=true
        else
            # Bucket 4: Pass-through (everything else)
            pass_through+=("$arg")
        fi
        done
    fi

    # Export results for use by main script
    # Bash 3.2 safe array expansion
    if [[ ${#host_flags[@]} -gt 0 ]]; then
        export CLI_HOST_FLAGS=("${host_flags[@]}")
    else
        export CLI_HOST_FLAGS=()
    fi
    if [[ ${#control_flags[@]} -gt 0 ]]; then
        export CLI_CONTROL_FLAGS=("${control_flags[@]}")
    else
        export CLI_CONTROL_FLAGS=()
    fi
    export CLI_SCRIPT_COMMAND="$script_command"
    if [[ ${#pass_through[@]} -gt 0 ]]; then
        export CLI_PASS_THROUGH=("${pass_through[@]}")
    else
        export CLI_PASS_THROUGH=()
    fi
}

# Process host-only flags and set environment variables
process_host_flags() {
    # Bash 3.2 safe: check if array is set and has elements
    if [[ -n "${CLI_HOST_FLAGS+x}" ]] && [[ ${#CLI_HOST_FLAGS[@]} -gt 0 ]]; then
        for flag in "${CLI_HOST_FLAGS[@]}"; do
            case "$flag" in
                --verbose)
                    export VERBOSE=true
                    ;;
                rebuild)
                    export REBUILD=true
                    ;;
                tmux)
                    export CLAUDEBOX_WRAP_TMUX=true
                    ;;
            esac
        done
    fi
}

# Get command requirements - returns one of:
# "none" - pure host command, no Docker or image needed
# "image" - needs image name but not Docker running
# "docker" - needs Docker running and will run container
get_command_requirements() {
    local cmd="${1:-}"
    local subcommand="${2:-}"
    
    case "$cmd" in
        # Pure host commands - no Docker or image needed
        profiles|projects|help|-h|--help|slots|create|revoke|clean|import|unlink|kill)
            echo "none"
            ;;
        # Commands that need image name but not Docker
        info|profile|add|remove|install|allowlist|save)
            echo "image"
            ;;
        # Commands that need Docker and will run containers
        shell|project|rebuild|update|config|mcp|migrate-installer|tmux|slot|"")
            echo "docker"
            ;;
        # Unknown commands are forwarded to Claude in container
        *)
            echo "docker"
            ;;
    esac
}

# Legacy function for compatibility
requires_docker_image() {
    local cmd="${1:-}"
    local req=$(get_command_requirements "$cmd")
    [[ "$req" == "docker" ]]
}

# Check if current command requires a slot
requires_slot() {
    local cmd="${1:-}"
    
    # Commands that need a slot
    case "$cmd" in
        shell|update|config|mcp|migrate-installer|create|slot|"")
            return 0  # true - needs slot
            ;;
        *)
            return 1  # false - doesn't need slot
            ;;
    esac
}

# Debug output for parsed arguments (only if VERBOSE=true)
debug_parsed_args() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        # Bash 3.2 safe array expansion
        printf "[DEBUG] CLI Parser Results:\n" >&2
        printf "[DEBUG]   Host flags: %s\n" "${CLI_HOST_FLAGS[*]:-}" >&2
        printf "[DEBUG]   Control flags: %s\n" "${CLI_CONTROL_FLAGS[*]:-}" >&2
        printf "[DEBUG]   Script command: %s\n" "${CLI_SCRIPT_COMMAND:-}" >&2
        printf "[DEBUG]   Pass-through: %s\n" "${CLI_PASS_THROUGH[*]:-}" >&2
    fi
}

# Export all functions
export -f parse_cli_args process_host_flags get_command_requirements requires_docker_image requires_slot debug_parsed_args