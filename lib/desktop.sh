#!/usr/bin/env bash
# =============================================================================
# devbox/lib/desktop.sh — Desktop environment and display server detection
# =============================================================================
# Source this file for portable screenshot/input automation:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/desktop.sh"
# =============================================================================

# Source common utilities if not already loaded
if [[ -z "${C_RESET:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# -----------------------------------------------------------------------------
# SESSION DETECTION
# -----------------------------------------------------------------------------

# Detect display server
# Returns: wayland, x11, tty
detect_session() {
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "wayland"
    elif [[ -n "${DISPLAY:-}" ]]; then
        echo "x11"
    else
        echo "tty"
    fi
}

# Detect desktop environment
# Returns: hyprland, sway, gnome, kde, xfce, i3, etc.
detect_desktop() {
    local de="${XDG_CURRENT_DESKTOP:-}"
    local session="${XDG_SESSION_DESKTOP:-}"
    
    # Check Wayland compositors first
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        echo "hyprland"
    elif [[ -n "${SWAYSOCK:-}" ]]; then
        echo "sway"
    elif [[ "$de" =~ [Gg]nome || "$session" == "gnome" ]]; then
        echo "gnome"
    elif [[ "$de" =~ [Kk][Dd][Ee] || "$session" == "plasma" ]]; then
        echo "kde"
    elif [[ "$de" =~ [Xx]fce ]]; then
        echo "xfce"
    elif pgrep -x "i3" &>/dev/null; then
        echo "i3"
    elif pgrep -x "bspwm" &>/dev/null; then
        echo "bspwm"
    else
        echo "unknown"
    fi
}

# -----------------------------------------------------------------------------
# SCREENSHOT TOOLS
# -----------------------------------------------------------------------------

# Detect available screenshot tool
# Returns: grim, gnome-screenshot, spectacle, maim, scrot, import, none
detect_screenshot_tool() {
    local session
    session=$(detect_session)
    
    if [[ "$session" == "wayland" ]]; then
        # Wayland screenshot tools
        if command -v grim &>/dev/null; then
            echo "grim"
        elif command -v gnome-screenshot &>/dev/null; then
            echo "gnome-screenshot"
        elif command -v spectacle &>/dev/null; then
            echo "spectacle"
        else
            echo "none"
        fi
    else
        # X11 screenshot tools
        if command -v maim &>/dev/null; then
            echo "maim"
        elif command -v scrot &>/dev/null; then
            echo "scrot"
        elif command -v gnome-screenshot &>/dev/null; then
            echo "gnome-screenshot"
        elif command -v spectacle &>/dev/null; then
            echo "spectacle"
        elif command -v import &>/dev/null; then
            echo "import"  # ImageMagick
        else
            echo "none"
        fi
    fi
}

# Take screenshot using detected tool
# Usage: take_screenshot [output_path] [options]
#   Options: --region (select region), --window (active window)
take_screenshot() {
    local output="${1:-$HOME/Pictures/screenshot_$(date +%Y%m%d_%H%M%S).png}"
    local mode="${2:-fullscreen}"  # fullscreen, region, window
    local tool
    tool=$(detect_screenshot_tool)
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$output")"
    
    case "$tool" in
        grim)
            case "$mode" in
                region)
                    if command -v slurp &>/dev/null; then
                        grim -g "$(slurp)" "$output"
                    else
                        log_warn "slurp not found, taking fullscreen"
                        grim "$output"
                    fi
                    ;;
                *)
                    grim "$output"
                    ;;
            esac
            ;;
        maim)
            case "$mode" in
                region)
                    maim -s "$output"
                    ;;
                window)
                    maim -i "$(xdotool getactivewindow)" "$output"
                    ;;
                *)
                    maim "$output"
                    ;;
            esac
            ;;
        scrot)
            case "$mode" in
                region)
                    scrot -s "$output"
                    ;;
                window)
                    scrot -u "$output"
                    ;;
                *)
                    scrot "$output"
                    ;;
            esac
            ;;
        gnome-screenshot)
            case "$mode" in
                region)
                    gnome-screenshot -a -f "$output"
                    ;;
                window)
                    gnome-screenshot -w -f "$output"
                    ;;
                *)
                    gnome-screenshot -f "$output"
                    ;;
            esac
            ;;
        spectacle)
            case "$mode" in
                region)
                    spectacle -r -b -n -o "$output"
                    ;;
                window)
                    spectacle -a -b -n -o "$output"
                    ;;
                *)
                    spectacle -f -b -n -o "$output"
                    ;;
            esac
            ;;
        import)
            case "$mode" in
                region)
                    import "$output"
                    ;;
                *)
                    import -window root "$output"
                    ;;
            esac
            ;;
        none)
            die "No screenshot tool found. Install: grim (Wayland), maim/scrot (X11)"
            ;;
    esac
    
    if [[ -f "$output" ]]; then
        log_ok "Screenshot saved: $output"
        echo "$output"
    else
        die "Failed to capture screenshot"
    fi
}

# -----------------------------------------------------------------------------
# CLICK/INPUT TOOLS
# -----------------------------------------------------------------------------

# Detect available click automation tool
# Returns: ydotool, xdotool, none
detect_click_tool() {
    local session
    session=$(detect_session)
    
    if [[ "$session" == "wayland" ]]; then
        if command -v ydotool &>/dev/null; then
            echo "ydotool"
        elif command -v wtype &>/dev/null; then
            echo "wtype"
        else
            echo "none"
        fi
    else
        if command -v xdotool &>/dev/null; then
            echo "xdotool"
        else
            echo "none"
        fi
    fi
}

# Check if click tool daemon is running (for ydotool)
check_click_daemon() {
    local tool
    tool=$(detect_click_tool)
    
    if [[ "$tool" == "ydotool" ]]; then
        local socket="/run/user/$(id -u)/.ydotool_socket"
        if ! pgrep -x "ydotoold" &>/dev/null || [[ ! -S "$socket" ]]; then
            log_warn "ydotoold is not running!"
            echo ""
            echo "  Start with:"
            echo "    ${C_BOLD}sudo ydotoold --socket-own=\$(id -u):\$(id -g) --socket-path=\"$socket\"${C_RESET}"
            echo ""
            return 1
        fi
    fi
    return 0
}

# Simulate mouse click
# Usage: simulate_click [button] [count]
#   button: left, right, middle (default: left)
#   count: number of clicks (default: 1)
simulate_click() {
    local button="${1:-left}"
    local count="${2:-1}"
    local tool
    tool=$(detect_click_tool)
    
    case "$tool" in
        ydotool)
            # ydotool click codes: 0xC0 = left, 0xC1 = right, 0xC2 = middle
            local code
            case "$button" in
                left)   code="0xC0" ;;
                right)  code="0xC1" ;;
                middle) code="0xC2" ;;
            esac
            for ((i = 0; i < count; i++)); do
                ydotool click "$code"
            done
            ;;
        xdotool)
            local btn_num
            case "$button" in
                left)   btn_num=1 ;;
                right)  btn_num=3 ;;
                middle) btn_num=2 ;;
            esac
            xdotool click --repeat "$count" "$btn_num"
            ;;
        wtype)
            log_warn "wtype does not support mouse clicks"
            return 1
            ;;
        none)
            die "No click tool found. Install: ydotool (Wayland), xdotool (X11)"
            ;;
    esac
}

# Simulate key press
# Usage: simulate_key <key>
simulate_key() {
    local key="$1"
    local tool
    tool=$(detect_click_tool)
    
    case "$tool" in
        ydotool)
            ydotool key "$key"
            ;;
        xdotool)
            xdotool key "$key"
            ;;
        wtype)
            wtype -k "$key"
            ;;
        none)
            die "No input tool found"
            ;;
    esac
}

# Type text
# Usage: simulate_type <text>
simulate_type() {
    local text="$1"
    local tool
    tool=$(detect_click_tool)
    
    case "$tool" in
        ydotool)
            ydotool type "$text"
            ;;
        xdotool)
            xdotool type "$text"
            ;;
        wtype)
            wtype "$text"
            ;;
        none)
            die "No input tool found"
            ;;
    esac
}
