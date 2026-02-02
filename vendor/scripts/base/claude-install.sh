#!/bin/bash
# Claude Code Installation Script (Vendored with pinned version)
#
# SECURITY: This script is vendored locally with a fixed version and hardcoded checksums.
# To update Claude Code version, update PINNED_VERSION and CHECKSUMS below.
# Checksums can be obtained from: $GCS_BUCKET/$VERSION/manifest.json
#
# Last updated: 2026-01-28
# Version: 2.1.22

set -e

# ============================================================================
# PINNED VERSION AND CHECKSUMS - Update these when upgrading Claude Code
# ============================================================================
PINNED_VERSION="2.1.22"

# SHA256 checksums for each platform (from manifest.json)
declare -A CHECKSUMS=(
    ["darwin-arm64"]="dd07b877ea3213ae7fd1df5536de3b441fbf7b11f93a0c20078540a6bd69033e"
    ["darwin-x64"]="3b16c67ef7d9edc6139cff1c73fc55b630dbeaa72fb7853fc0748309fc6529a0"
    ["linux-arm64"]="3750cebff6c8d7664fdffef578b14b962af8e29daa7ce53c0a6bd0a317ce973e"
    ["linux-x64"]="f7ba63e4d72ea8394998dec8b25cf94ba17faec434db17885218c0884103b5e9"
    ["linux-arm64-musl"]="237b62972ebcee890d816224ef9db079da06a824ae39a2755e398cf8f4f1cc73"
    ["linux-x64-musl"]="affcacf6d15f9d0f1831aad6373103c8d89497563704dc0fa07186402e8ea8d1"
    ["win32-x64"]="fb522d2000e434328189a5ce5ade17faf132ea05ddc29d60e4ac0afefddb69fd"
)
# ============================================================================

# Parse command line arguments
TARGET="$1"  # Optional target parameter

# Validate target if provided
if [[ -n "$TARGET" ]] && [[ ! "$TARGET" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?)$ ]]; then
    echo "Usage: $0 [stable|latest|VERSION]" >&2
    exit 1
fi

GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
DOWNLOAD_DIR="$HOME/.claude/downloads"

# Check for required dependencies
DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
else
    echo "Either curl or wget is required but neither is installed" >&2
    exit 1
fi

# Check if jq is available (optional)
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=true
fi

# Download function that works with both curl and wget
download_file() {
    local url="$1"
    local output="$2"
    
    if [ "$DOWNLOADER" = "curl" ]; then
        if [ -n "$output" ]; then
            curl -fsSL -o "$output" "$url"
        else
            curl -fsSL "$url"
        fi
    elif [ "$DOWNLOADER" = "wget" ]; then
        if [ -n "$output" ]; then
            wget -q -O "$output" "$url"
        else
            wget -q -O - "$url"
        fi
    else
        return 1
    fi
}

# Simple JSON parser for extracting checksum when jq is not available
get_checksum_from_manifest() {
    local json="$1"
    local platform="$2"
    
    # Normalize JSON to single line and extract checksum
    json=$(echo "$json" | tr -d '\n\r\t' | sed 's/ \+/ /g')
    
    # Extract checksum for platform using bash regex
    if [[ $json =~ \"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# Detect platform
case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) echo "Windows is not supported" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# Check for musl on Linux and adjust platform accordingly
if [ "$os" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
        platform="linux-${arch}-musl"
    else
        platform="linux-${arch}"
    fi
else
    platform="${os}-${arch}"
fi
mkdir -p "$DOWNLOAD_DIR"

# Use pinned version (no network request for version)
version="$PINNED_VERSION"
echo "Installing Claude Code v${version} (pinned version)"

# Get checksum from hardcoded values (no network request)
checksum="${CHECKSUMS[$platform]}"

# Validate checksum exists for this platform
if [ -z "$checksum" ]; then
    echo "Platform $platform not supported in pinned checksums" >&2
    echo "Supported platforms: ${!CHECKSUMS[*]}" >&2
    exit 1
fi

# Validate checksum format (SHA256 = 64 hex characters)
if [[ ! "$checksum" =~ ^[a-f0-9]{64}$ ]]; then
    echo "Invalid checksum format for platform $platform" >&2
    exit 1
fi

echo "Using hardcoded SHA256: ${checksum:0:16}..."

# Download and verify
binary_path="$DOWNLOAD_DIR/claude-$version-$platform"
if ! download_file "$GCS_BUCKET/$version/$platform/claude" "$binary_path"; then
    echo "Download failed" >&2
    rm -f "$binary_path"
    exit 1
fi

# Pick the right checksum tool
if [ "$os" = "darwin" ]; then
    actual=$(shasum -a 256 "$binary_path" | cut -d' ' -f1)
else
    actual=$(sha256sum "$binary_path" | cut -d' ' -f1)
fi

if [ "$actual" != "$checksum" ]; then
    echo "Checksum verification failed" >&2
    rm -f "$binary_path"
    exit 1
fi

chmod +x "$binary_path"

# Run claude install to set up launcher and shell integration
echo "Setting up Claude Code..."
"$binary_path" install ${TARGET:+"$TARGET"}

# Clean up downloaded file
rm -f "$binary_path"

echo ""
echo "✅ Installation complete!"
echo ""
