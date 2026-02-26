#!/usr/bin/env bash
# Claude Code status line script
# Receives JSON session data on stdin

input=$(cat)

# Extract fields
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
used_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(printf '%s' "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
output_tokens=$(printf '%s' "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
cache_read=$(printf '%s' "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
duration_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // empty')
api_ms=$(printf '%s' "$input" | jq -r '.cost.total_api_duration_ms // empty')
lines_added=$(printf '%s' "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(printf '%s' "$input" | jq -r '.cost.total_lines_removed // empty')
session_name=$(printf '%s' "$input" | jq -r '.session_name // empty')

# Directory: use ClaudeBox project name if available, otherwise basename of cwd
if [ -n "${CLAUDEBOX_PROJECT_NAME:-}" ]; then
    dir="$CLAUDEBOX_PROJECT_NAME"
elif [ -n "$cwd" ]; then
    dir=$(basename "$cwd")
else
    dir=$(basename "$(pwd)")
fi

# Build segments
# Colors (will appear dimmed in Claude's status bar)
RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[32m'
BLUE='\033[34m'
CYAN='\033[36m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
DIM='\033[2m'

# project/directory
seg_dir=$(printf "${GREEN}${dir}${RESET}")

# model (short form)
if [ -n "$model" ]; then
    seg_model=$(printf "${CYAN}${model}${RESET}")
fi

# format token count (1234 -> 1.2k, 144100 -> 144.1k)
fmt_tokens() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "null" ]; then
        printf '0'
        return
    fi
    if [ "$n" -ge 1000 ]; then
        local whole=$((n / 1000))
        local frac=$(( (n % 1000) / 100 ))
        printf '%d.%dk' "$whole" "$frac"
    else
        printf '%d' "$n"
    fi
}

# context usage with in/out/cache
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
    used_int=${used_pct%.*}
    in_fmt=$(fmt_tokens "${input_tokens:-0}")
    out_fmt=$(fmt_tokens "${output_tokens:-0}")
    cache_fmt=$(fmt_tokens "${cache_read:-0}")
    RED='\033[31m'
    ORANGE='\033[38;5;208m'
    if [ "${used_int:-0}" -ge 95 ]; then
        ctx_color="$RED"
    elif [ "${used_int:-0}" -ge 80 ]; then
        ctx_color="$ORANGE"
    elif [ "${used_int:-0}" -ge 50 ]; then
        ctx_color="$YELLOW"
    else
        ctx_color="$DIM"
    fi
    seg_ctx=$(printf "[${ctx_color}ctx:${used_pct%%.*}%%${RESET} in:${in_fmt} out:${out_fmt} cache:${cache_fmt}]")
fi

# duration (convert ms to minutes:seconds)
fmt_duration() {
    local ms="$1"
    if [ -n "$ms" ] && [ "$ms" != "null" ] && [ "$ms" != "0" ]; then
        local secs=$(( ${ms%.*} / 1000 ))
        printf '%d:%02d' $((secs / 60)) $((secs % 60))
    fi
}

dur=$(fmt_duration "$duration_ms")
api=$(fmt_duration "$api_ms")
if [ -n "$dur" ]; then
    seg_time=$(printf "${DIM}${dur}(api:${api})${RESET}")
fi

# lines changed
if [ -n "$lines_added" ] && [ "$lines_added" != "null" ] && [ "$lines_added" != "0" -o "$lines_removed" != "0" ]; then
    seg_lines=$(printf "${GREEN}+${lines_added:-0}${RESET}/${YELLOW}-${lines_removed:-0}${RESET}")
fi

# git status
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        git_info="${BLUE}${branch}${RESET}"
        if [ "$staged" -gt 0 ]; then
            git_info="${git_info} ${GREEN}+${staged}${RESET}"
        fi
        if [ "$modified" -gt 0 ]; then
            git_info="${git_info} ${YELLOW}~${modified}${RESET}"
        fi
        if [ "$untracked" -gt 0 ]; then
            git_info="${git_info} ${DIM}?${untracked}${RESET}"
        fi
        seg_git="$git_info"
    fi
fi

# session name (if set)
if [ -n "$session_name" ] && [ "$session_name" != "null" ]; then
    seg_session=$(printf "${MAGENTA}[${session_name}]${RESET}")
fi

# Assemble line 1: project | model | ctx
line1="${seg_dir}"
if [ -n "$seg_model" ]; then
    line1="${line1} | ${seg_model}"
fi
if [ -n "$seg_ctx" ]; then
    line1="${line1} | ${seg_ctx}"
fi
if [ -n "$seg_session" ]; then
    line1="${line1} ${seg_session}"
fi
printf '%b\n' "$line1"

# Assemble line 2: time | lines | git
line2=""
if [ -n "${seg_time:-}" ]; then
    line2="${seg_time}"
fi
if [ -n "${seg_lines:-}" ]; then
    if [ -n "$line2" ]; then
        line2="${line2} | ${seg_lines}"
    else
        line2="${seg_lines}"
    fi
fi
if [ -n "${seg_git:-}" ]; then
    if [ -n "$line2" ]; then
        line2="${line2} | ${seg_git}"
    else
        line2="${seg_git}"
    fi
fi
if [ -n "$line2" ]; then
    printf '%b\n' "$line2"
fi
