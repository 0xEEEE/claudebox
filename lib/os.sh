#!/usr/bin/env bash
# Detect host OS and sane defaults needed by other modules.

# Cross-platform host detection (Linux vs. macOS)
OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
  Darwin*) HOST_OS="macOS" ;;
  Linux*)  HOST_OS="linux" ;;
  *) echo "Unsupported operating system: $OS_TYPE" >&2; exit 1 ;;
esac

export HOST_OS

# Detect case‑insensitive default macOS filesystems (HFS+/APFS)
# Exit code 0  → case‑sensitive, 1 → case‑insensitive
is_case_sensitive_fs() {
  local t1 t2
  t1="$(mktemp "/tmp/.fs_case_test.XXXXXXXX")"
  # More portable uppercase conversion
  t2="$(echo "$t1" | tr '[:lower:]' '[:upper:]')"
  touch "$t1"
  [[ -e "$t2" && "$t1" != "$t2" ]] && { rm -f "$t1"; return 1; }
  rm -f "$t1"
  return 0
}

# Normalise docker‑build contexts on case‑insensitive hosts to avoid collisions
if [[ "$HOST_OS" == "macOS" ]] && ! is_case_sensitive_fs; then
  export COMPOSE_DOCKER_CLI_BUILD=1   # new BuildKit path‑normaliser
  export DOCKER_BUILDKIT=1
fi

# ============================================================================
# MD5 Command Detection and Helpers
# ============================================================================

# Detect and set the appropriate MD5 command based on OS
# Security fix: Removed eval usage and use direct command selection
set_md5_command() {
    if command -v md5sum >/dev/null 2>&1; then
        # Linux style: md5sum outputs "hash  filename"
        MD5_STYLE="linux"
    elif command -v md5 >/dev/null 2>&1; then
        # macOS style: md5 -q outputs just the hash
        MD5_STYLE="macos"
    else
        error "No MD5 command found. Please install md5sum or md5."
    fi
    export MD5_STYLE
}

# Calculate MD5 hash of a file (cross-platform)
# Security fix: Use case statement instead of eval
md5_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        case "$MD5_STYLE" in
            linux)
                md5sum "$file" 2>/dev/null | cut -d' ' -f1
                ;;
            macos)
                md5 -q "$file" 2>/dev/null
                ;;
        esac
    else
        echo ""
    fi
}

# Calculate MD5 hash of a string (cross-platform)
# Security fix: Use case statement instead of eval
md5_string() {
    local string="$1"
    case "$MD5_STYLE" in
        linux)
            echo -n "$string" | md5sum 2>/dev/null | cut -d' ' -f1
            ;;
        macos)
            echo -n "$string" | md5 -q 2>/dev/null
            ;;
    esac
}

# Initialize MD5 command on library load
set_md5_command

# Export functions
export -f set_md5_command md5_file md5_string