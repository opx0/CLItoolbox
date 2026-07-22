#!/usr/bin/env bash
# =============================================================================
# devbox/cli/clean/system.sh — Portable system cleaner
# =============================================================================
# Cleans package caches, orphan packages, journals, browser caches, dev caches
# Works on: Arch, Debian/Ubuntu, Fedora, and other major distros
# Usage: system.sh [--dry-run]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/distro.sh"

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

DRY_RUN=false
total_freed=0

# Get the main user (UID 1000 or current user)
get_main_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        echo "$SUDO_USER"
    elif id -nu 1000 &>/dev/null; then
        id -nu 1000
    else
        echo "$USER"
    fi
}

MAIN_USER="$(get_main_user)"
USER_HOME="/home/$MAIN_USER"

# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------

show_deleted() {
    local name="$1" size="$2" count="${3:-}"
    if [[ $size -gt 0 ]]; then
        local size_mb=$((size / 1024 / 1024))
        if [[ -n "$count" ]]; then
            log_ok "$name: $count, ${size_mb}M"
        else
            log_ok "$name: ${size_mb}M"
        fi
        total_freed=$((total_freed + size))
    fi
}

safe_rm() {
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would delete: $*"
    else
        rm -rf "$@" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# PACKAGE CACHE CLEANING
# -----------------------------------------------------------------------------

clean_aur_cache() {
    local distro
    distro=$(detect_distro)
    
    if [[ "$distro" != "arch" ]]; then
        return 0
    fi
    
    local aur_cache
    aur_cache=$(get_aur_cache_dir)
    
    if [[ -z "$aur_cache" ]] || [[ ! -d "$aur_cache" ]]; then
        return 0
    fi
    
    local before
    before=$(get_size "$aur_cache")
    
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would clean AUR cache: $aur_cache"
        return 0
    fi
    
    # Get list of installed AUR packages
    local -a installed
    mapfile -t installed < <(pacman -Qqm 2>/dev/null || true)
    local removed=0
    
    while IFS= read -r -d '' dir; do
        local pkg
        pkg="$(basename "$dir")"
        if ! printf '%s\n' "${installed[@]}" | grep -qFx "$pkg"; then
            rm -rf "$dir"
            ((removed++))
        else
            # Keep package but remove build artifacts
            rm -rf "$dir"/{src,pkg} 2>/dev/null || true
        fi
    done < <(find "$aur_cache" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    
    show_deleted "AUR cache" $((before - $(get_size "$aur_cache"))) "$removed pkgs"
}

clean_package_cache() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    local cache_dir
    cache_dir=$(get_pkg_cache_dir)
    
    if [[ -z "$cache_dir" ]] || [[ ! -d "$cache_dir" ]]; then
        return 0
    fi
    
    local before
    before=$(get_size "$cache_dir")
    
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would clean package cache: $cache_dir"
        return 0
    fi
    
    case "$pkg_manager" in
        pacman)
            if command -v paccache &>/dev/null; then
                local count ucount
                count=$(sudo paccache -rk1 2>&1 | grep -oP '\d+(?= packages removed)' || echo 0)
                ucount=$(sudo paccache -ruk0 2>&1 | grep -oP '\d+(?= packages removed)' || echo 0)
                show_deleted "Package cache" $((before - $(get_size "$cache_dir"))) "$((count + ucount)) pkgs"
            fi
            ;;
        apt)
            sudo apt clean 2>/dev/null || true
            sudo apt autoclean 2>/dev/null || true
            show_deleted "Package cache" $((before - $(get_size "$cache_dir")))
            ;;
        dnf)
            sudo dnf clean all 2>/dev/null || true
            show_deleted "Package cache" $((before - $(get_size "$cache_dir")))
            ;;
        yum)
            sudo yum clean all 2>/dev/null || true
            show_deleted "Package cache" $((before - $(get_size "$cache_dir")))
            ;;
        zypper)
            sudo zypper clean --all 2>/dev/null || true
            show_deleted "Package cache" $((before - $(get_size "$cache_dir")))
            ;;
    esac
}

clean_orphans() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would remove orphan packages"
        return 0
    fi
    
    case "$pkg_manager" in
        pacman)
            local orphans
            if orphans=$(pacman -Qdtq 2>/dev/null) && [[ -n "$orphans" ]]; then
                local count
                count=$(echo "$orphans" | wc -l)
                echo "$orphans" | sudo pacman -Rns --noconfirm - &>/dev/null || true
                log_ok "Orphans: $count pkgs removed"
            fi
            ;;
        apt)
            sudo apt autoremove -y &>/dev/null || true
            log_ok "Orphans: cleaned (apt autoremove)"
            ;;
        dnf)
            sudo dnf autoremove -y &>/dev/null || true
            log_ok "Orphans: cleaned (dnf autoremove)"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# SYSTEM CLEANING
# -----------------------------------------------------------------------------

clean_journal() {
    if ! command -v journalctl &>/dev/null; then
        return 0
    fi
    
    local before after
    before=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.?\d*[KMGT]?' | head -1 || echo "0")
    
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would vacuum journal logs older than 3 days"
        return 0
    fi
    
    sudo journalctl --vacuum-time=3d &>/dev/null || true
    after=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.?\d*[KMGT]?' | head -1 || echo "0")
    
    if [[ "$before" != "$after" ]]; then
        log_ok "Journal: $before → $after"
    fi
}

clean_browser_cache() {
    local cache_dir="$USER_HOME/.cache"
    
    if [[ ! -d "$cache_dir" ]]; then
        return 0
    fi
    
    local before
    before=$(get_size "$cache_dir")
    
    local browser_caches=(
        "chromium"
        "google-chrome"
        "google-chrome-beta"
        "mozilla"
        "firefox"
        "BraveSoftware"
        "vivaldi"
        "thumbnails"
    )
    
    for cache in "${browser_caches[@]}"; do
        if [[ -d "$cache_dir/$cache" ]]; then
            safe_rm "$cache_dir/$cache"
        fi
    done
    
    show_deleted "Browser cache" $((before - $(get_size "$cache_dir")))
}

clean_dev_caches() {
    local dev_freed=0
    
    local dev_caches=(
        ".npm/_cacache"
        ".npm/_logs"
        ".pnpm-store"
        ".yarn/cache"
        ".gradle/caches"
        ".gradle/wrapper/dists"
        ".cargo/registry/cache"
        ".cargo/git/checkouts"
        ".android/build-cache"
        ".android/cache"
        ".nuget/packages"
        ".m2/repository"
        ".cache/pip"
        ".cache/go-build"
    )
    
    for cache in "${dev_caches[@]}"; do
        local cache_path="$USER_HOME/$cache"
        if [[ -d "$cache_path" ]]; then
            local size
            size=$(get_size "$cache_path")
            dev_freed=$((dev_freed + size))
            safe_rm "$cache_path"
        fi
    done
    
    show_deleted "Dev caches" $dev_freed
}

clean_python_caches() {
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would clean Python caches (__pycache__, .pytest_cache)"
        return 0
    fi
    
    find "$USER_HOME" -type d \( -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache \) -exec rm -rf {} + 2>/dev/null || true
}

clean_node_caches() {
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would clean node_modules/.cache directories"
        return 0
    fi
    
    find "$USER_HOME" -type d -path "*/node_modules/.cache" -exec rm -rf {} + 2>/dev/null || true
}

clean_temp_files() {
    local before
    before=$(get_size "/tmp")
    
    if [[ "$DRY_RUN" == true ]]; then
        log_dim "[dry-run] Would clean /tmp"
        return 0
    fi
    
    # Only delete files older than 1 day and not in use
    find /tmp -mindepth 1 -mtime +1 -delete 2>/dev/null || true
    
    show_deleted "Temp files" $((before - $(get_size "/tmp")))
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Cleans system caches, orphan packages, logs, and temporary files.

Options:
  --dry-run    Show what would be deleted without actually deleting
  --help, -h   Show this help

Cleans:
  - Package manager cache (pacman/apt/dnf/yum)
  - AUR helper cache (yay/paru) on Arch
  - Orphan packages
  - Journal logs (older than 3 days)
  - Browser caches
  - Dev caches (npm, cargo, gradle, pip, etc.)
  - Python caches (__pycache__, .pytest_cache)
  - Node caches (node_modules/.cache)
  - Temp files (/tmp, older than 1 day)
EOF
    exit 0
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
    
    local distro pkg_manager
    distro=$(detect_distro)
    pkg_manager=$(detect_pkg_manager)
    
    log_info "Cleanup started..."
    log_dim "Distro: $distro, Package manager: $pkg_manager, User: $MAIN_USER"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warn "DRY RUN MODE - no files will be deleted"
    fi
    
    echo ""
    
    # Run all cleaners
    clean_aur_cache
    clean_package_cache
    clean_orphans
    clean_journal
    clean_browser_cache
    clean_dev_caches
    clean_python_caches
    clean_node_caches
    clean_temp_files
    
    echo ""
    log_ok "Total: $((total_freed / 1024 / 1024))M freed"
    df -h / | awk 'NR==2 {print "💾 Free: " $4 " (" $5 " used)"}'
}

main "$@"
