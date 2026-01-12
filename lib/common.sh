#!/usr/bin/env bash
# =============================================================================
# devbox/lib/common.sh — Shared utilities for all devbox scripts
# =============================================================================
# Source this file at the top of your scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# COLORS (TTY-aware)
# -----------------------------------------------------------------------------

if [[ -t 1 ]] && [[ -t 2 ]]; then
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'
    C_CYAN=$'\033[1;36m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_DIM='' C_RESET=''
fi

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------

log_info()  { echo "${C_CYAN}→ $*${C_RESET}"; }
log_ok()    { echo "${C_GREEN}✓ $*${C_RESET}"; }
log_warn()  { echo "${C_YELLOW}⚠ $*${C_RESET}" >&2; }
log_error() { echo "${C_RED}✗ $*${C_RESET}" >&2; }
log_dim()   { echo "${C_DIM}  $*${C_RESET}"; }

die() {
    log_error "$@"
    exit 1
}

# -----------------------------------------------------------------------------
# PROMPTS
# -----------------------------------------------------------------------------

# Ask yes/no question, default to yes
ask_yes() {
    local prompt="$1"
    local reply
    
    if [[ "${AUTO_YES:-0}" == "1" ]]; then
        return 0
    fi
    
    echo -n "${C_CYAN}? ${prompt}${C_RESET} [Y/n] "
    read -r reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# Ask yes/no question, default to no
ask_no() {
    local prompt="$1"
    local reply
    
    echo -n "${C_YELLOW}? ${prompt}${C_RESET} [y/N] "
    read -r reply
    [[ "$reply" =~ ^[Yy] ]]
}

# Ask for a value with optional default
ask_value() {
    local prompt="$1"
    local default="${2:-}"
    local reply
    
    if [[ -n "$default" ]]; then
        echo -n "${C_CYAN}? ${prompt}${C_RESET} [$default]: "
    else
        echo -n "${C_CYAN}? ${prompt}${C_RESET}: "
    fi
    read -r reply
    
    echo "${reply:-$default}"
}

# Select from list
ask_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local i
    
    echo "${C_CYAN}? ${prompt}${C_RESET}"
    for i in "${!options[@]}"; do
        echo "  $((i+1))) ${options[$i]}"
    done
    
    local reply
    echo -n "  Enter number [1]: "
    read -r reply
    reply="${reply:-1}"
    
    if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#options[@]} )); then
        echo "${options[$((reply-1))]}"
    else
        echo "${options[0]}"
    fi
}

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------

# Check if command exists
require_cmd() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command -v "$cmd" &>/dev/null; then
        if [[ -n "$install_hint" ]]; then
            die "Required command '$cmd' not found. Install with: $install_hint"
        else
            die "Required command '$cmd' not found"
        fi
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Get size of directory in bytes
get_size() {
    du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0
}

# Format bytes to human readable
format_size() {
    local bytes="$1"
    if (( bytes >= 1073741824 )); then
        echo "$((bytes / 1073741824))G"
    elif (( bytes >= 1048576 )); then
        echo "$((bytes / 1048576))M"
    elif (( bytes >= 1024 )); then
        echo "$((bytes / 1024))K"
    else
        echo "${bytes}B"
    fi
}

# Get devbox root directory
get_devbox_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    
    # Walk up to find devbox root (contains lib/ directory)
    while [[ "$script_dir" != "/" ]]; do
        if [[ -d "$script_dir/lib" ]] && [[ -f "$script_dir/lib/common.sh" ]]; then
            echo "$script_dir"
            return 0
        fi
        script_dir="$(dirname "$script_dir")"
    done
    
    die "Could not find devbox root directory"
}
