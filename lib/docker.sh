#!/usr/bin/env bash
# Functions for managing Docker containers, images, and runtime.

# Docker checks
check_docker() {
    command -v docker >/dev/null || return 1
    docker info >/dev/null 2>&1 || return 2
    docker ps >/dev/null 2>&1 || return 3
    return 0
}

install_docker() {
    warn "Docker is not installed."
    cecho "Would you like to install Docker now? (y/n)" "$CYAN"
    read -r response
    [[ "$response" =~ ^[Yy]$ ]] || error "Docker is required. Visit: https://docs.docker.com/engine/install/"

    info "Installing Docker..."

    [[ -f /etc/os-release ]] && . /etc/os-release || error "Cannot detect OS"

    case "${ID:-}" in
        ubuntu|debian)
            warn "Installing Docker requires sudo privileges..."
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl gnupg lsb-release
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/$ID/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora|rhel|centos)
            warn "Installing Docker requires sudo privileges..."
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        arch|manjaro)
            warn "Installing Docker requires sudo privileges..."
            sudo pacman -S --noconfirm docker
            sudo systemctl start docker
            sudo systemctl enable docker
            ;;
        *)
            error "Unsupported OS: ${ID:-unknown}. Visit: https://docs.docker.com/engine/install/"
            ;;
    esac

    success "Docker installed successfully!"
    configure_docker_nonroot
}

configure_docker_nonroot() {
    warn "Configuring Docker for non-root usage..."
    warn "This requires sudo to add you to the docker group..."

    getent group docker >/dev/null || sudo groupadd docker
    sudo usermod -aG docker "$USER"

    success "Docker configured for non-root usage!"
    warn "You need to log out and back in for group changes to take effect."
    warn "Or run: ${CYAN}newgrp docker"
    warn "Then run 'claudebox' again."
    info "Trying to activate docker group in current shell..."
    exec newgrp docker
}

docker_exec_root() {
    docker exec -u root "$@"
}

docker_exec_user() {
    docker exec -u "$DOCKER_USER" "$@"
}

# run_claudebox_container - Main entry point for container execution
# Usage: run_claudebox_container <container_name> <mode> [args...]
# Args:
#   container_name: Name for the container (empty for auto-generated)
#   mode: "interactive", "detached", "pipe", or "attached"
#   args: Commands to pass to claude in container
# Returns: Exit code from container
# Note: Handles all mounting, environment setup, and security configuration
run_claudebox_container() {
    local container_name="$1"
    local run_mode="$2"  # "interactive", "detached", "pipe", or "attached"
    shift 2
    local container_args=("$@")
    
    # Handle "attached" mode - start detached, wait, then attach
    if [[ "$run_mode" == "attached" ]]; then
        # Start detached
        # Bash 3.2 safe array expansion
        run_claudebox_container "$container_name" "detached" ${container_args[@]+"${container_args[@]}"} >/dev/null
        
        # Show progress while container initializes
        fillbar
        
        # Wait for container to be ready
        while ! docker exec "$container_name" true ; do
            sleep 0.1
        done
        
        fillbar stop
        
        # Attach to ready container
        docker attach "$container_name"
        
        return
    fi
    
    local docker_args=()
    
    # Set run mode
    case "$run_mode" in
        "interactive")
            # Only use -it if we have a TTY
            if [ -t 0 ] && [ -t 1 ]; then
                docker_args+=("-it")
            fi
            # Use --rm for auto-cleanup unless it's an admin container
            # Admin containers need to persist so we can commit changes
            if [[ -z "$container_name" ]] || [[ "$container_name" != *"admin"* ]]; then
                docker_args+=("--rm")
            fi
            if [[ -n "$container_name" ]]; then
                docker_args+=("--name" "$container_name")
            fi
            docker_args+=("--init")
            ;;
        "detached")
            docker_args+=("-d")
            if [[ -n "$container_name" ]]; then
                docker_args+=("--name" "$container_name")
            fi
            ;;
        "pipe")
            docker_args+=("--rm" "--init")
            ;;
    esac
    
    # Always check for tmux socket and mount if available (or create one)
    local tmux_socket=""
    local tmux_socket_dir=""
    
    # If TMUX env var is set, extract socket path from it
    if [[ -n "${TMUX:-}" ]]; then
        # TMUX format is typically: /tmp/tmux-1000/default,23456,0
        tmux_socket="${TMUX%%,*}"
        tmux_socket_dir=$(dirname "$tmux_socket")
    else
        # Look for existing tmux socket or determine where to create one
        local uid=$(id -u)
        local default_socket_dir="/tmp/tmux-$uid"
        
        # Check common locations for existing sockets
        for socket_dir in "$default_socket_dir" "/var/run/tmux-$uid" "$HOME/.tmux"; do
            if [[ -d "$socket_dir" ]]; then
                # Find any socket in the directory
                for socket in "$socket_dir"/default "$socket_dir"/*; do
                    if [[ -S "$socket" ]]; then
                        tmux_socket="$socket"
                        tmux_socket_dir="$socket_dir"
                        break
                    fi
                done
                [[ -n "$tmux_socket" ]] && break
            fi
        done
        
        # If no socket found, ensure we have a socket directory for potential tmux usage
        if [[ -z "$tmux_socket" ]]; then
            tmux_socket_dir="$default_socket_dir"
            # Create the socket directory if it doesn't exist
            if [[ ! -d "$tmux_socket_dir" ]]; then
                mkdir -p "$tmux_socket_dir"
                chmod 700 "$tmux_socket_dir"
            fi
            
            # Check if tmux is installed and create a detached session if so
            if command -v tmux >/dev/null 2>&1; then
                # Create a minimal tmux server without attaching
                # This creates the socket but doesn't start any session
                tmux -S "$tmux_socket_dir/default" start-server \; 2>/dev/null || true
                if [[ -S "$tmux_socket_dir/default" ]]; then
                    tmux_socket="$tmux_socket_dir/default"
                    if [[ "$VERBOSE" == "true" ]]; then
                        echo "[DEBUG] Created tmux server socket at: $tmux_socket" >&2
                    fi
                fi
            fi
        fi
    fi
    
    # Mount the socket and directory if we have them
    # Security fix: Validate socket directory permissions before mounting
    if [[ -n "$tmux_socket_dir" ]] && [[ -d "$tmux_socket_dir" ]]; then
        # Check socket directory permissions
        local socket_perms
        if [[ "$HOST_OS" == "macOS" ]]; then
            socket_perms=$(stat -f %A "$tmux_socket_dir" 2>/dev/null || echo "")
        else
            socket_perms=$(stat -c %a "$tmux_socket_dir" 2>/dev/null || echo "")
        fi
        # Warn if world-writable (last digit is 7 or has write bit)
        if [[ -n "$socket_perms" ]] && [[ "${socket_perms: -1}" =~ [2367] ]]; then
            echo "[SECURITY WARNING] Tmux socket directory has world-writable permissions: $tmux_socket_dir ($socket_perms)" >&2
        fi
        # Always mount the socket directory
        docker_args+=(-v "$tmux_socket_dir:$tmux_socket_dir")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Mounting tmux socket directory: $tmux_socket_dir" >&2
        fi
        
        # Mount specific socket if it exists
        if [[ -n "$tmux_socket" ]] && [[ -S "$tmux_socket" ]]; then
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Tmux socket found at: $tmux_socket" >&2
            fi
        fi
        
        # Pass TMUX env var if available
        [[ -n "${TMUX:-}" ]] && docker_args+=(-e "TMUX=$TMUX")
    fi
    
    # Standard configuration for ALL containers
    docker_args+=(
        -w /workspace
        -v "$PROJECT_DIR":/workspace
        -v "$PROJECT_PARENT_DIR":/home/$DOCKER_USER/.claudebox
    )
    
    # Ensure .claude directory exists
    if [[ ! -d "$PROJECT_SLOT_DIR/.claude" ]]; then
        mkdir -p "$PROJECT_SLOT_DIR/.claude"
    fi
    
    docker_args+=(-v "$PROJECT_SLOT_DIR/.claude":/home/$DOCKER_USER/.claude)
    
    # Mount .claude.json only if it already exists (from previous session)
    # Security fix: Validate file permissions before mounting
    if [[ -f "$PROJECT_SLOT_DIR/.claude.json" ]]; then
        # Check and fix permissions if world-readable
        local file_perms
        if [[ "$HOST_OS" == "macOS" ]]; then
            file_perms=$(stat -f %A "$PROJECT_SLOT_DIR/.claude.json" 2>/dev/null || echo "")
        else
            file_perms=$(stat -c %a "$PROJECT_SLOT_DIR/.claude.json" 2>/dev/null || echo "")
        fi
        # If permissions allow group/other read, fix them
        if [[ -n "$file_perms" ]] && [[ ! "$file_perms" =~ ^[67]00$ ]]; then
            chmod 600 "$PROJECT_SLOT_DIR/.claude.json" 2>/dev/null || true
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[DEBUG] Fixed .claude.json permissions (was $file_perms, now 600)" >&2
            fi
        fi
        docker_args+=(-v "$PROJECT_SLOT_DIR/.claude.json":/home/$DOCKER_USER/.claude.json)
    fi
    
    # Mount .config directory
    docker_args+=(-v "$PROJECT_SLOT_DIR/.config":/home/$DOCKER_USER/.config)
    
    # Mount .cache directory
    docker_args+=(-v "$PROJECT_SLOT_DIR/.cache":/home/$DOCKER_USER/.cache)
    
    # Mount SSH agent socket only - never mount host SSH directory or config
    # Security: Private keys and host config never enter container
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && [[ -S "$SSH_AUTH_SOCK" ]]; then
        # Use SSH agent socket (keys stay on host, never enter container)
        docker_args+=(-v "$SSH_AUTH_SOCK":/tmp/ssh-agent.sock:ro)
        docker_args+=(-e "SSH_AUTH_SOCK=/tmp/ssh-agent.sock")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Using SSH agent socket for authentication" >&2
        fi
    else
        # No SSH agent available - warn user but don't mount sensitive directories
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] SSH agent not available - SSH authentication disabled in container" >&2
        fi
    fi
    # Note: SSH config is initialized in docker-entrypoint with safe defaults (GitHub only)
    # Host's ~/.ssh/config is never mounted to prevent information leakage

    # Mount host skills directory for layered skill access
    # Default: enabled. Use --no-host-skills to disable
    # Security fix: Check both container_args and CLI_CONTROL_FLAGS for control flags
    # Bash 3.2 safe array expansion
    local host_skills_enabled=true
    for flag in ${container_args[@]+"${container_args[@]}"} ${CLI_CONTROL_FLAGS[@]+"${CLI_CONTROL_FLAGS[@]}"}; do
        if [[ "$flag" == "--no-host-skills" ]]; then
            host_skills_enabled=false
            break
        fi
    done

    if [[ "$host_skills_enabled" == "true" ]] && [[ -d "$HOME/.claude/skills" ]]; then
        docker_args+=(-v "$HOME/.claude/skills":"/mnt/host-skills:ro")
        docker_args+=(-e "CLAUDEBOX_HOST_SKILLS=true")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Mounting host skills from ~/.claude/skills" >&2
        fi
    else
        docker_args+=(-e "CLAUDEBOX_HOST_SKILLS=false")
    fi

    # Mount host plugins directory for LSP and other plugin access
    # Default: enabled. Use --no-host-lsp to disable
    # Security fix: Check both container_args and CLI_CONTROL_FLAGS for control flags
    # Bash 3.2 safe array expansion
    local host_lsp_enabled=true
    for flag in ${container_args[@]+"${container_args[@]}"} ${CLI_CONTROL_FLAGS[@]+"${CLI_CONTROL_FLAGS[@]}"}; do
        if [[ "$flag" == "--no-host-lsp" ]]; then
            host_lsp_enabled=false
            break
        fi
    done

    if [[ "$host_lsp_enabled" == "true" ]] && [[ -d "$HOME/.claude/plugins" ]]; then
        docker_args+=(-v "$HOME/.claude/plugins":"/mnt/host-plugins:ro")
        docker_args+=(-e "CLAUDEBOX_HOST_LSP=true")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Mounting host plugins from ~/.claude/plugins" >&2
        fi
    else
        docker_args+=(-e "CLAUDEBOX_HOST_LSP=false")
    fi

    # Mount bundled claudebox plugins (e.g., ty-lsp)
    local bundled_plugins_dir="${CLAUDEBOX_HOME:-$HOME/.claudebox}/source/plugins"
    if [[ -d "$bundled_plugins_dir" ]]; then
        docker_args+=(-v "$bundled_plugins_dir":"/mnt/claudebox-plugins:ro")
        docker_args+=(-e "CLAUDEBOX_BUNDLED_PLUGINS=true")
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Mounting bundled plugins from $bundled_plugins_dir" >&2
        fi
    fi

    # Mount .env file if it exists in the project directory
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        docker_args+=(-v "$PROJECT_DIR/.env":/workspace/.env:ro)
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Mounting .env file from project directory" >&2
        fi
    fi
    
    # Parse and prepare MCP servers for native --mcp-config support
    # Check for jq dependency first - fail fast with clear error message
    if ! command -v jq >/dev/null 2>&1; then
        printf "ERROR: jq is required for MCP server configuration but not installed.\n" >&2
        printf "Please install jq to use MCP server integration:\n" >&2
        printf "  macOS: brew install jq\n" >&2
        printf "  Ubuntu/Debian: apt-get install jq\n" >&2
        printf "  RHEL/CentOS: yum install jq\n" >&2
        exit 1
    fi
    
    # Helper function to create and merge MCP config files
    create_mcp_config_file() {
        local config_file="$1"
        local temp_file="$2"
        
        # Create temporary file with secure random name and restrictive permissions
        # Security fix: Use random suffix instead of predictable timestamp+pid
        local mcp_file=$(mktemp /tmp/claudebox-mcp-XXXXXXXXXXXXXX.json 2>/dev/null || mktemp)
        chmod 600 "$mcp_file"
        mcp_temp_files+=("$mcp_file")
        
        # Extract mcpServers if they exist
        if [[ -f "$config_file" ]] && jq -e '.mcpServers' "$config_file" >/dev/null 2>&1; then
            if [[ -f "$temp_file" ]]; then
                # Merge with existing temp file
                jq -s '.[0].mcpServers * .[1].mcpServers | {mcpServers: .}' \
                    "$temp_file" "$config_file" > "$mcp_file" 2>/dev/null
            else
                # Create new config file
                jq '{mcpServers: .mcpServers}' "$config_file" > "$mcp_file" 2>/dev/null
            fi
            printf "%s" "$mcp_file"
        else
            rm -f "$mcp_file"
            printf ""
        fi
    }
    
    local project_mcp_file=""

    # Track all temporary MCP files for cleanup
    declare -a mcp_temp_files=()

    # Set up cleanup trap for temporary MCP config files
    # Bash 3.2 safe: check if variable exists AND array length before iteration
    cleanup_mcp_files() {
        # Check if mcp_temp_files exists and has elements
        if [[ -n "${mcp_temp_files+x}" ]] && [[ ${#mcp_temp_files[@]} -gt 0 ]]; then
            local file
            for file in "${mcp_temp_files[@]}"; do
                if [[ -f "$file" ]]; then
                    rm -f "$file"
                fi
            done
        fi
        # Check if project_mcp_file exists and is set
        if [[ -n "${project_mcp_file+x}" ]] && [[ -n "$project_mcp_file" ]] && [[ -f "$project_mcp_file" ]]; then
            rm -f "$project_mcp_file"
        fi
    }
    trap cleanup_mcp_files EXIT
    
    # Security: Do NOT read MCP config from host's ~/.claude.json
    # This prevents exposing host MCP server credentials to the container
    # MCP servers should be configured per-project in:
    #   - $PROJECT_DIR/.claude/settings.json (shared, can be committed)
    #   - $PROJECT_DIR/.claude/settings.local.json (local, add to .gitignore)

    # Create project MCP config file by merging project configs
    # Start with empty config file for merging
    # Security fix: Use random suffix instead of predictable timestamp+pid
    local temp_project_file=$(mktemp /tmp/claudebox-project-XXXXXXXXXXXXXX.json 2>/dev/null || mktemp)
    chmod 600 "$temp_project_file"
    mcp_temp_files+=("$temp_project_file")
    echo '{"mcpServers":{}}' > "$temp_project_file"
    
    # Merge shared project settings first
    local merged_file=""
    if [[ -f "$PROJECT_DIR/.claude/settings.json" ]]; then
        merged_file=$(create_mcp_config_file "$PROJECT_DIR/.claude/settings.json" "$temp_project_file")
        if [[ -n "$merged_file" ]]; then
            mv "$merged_file" "$temp_project_file"
        fi
    fi
    
    # Merge local project settings (highest priority)
    if [[ -f "$PROJECT_DIR/.claude/settings.local.json" ]]; then
        merged_file=$(create_mcp_config_file "$PROJECT_DIR/.claude/settings.local.json" "$temp_project_file")
        if [[ -n "$merged_file" ]]; then
            mv "$merged_file" "$temp_project_file"
        fi
    fi
    
    # Check if we have any project servers
    local project_count=$(jq '.mcpServers | length' "$temp_project_file" 2>/dev/null || echo "0")
    if [[ "$project_count" -gt 0 ]]; then
        project_mcp_file="$temp_project_file"
        if [[ "$VERBOSE" == "true" ]]; then
            printf "Found %s project MCP servers\n" "$project_count" >&2
        fi
        docker_args+=(-v "$project_mcp_file":/tmp/project-mcp-config.json:ro)
        if [[ "$VERBOSE" == "true" ]]; then
            echo "[DEBUG] Mounting project MCP configuration file" >&2
        fi
    else
        rm -f "$temp_project_file"
        project_mcp_file=""
    fi
    
    
    # Add environment variables
    local project_name=$(basename "$PROJECT_DIR")
    local slot_name=$(basename "$PROJECT_SLOT_DIR")
    
    # Calculate slot index for hostname
    local slot_index=1  # default if we can't determine
    if [[ -n "$PROJECT_PARENT_DIR" ]] && [[ -n "$slot_name" ]]; then
        slot_index=$(get_slot_index "$slot_name" "$PROJECT_PARENT_DIR" 2>/dev/null || echo "1")
    fi
    
    # Security fix: Pass API key via file instead of environment variable
    # Environment variables are visible in docker inspect and process listings
    local api_key_file=""
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        api_key_file=$(mktemp /tmp/claudebox-apikey-XXXXXXXXXXXXXX 2>/dev/null || mktemp)
        chmod 600 "$api_key_file"
        printf '%s' "$ANTHROPIC_API_KEY" > "$api_key_file"
        mcp_temp_files+=("$api_key_file")
        docker_args+=(-v "$api_key_file":/tmp/.anthropic_api_key:ro)
        docker_args+=(-e "ANTHROPIC_API_KEY_FILE=/tmp/.anthropic_api_key")
    fi

    docker_args+=(
        -e "NODE_ENV=${NODE_ENV:-production}"
        -e "CLAUDEBOX_PROJECT_NAME=$project_name"
        -e "CLAUDEBOX_SLOT_NAME=$slot_name"
        -e "TERM=${TERM:-xterm-256color}"
        -e "VERBOSE=${VERBOSE:-false}"
        -e "CLAUDEBOX_WRAP_TMUX=${CLAUDEBOX_WRAP_TMUX:-false}"
        -e "CLAUDEBOX_PANE_NAME=${CLAUDEBOX_PANE_NAME:-}"
        -e "CLAUDEBOX_TMUX_PANE=${CLAUDEBOX_TMUX_PANE:-}"
        --cap-add NET_ADMIN
        --cap-add NET_RAW
    )

    # Security fix: Add resource limits to prevent DoS
    # These can be overridden via environment variables
    local memory_limit="${CLAUDEBOX_MEMORY_LIMIT:-8g}"
    local cpu_limit="${CLAUDEBOX_CPU_LIMIT:-4}"
    local pids_limit="${CLAUDEBOX_PIDS_LIMIT:-512}"

    docker_args+=(
        --memory "$memory_limit"
        --cpus "$cpu_limit"
        --pids-limit "$pids_limit"
        --ulimit nofile=65536:65536
        "$IMAGE_NAME"
    )
    
    # Add any additional arguments
    # Bash 3.2 safe array expansion
    if [[ ${#container_args[@]} -gt 0 ]]; then
        docker_args+=(${container_args[@]+"${container_args[@]}"})
    fi
    
    # Run the container
    if [[ "$VERBOSE" == "true" ]]; then
        # Security fix: Sanitize sensitive information from debug output
        local sanitized_args=()
        local skip_next=false
        # Bash 3.2 safe array expansion
        for arg in ${docker_args[@]+"${docker_args[@]}"}; do
            if [[ "$skip_next" == "true" ]]; then
                sanitized_args+=("[REDACTED]")
                skip_next=false
            elif [[ "$arg" =~ ^-v.*apikey|^-v.*\.anthropic ]]; then
                sanitized_args+=("-v [API_KEY_FILE]:...")
            elif [[ "$arg" =~ ANTHROPIC_API_KEY|API_KEY|SECRET|PASSWORD|TOKEN ]]; then
                sanitized_args+=("[REDACTED]")
            else
                sanitized_args+=("$arg")
            fi
        done
        # Bash 3.2 safe array expansion
        echo "[DEBUG] Docker run command: docker run ${sanitized_args[*]+${sanitized_args[*]}}" >&2
    fi
    # Bash 3.2 safe array expansion
    docker run ${docker_args[@]+"${docker_args[@]}"}
    local exit_code=$?
    
    return $exit_code
}

check_container_exists() {
    local container_name="$1"
    
    # Check if container exists (running or stopped)
    if docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}"  | grep -q "^${container_name}$"; then
        # Check if it's running
        if docker ps --filter "name=^${container_name}$" --format "{{.Names}}"  | grep -q "^${container_name}$"; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "none"
    fi
}

run_docker_build() {
    info "Running docker build..."
    export DOCKER_BUILDKIT=1
    
    # Check if we need to force rebuild due to template changes
    local no_cache_flag=""
    if [[ "${CLAUDEBOX_FORCE_NO_CACHE:-false}" == "true" ]]; then
        no_cache_flag="--no-cache"
        info "Forcing full rebuild (templates changed)"
    fi
    
    docker build \
        $no_cache_flag \
        --progress=${BUILDKIT_PROGRESS:-auto} \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --build-arg USER_ID="$USER_ID" \
        --build-arg GROUP_ID="$GROUP_ID" \
        --build-arg USERNAME="$DOCKER_USER" \
        --build-arg DELTA_VERSION="$DELTA_VERSION" \
        --build-arg REBUILD_TIMESTAMP="${CLAUDEBOX_REBUILD_TIMESTAMP:-}" \
        -f "$1" -t "$IMAGE_NAME" "$2" || error "Docker build failed"
}

export -f check_docker install_docker configure_docker_nonroot docker_exec_root docker_exec_user run_claudebox_container check_container_exists run_docker_build