#!/usr/bin/env bash
# Vendor script management tool for supply chain security
# Usage: ./scripts/vendor-update.sh [verify|update|audit] [script-name]

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$ROOT_DIR/vendor/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# Script sources for updates
declare -A SCRIPT_SOURCES=(
    ["base/zsh-in-docker.sh"]="https://raw.githubusercontent.com/deluan/zsh-in-docker/master/zsh-in-docker.sh"
    ["base/uv-install.sh"]="https://astral.sh/uv/install.sh"
    ["base/nvm-install.sh"]="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh"
    ["profiles/rustup.sh"]="https://sh.rustup.rs"
    ["profiles/fvm-install.sh"]="https://fvm.app/install.sh"
    ["profiles/nvm-install.sh"]="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh"
    ["profiles/sdkman-install.sh"]="https://get.sdkman.io"
)

verify_checksums() {
    local exit_code=0

    log_info "Verifying base script checksums..."
    if cd "$VENDOR_DIR" && sha256sum -c checksums-base.sha256; then
        log_info "Base scripts: OK"
    else
        log_error "Base scripts: FAILED"
        exit_code=1
    fi

    log_info "Verifying profile script checksums..."
    if cd "$VENDOR_DIR" && sha256sum -c checksums-profiles.sha256; then
        log_info "Profile scripts: OK"
    else
        log_error "Profile scripts: FAILED"
        exit_code=1
    fi

    return $exit_code
}

regenerate_checksums() {
    log_info "Regenerating checksums..."

    cd "$VENDOR_DIR"

    # Base checksums
    sha256sum base/*.sh > checksums-base.sha256
    log_info "Generated checksums-base.sha256"

    # Profile checksums
    sha256sum profiles/*.sh > checksums-profiles.sha256
    log_info "Generated checksums-profiles.sha256"
}

download_script() {
    local script_path="$1"
    local url="${SCRIPT_SOURCES[$script_path]:-}"

    if [[ -z "$url" ]]; then
        log_error "Unknown script: $script_path"
        return 1
    fi

    local target="$VENDOR_DIR/$script_path"
    local temp_file="/tmp/vendor-download-$$"

    log_info "Downloading $script_path from $url..."

    if curl -fsSL --retry 3 -o "$temp_file" "$url"; then
        log_info "Downloaded successfully"

        # Show diff if existing file
        if [[ -f "$target" ]]; then
            log_info "Showing changes..."
            diff -u "$target" "$temp_file" || true
        fi

        # Prompt for review
        printf "\n${YELLOW}Review the downloaded script before accepting.${NC}\n"
        printf "Script saved to: $temp_file\n"
        printf "Target location: $target\n"
        printf "\nAccept this update? [y/N] "
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            mv "$temp_file" "$target"
            chmod +x "$target"
            log_info "Updated $script_path"
            return 0
        else
            rm -f "$temp_file"
            log_info "Update cancelled"
            return 1
        fi
    else
        log_error "Failed to download $script_path"
        rm -f "$temp_file"
        return 1
    fi
}

update_script() {
    local script_name="$1"

    if [[ -z "$script_name" ]]; then
        log_error "Usage: $0 update <script-path>"
        log_info "Available scripts:"
        for key in "${!SCRIPT_SOURCES[@]}"; do
            printf "  - %s\n" "$key"
        done
        return 1
    fi

    if download_script "$script_name"; then
        regenerate_checksums
        log_info "Don't forget to audit the changes before committing!"
    fi
}

audit_script() {
    local script_path="$1"

    if [[ -z "$script_path" ]]; then
        log_error "Usage: $0 audit <script-path>"
        return 1
    fi

    local target="$VENDOR_DIR/$script_path"

    if [[ ! -f "$target" ]]; then
        log_error "Script not found: $target"
        return 1
    fi

    log_info "Security audit for: $script_path"
    printf "\n"

    # Check for suspicious patterns
    log_info "Checking for suspicious patterns..."

    local suspicious_patterns=(
        "curl.*|.*sh"
        "wget.*|.*sh"
        "eval.*\\\$"
        "base64.*-d"
        "/dev/tcp"
        "nc -e"
        "bash -i"
        "python.*-c.*import"
        "perl.*-e"
        "ruby.*-e"
    )

    local found_issues=0
    for pattern in "${suspicious_patterns[@]}"; do
        if grep -En "$pattern" "$target" 2>/dev/null; then
            log_warn "Found pattern: $pattern"
            found_issues=$((found_issues + 1))
        fi
    done

    if [[ $found_issues -eq 0 ]]; then
        log_info "No suspicious patterns found"
    else
        log_warn "Found $found_issues suspicious patterns - review required"
    fi

    printf "\n"
    log_info "Checking for external URLs..."
    grep -Eon 'https?://[^"'"'"' ]+' "$target" 2>/dev/null | head -20 || log_info "No URLs found"

    printf "\n"
    log_info "Script statistics:"
    printf "  Lines: %s\n" "$(wc -l < "$target")"
    printf "  Size: %s bytes\n" "$(wc -c < "$target")"
    printf "  SHA256: %s\n" "$(sha256sum "$target" | cut -d' ' -f1)"
}

list_scripts() {
    log_info "Vendored scripts:"
    printf "\nBase scripts (used in Dockerfile):\n"
    for f in "$VENDOR_DIR"/base/*.sh; do
        if [[ -f "$f" ]]; then
            local name=$(basename "$f")
            local sum=$(sha256sum "$f" | cut -d' ' -f1 | head -c 16)
            printf "  - base/%s  [%s...]\n" "$name" "$sum"
        fi
    done

    printf "\nProfile scripts (used in profiles):\n"
    for f in "$VENDOR_DIR"/profiles/*.sh; do
        if [[ -f "$f" ]]; then
            local name=$(basename "$f")
            local sum=$(sha256sum "$f" | cut -d' ' -f1 | head -c 16)
            printf "  - profiles/%s  [%s...]\n" "$name" "$sum"
        fi
    done
}

show_help() {
    cat << 'EOF'
Vendor Script Management Tool

Usage: vendor-update.sh <command> [arguments]

Commands:
  verify              Verify all script checksums
  list                List all vendored scripts
  update <script>     Download and update a specific script
  audit <script>      Run security audit on a script
  regenerate          Regenerate all checksum files
  help                Show this help message

Examples:
  ./scripts/vendor-update.sh verify
  ./scripts/vendor-update.sh update profiles/rustup.sh
  ./scripts/vendor-update.sh audit base/nvm-install.sh

Security Note:
  Always audit scripts after updating before committing changes.
  Check MANIFEST.md for the audit checklist.
EOF
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        verify)
            verify_checksums
            ;;
        list)
            list_scripts
            ;;
        update)
            update_script "${1:-}"
            ;;
        audit)
            audit_script "${1:-}"
            ;;
        regenerate)
            regenerate_checksums
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
