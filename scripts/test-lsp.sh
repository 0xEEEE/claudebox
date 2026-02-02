#!/usr/bin/env bash
# Test LSP server availability in claudebox container
# Usage: Run this inside the container to verify LSP setup

set -euo pipefail

echo "=== ClaudeBox LSP Diagnostics ==="
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_binary() {
    local name="$1"
    local cmd="$2"

    printf "%-30s" "$name:"
    if command -v "$cmd" >/dev/null 2>&1; then
        local path=$(command -v "$cmd")
        local version=$("$cmd" --version 2>&1 | head -1 || echo "unknown")
        printf "${GREEN}OK${NC} - %s\n" "$path"
        printf "%-30s  %s\n" "" "$version"
    else
        printf "${RED}NOT FOUND${NC}\n"
    fi
}

echo "=== LSP Server Binaries ==="
echo

check_binary "Rust (rust-analyzer)" "rust-analyzer"
check_binary "Python (ty)" "ty"
check_binary "Go (gopls)" "gopls"
check_binary "TypeScript (tsserver)" "typescript-language-server"
check_binary "C/C++ (clangd)" "clangd"
check_binary "Bash (bash-language-server)" "bash-language-server"

echo
echo "=== PATH ==="
echo "$PATH" | tr ':' '\n' | head -20

echo
echo "=== Claude Code Plugins Directory ==="
if [ -d "$HOME/.claude/plugins" ]; then
    echo "Directory exists: $HOME/.claude/plugins"
    ls -la "$HOME/.claude/plugins/" 2>/dev/null || echo "  (empty or inaccessible)"
else
    echo "${YELLOW}Directory not found: $HOME/.claude/plugins${NC}"
fi

echo
echo "=== Bundled Plugins Mount ==="
if [ -d "/mnt/claudebox-plugins" ]; then
    echo "Mount exists: /mnt/claudebox-plugins"
    ls -la "/mnt/claudebox-plugins/" 2>/dev/null || echo "  (empty)"
else
    echo "${YELLOW}Mount not found: /mnt/claudebox-plugins${NC}"
fi

echo
echo "=== Host Plugins Mount ==="
if [ -d "/mnt/host-plugins" ]; then
    echo "Mount exists: /mnt/host-plugins"
    ls -la "/mnt/host-plugins/" 2>/dev/null || echo "  (empty)"
else
    echo "${YELLOW}Mount not found: /mnt/host-plugins${NC}"
fi

echo
echo "=== Claude Settings ==="
if [ -f "$HOME/.claude/settings.json" ]; then
    echo "Settings file exists"
    cat "$HOME/.claude/settings.json" 2>/dev/null | head -50
else
    echo "${YELLOW}No settings.json found${NC}"
fi

echo
echo "=== Test Complete ==="
