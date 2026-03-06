#!/usr/bin/env bash
# Container runtime detection and abstraction layer.
# Supports Docker and Podman (rootful and rootless).

# Runtime globals (set by detect_container_runtime)
CONTAINER_RUNTIME=""
CONTAINER_RUNTIME_MODE=""
RUNTIME_HAS_BUILDKIT="false"
RUNTIME_HAS_FIREWALL="false"
RUNTIME_HAS_SUDO="false"
RUNTIME_HAS_USER_REMAP="false"

# Detect and configure the container runtime.
# Sets CONTAINER_RUNTIME, CONTAINER_RUNTIME_MODE, and capability flags.
# Supports CLAUDEBOX_RUNTIME env var to force a specific runtime.
detect_container_runtime() {
    local forced_runtime="${CLAUDEBOX_RUNTIME:-}"

    if [[ -n "$forced_runtime" ]]; then
        case "$forced_runtime" in
            docker|podman)
                if ! command -v "$forced_runtime" >/dev/null 2>&1; then
                    error "CLAUDEBOX_RUNTIME=$forced_runtime but $forced_runtime is not installed"
                fi
                CONTAINER_RUNTIME="$forced_runtime"
                ;;
            *)
                error "CLAUDEBOX_RUNTIME must be 'docker' or 'podman' (got '$forced_runtime')"
                ;;
        esac
    else
        # Auto-detect: prefer Docker when both are installed
        if command -v docker >/dev/null 2>&1; then
            CONTAINER_RUNTIME="docker"
        elif command -v podman >/dev/null 2>&1; then
            CONTAINER_RUNTIME="podman"
        else
            CONTAINER_RUNTIME=""
            CONTAINER_RUNTIME_MODE=""
            return 0
        fi
    fi

    # Determine runtime mode and capabilities
    if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
        CONTAINER_RUNTIME_MODE="docker"
        RUNTIME_HAS_BUILDKIT="true"
        RUNTIME_HAS_FIREWALL="true"
        RUNTIME_HAS_SUDO="true"
        RUNTIME_HAS_USER_REMAP="true"
    elif [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        # Detect rootful vs rootless
        if [[ "$(id -u)" -eq 0 ]]; then
            CONTAINER_RUNTIME_MODE="podman-rootful"
            RUNTIME_HAS_BUILDKIT="false"
            RUNTIME_HAS_FIREWALL="true"
            RUNTIME_HAS_SUDO="true"
            RUNTIME_HAS_USER_REMAP="true"
        else
            CONTAINER_RUNTIME_MODE="podman-rootless"
            RUNTIME_HAS_BUILDKIT="false"
            RUNTIME_HAS_FIREWALL="false"
            RUNTIME_HAS_SUDO="false"
            RUNTIME_HAS_USER_REMAP="false"
        fi
    fi

    export CONTAINER_RUNTIME
    export CONTAINER_RUNTIME_MODE
    export RUNTIME_HAS_BUILDKIT
    export RUNTIME_HAS_FIREWALL
    export RUNTIME_HAS_SUDO
    export RUNTIME_HAS_USER_REMAP

    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[DEBUG] Container runtime: $CONTAINER_RUNTIME" >&2
        echo "[DEBUG] Runtime mode: $CONTAINER_RUNTIME_MODE" >&2
        echo "[DEBUG] Has BuildKit: $RUNTIME_HAS_BUILDKIT" >&2
        echo "[DEBUG] Has firewall: $RUNTIME_HAS_FIREWALL" >&2
        echo "[DEBUG] Has sudo: $RUNTIME_HAS_SUDO" >&2
        echo "[DEBUG] Has user remap: $RUNTIME_HAS_USER_REMAP" >&2
    fi
}

# Returns the container runtime command name.
runtime_cmd() {
    printf '%s' "$CONTAINER_RUNTIME"
}

# Print runtime information for verbose/info output.
runtime_info() {
    printf "Container Runtime:  %s\n" "$CONTAINER_RUNTIME"
    printf "Runtime Mode:       %s\n" "$CONTAINER_RUNTIME_MODE"
    printf "BuildKit Support:   %s\n" "$RUNTIME_HAS_BUILDKIT"
    printf "Firewall Support:   %s\n" "$RUNTIME_HAS_FIREWALL"
    printf "Sudo Support:       %s\n" "$RUNTIME_HAS_SUDO"
    printf "User Remap:         %s\n" "$RUNTIME_HAS_USER_REMAP"
}

# Check if the container runtime is available and running.
# Returns:
#   0 - runtime is available and functional
#   1 - runtime is not installed
#   2 - runtime is installed but not running
#   3 - runtime requires non-root configuration (Docker-specific)
check_runtime() {
    if [[ -z "$CONTAINER_RUNTIME" ]]; then
        return 1
    fi

    if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
        command -v docker >/dev/null || return 1
        docker info >/dev/null 2>&1 || return 2
        docker ps >/dev/null 2>&1 || return 3
    elif [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
        command -v podman >/dev/null || return 1
        podman info >/dev/null 2>&1 || return 2
    fi
    return 0
}

# Install container runtime (offers both Docker and Podman on Linux).
install_container_runtime() {
    warn "No container runtime (Docker or Podman) is installed."
    cecho "Which runtime would you like to install?" "$CYAN"
    printf "  1) Docker (recommended)\n"
    printf "  2) Podman\n"
    printf "  q) Quit\n"
    read -r response
    case "$response" in
        1) install_docker ;;
        2) _install_podman ;;
        *) error "A container runtime is required. Visit: https://docs.docker.com/engine/install/ or https://podman.io/getting-started/installation" ;;
    esac
}

# Install Podman on Linux.
_install_podman() {
    info "Installing Podman..."

    [[ -f /etc/os-release ]] && . /etc/os-release || error "Cannot detect OS"

    case "${ID:-}" in
        ubuntu|debian)
            warn "Installing Podman requires sudo privileges..."
            sudo apt-get update
            sudo apt-get install -y podman
            ;;
        fedora|rhel|centos)
            warn "Installing Podman requires sudo privileges..."
            sudo dnf install -y podman
            ;;
        arch|manjaro)
            warn "Installing Podman requires sudo privileges..."
            sudo pacman -S --noconfirm podman
            ;;
        *)
            error "Unsupported OS: ${ID:-unknown}. Visit: https://podman.io/getting-started/installation"
            ;;
    esac

    success "Podman installed successfully!"

    # Re-detect runtime
    CONTAINER_RUNTIME="podman"
    detect_container_runtime
}

export -f detect_container_runtime runtime_cmd runtime_info check_runtime install_container_runtime _install_podman
