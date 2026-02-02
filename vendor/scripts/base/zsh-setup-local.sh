#!/bin/sh
#######################################################################################################
# Local Zsh Setup Script (No Network Required)
# Based on deluan/zsh-in-docker but uses pre-downloaded archives
#
# This script installs Oh-My-Zsh and powerlevel10k from local tarballs
# to avoid supply chain attacks from runtime network requests.
#######################################################################################################

set -e

# Configuration
OHMYZSH_ARCHIVE="${OHMYZSH_ARCHIVE:-/tmp/zsh-assets/ohmyzsh.tar.gz}"
POWERLEVEL10K_ARCHIVE="${POWERLEVEL10K_ARCHIVE:-/tmp/zsh-assets/powerlevel10k.tar.gz}"

THEME=powerlevel10k/powerlevel10k
PLUGINS=""
ZSHRC_APPEND=""

while getopts ":t:p:a:" opt; do
    case ${opt} in
        t)  THEME=$OPTARG
            ;;
        p)  PLUGINS="${PLUGINS}$OPTARG "
            ;;
        a)  ZSHRC_APPEND="$ZSHRC_APPEND\n$OPTARG"
            ;;
        \?)
            echo "Invalid option: $OPTARG" 1>&2
            ;;
        :)
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            ;;
    esac
done
shift $((OPTIND -1))

echo
echo "Installing Oh-My-Zsh (local mode) with:"
echo "  THEME   = $THEME"
echo "  PLUGINS = $PLUGINS"
echo

# Verify archives exist
if [ ! -f "$OHMYZSH_ARCHIVE" ]; then
    echo "ERROR: Oh-My-Zsh archive not found at $OHMYZSH_ARCHIVE" >&2
    exit 1
fi

if [ ! -f "$POWERLEVEL10K_ARCHIVE" ]; then
    echo "ERROR: powerlevel10k archive not found at $POWERLEVEL10K_ARCHIVE" >&2
    exit 1
fi

# Install Oh-My-Zsh from local archive
echo "Installing Oh-My-Zsh from local archive..."
mkdir -p "$HOME/.oh-my-zsh"
tar -xzf "$OHMYZSH_ARCHIVE" -C "$HOME/.oh-my-zsh" --strip-components=1

# Install powerlevel10k theme from local archive
echo "Installing powerlevel10k theme from local archive..."
mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
tar -xzf "$POWERLEVEL10K_ARCHIVE" -C "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" --strip-components=1

# Generate .zshrc
echo "Generating .zshrc..."
cat > "$HOME/.zshrc" <<EOM
export LANG='en_US.UTF-8'
export LANGUAGE='en_US:en'
export LC_ALL='en_US.UTF-8'
export TERM=xterm

##### Zsh/Oh-my-Zsh Configuration
export ZSH="\$HOME/.oh-my-zsh"

ZSH_THEME="${THEME}"
plugins=(${PLUGINS})

EOM

# Append custom configuration
printf "$ZSHRC_APPEND" >> "$HOME/.zshrc"

# Add oh-my-zsh source
cat >> "$HOME/.zshrc" <<'EOM'

source $ZSH/oh-my-zsh.sh
EOM

# Add powerlevel10k configuration
cat >> "$HOME/.zshrc" <<'EOM'

# Powerlevel10k Configuration
POWERLEVEL9K_SHORTEN_STRATEGY="truncate_to_last"
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(user dir vcs status)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=()
POWERLEVEL9K_STATUS_OK=false
POWERLEVEL9K_STATUS_CROSS=true
EOM

echo "Oh-My-Zsh installation complete (local mode, no network requests made)"
