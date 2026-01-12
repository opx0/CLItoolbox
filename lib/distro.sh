#!/usr/bin/env bash
# =============================================================================
# devbox/lib/distro.sh — OS and package manager detection
# =============================================================================
# Source this file for portable package management:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/distro.sh"
# =============================================================================

# Source common utilities if not already loaded
if [[ -z "${C_RESET:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# -----------------------------------------------------------------------------
# DISTRO DETECTION
# -----------------------------------------------------------------------------

# Detect Linux distribution
# Returns: arch, debian, ubuntu, fedora, rhel, opensuse, alpine, unknown
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "${ID:-}" in
            arch|manjaro|endeavouros|garuda)
                echo "arch"
                ;;
            debian)
                echo "debian"
                ;;
            ubuntu|pop|linuxmint|elementary)
                echo "ubuntu"
                ;;
            fedora)
                echo "fedora"
                ;;
            rhel|centos|rocky|almalinux)
                echo "rhel"
                ;;
            opensuse*|sles)
                echo "opensuse"
                ;;
            alpine)
                echo "alpine"
                ;;
            *)
                # Check ID_LIKE for derivatives
                case "${ID_LIKE:-}" in
                    *arch*)   echo "arch" ;;
                    *debian*) echo "debian" ;;
                    *ubuntu*) echo "ubuntu" ;;
                    *fedora*|*rhel*) echo "fedora" ;;
                    *)        echo "unknown" ;;
                esac
                ;;
        esac
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "fedora"
    else
        echo "unknown"
    fi
}

# Detect package manager
# Returns: pacman, apt, dnf, yum, zypper, apk, unknown
detect_pkg_manager() {
    if command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    elif command -v apk &>/dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# Detect AUR helper (for Arch-based systems)
# Returns: yay, paru, trizen, none
detect_aur_helper() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    elif command -v trizen &>/dev/null; then
        echo "trizen"
    else
        echo "none"
    fi
}

# -----------------------------------------------------------------------------
# PACKAGE OPERATIONS
# -----------------------------------------------------------------------------

# Install package(s) - unified interface
pkg_install() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    
    case "$pkg_manager" in
        pacman)
            sudo pacman -S --noconfirm "$@"
            ;;
        apt)
            sudo apt update && sudo apt install -y "$@"
            ;;
        dnf)
            sudo dnf install -y "$@"
            ;;
        yum)
            sudo yum install -y "$@"
            ;;
        zypper)
            sudo zypper install -y "$@"
            ;;
        apk)
            sudo apk add "$@"
            ;;
        *)
            die "Unknown package manager"
            ;;
    esac
}

# Check if package is installed
pkg_installed() {
    local pkg="$1"
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    
    case "$pkg_manager" in
        pacman)
            pacman -Qi "$pkg" &>/dev/null
            ;;
        apt)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            ;;
        dnf|yum)
            rpm -q "$pkg" &>/dev/null
            ;;
        zypper)
            rpm -q "$pkg" &>/dev/null
            ;;
        apk)
            apk info -e "$pkg" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Clean package cache
pkg_cache_clean() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    
    case "$pkg_manager" in
        pacman)
            if command -v paccache &>/dev/null; then
                sudo paccache -rk1 2>/dev/null || true
                sudo paccache -ruk0 2>/dev/null || true
            fi
            ;;
        apt)
            sudo apt clean
            sudo apt autoclean
            ;;
        dnf)
            sudo dnf clean all
            ;;
        yum)
            sudo yum clean all
            ;;
        zypper)
            sudo zypper clean --all
            ;;
        apk)
            sudo apk cache clean
            ;;
    esac
}

# Remove orphan packages
pkg_remove_orphans() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    
    case "$pkg_manager" in
        pacman)
            local orphans
            if orphans=$(pacman -Qdtq 2>/dev/null); then
                echo "$orphans" | sudo pacman -Rns --noconfirm - 2>/dev/null || true
            fi
            ;;
        apt)
            sudo apt autoremove -y
            ;;
        dnf)
            sudo dnf autoremove -y
            ;;
        yum)
            sudo yum autoremove -y
            ;;
        zypper)
            sudo zypper packages --orphaned | tail -n +5 | awk '{print $5}' | xargs -r sudo zypper remove -y
            ;;
        apk)
            # Alpine doesn't have a direct equivalent
            :
            ;;
    esac
}

# -----------------------------------------------------------------------------
# CACHE PATHS
# -----------------------------------------------------------------------------

# Get package cache directory
get_pkg_cache_dir() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    
    case "$pkg_manager" in
        pacman)
            echo "/var/cache/pacman/pkg"
            ;;
        apt)
            echo "/var/cache/apt/archives"
            ;;
        dnf|yum)
            echo "/var/cache/dnf"
            ;;
        zypper)
            echo "/var/cache/zypp"
            ;;
        apk)
            echo "/var/cache/apk"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get AUR cache directory (Arch only)
get_aur_cache_dir() {
    local aur_helper
    aur_helper=$(detect_aur_helper)
    local user="${SUDO_USER:-$USER}"
    
    case "$aur_helper" in
        yay)
            echo "/home/$user/.cache/yay"
            ;;
        paru)
            echo "/home/$user/.cache/paru"
            ;;
        trizen)
            echo "/home/$user/.cache/trizen"
            ;;
        *)
            echo ""
            ;;
    esac
}
