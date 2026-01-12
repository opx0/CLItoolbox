#!/usr/bin/env bash
# =============================================================================
# devbox/cli/screenshot/capture.sh — Portable screenshot tool
# =============================================================================
# Works on both X11 and Wayland, auto-detects available tools
# Usage: capture.sh [output_path] [--region|--window]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/desktop.sh"

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

SCREENSHOT_DIR="${SCREENSHOT_DIR:-$HOME/Pictures}"
SCREENSHOT_PREFIX="${SCREENSHOT_PREFIX:-screenshot}"
SCREENSHOT_EXT="${SCREENSHOT_EXT:-.png}"

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

main() {
    local output=""
    local mode="fullscreen"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --region|-r)
                mode="region"
                shift
                ;;
            --window|-w)
                mode="window"
                shift
                ;;
            --help|-h)
                echo "Usage: $(basename "$0") [output_path] [--region|--window]"
                echo ""
                echo "Options:"
                echo "  --region, -r    Select a region to capture"
                echo "  --window, -w    Capture active window"
                echo "  --help, -h      Show this help"
                echo ""
                echo "Environment variables:"
                echo "  SCREENSHOT_DIR     Output directory (default: ~/Pictures)"
                echo "  SCREENSHOT_PREFIX  Filename prefix (default: screenshot)"
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                output="$1"
                shift
                ;;
        esac
    done
    
    # Generate output path if not provided
    if [[ -z "$output" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        output="${SCREENSHOT_DIR}/${SCREENSHOT_PREFIX}_${timestamp}${SCREENSHOT_EXT}"
        
        # Handle filename collision
        local counter=1
        while [[ -f "$output" ]]; do
            output="${SCREENSHOT_DIR}/${SCREENSHOT_PREFIX}_${timestamp}_${counter}${SCREENSHOT_EXT}"
            ((counter++))
        done
    fi
    
    # Take screenshot
    local session tool
    session=$(detect_session)
    tool=$(detect_screenshot_tool)
    
    log_info "Session: $session, Tool: $tool, Mode: $mode"
    
    take_screenshot "$output" "$mode"
}

main "$@"
