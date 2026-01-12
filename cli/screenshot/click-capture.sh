#!/usr/bin/env bash
# =============================================================================
# devbox/cli/screenshot/click-capture.sh — Screenshot + click automation
# =============================================================================
# Takes repeated screenshots with clicks, then converts to PDF
# Works on both X11 and Wayland, auto-detects available tools
# Usage: click-capture.sh <number_of_repetitions>
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
source "$SCRIPT_DIR/../../lib/desktop.sh"

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

SCREENSHOT_DIR="${SCREENSHOT_DIR:-$HOME/Pictures}"
SCREENSHOT_PREFIX="${SCREENSHOT_PREFIX:-Q}"
SCREENSHOT_EXT="${SCREENSHOT_EXT:-.png}"
COUNTDOWN="${COUNTDOWN:-5}"
CLICK_DELAY="${CLICK_DELAY:-0.5}"

# -----------------------------------------------------------------------------
# FUNCTIONS
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") <number_of_repetitions> [options]

Takes repeated screenshots with mouse clicks, then converts to PDF.

Options:
  --dir DIR         Output directory (default: ~/Pictures)
  --prefix PREFIX   Screenshot prefix (default: Q)
  --delay SECONDS   Delay between actions (default: 0.5)
  --countdown SECS  Countdown before starting (default: 5)
  --no-pdf          Skip PDF conversion
  --help, -h        Show this help

Examples:
  $(basename "$0") 10              # Take 10 screenshots
  $(basename "$0") 5 --delay 1     # Take 5 screenshots, 1s delay
  $(basename "$0") 20 --no-pdf     # Take 20, keep PNGs
EOF
    exit 0
}

check_pdf_tool() {
    if command -v magick &>/dev/null; then
        echo "magick"
    elif command -v convert &>/dev/null; then
        echo "convert"
    else
        echo "none"
    fi
}

convert_to_pdf() {
    local output_dir="$1"
    local prefix="$2"
    local pdf_tool
    pdf_tool=$(check_pdf_tool)
    
    local pdf_time
    pdf_time=$(date +%H%M%S)
    local pdf_name="Qz_${pdf_time}.pdf"
    local pdf_path="${output_dir}/${pdf_name}"
    
    log_info "Converting to PDF..."
    
    case "$pdf_tool" in
        magick)
            magick "${output_dir}/${prefix}"_*.png "$pdf_path"
            ;;
        convert)
            convert "${output_dir}/${prefix}"_*.png "$pdf_path"
            ;;
        none)
            log_warn "ImageMagick not found. Skipping PDF conversion."
            log_info "Install with: sudo pacman -S imagemagick (Arch) or sudo apt install imagemagick (Debian)"
            return 1
            ;;
    esac
    
    if [[ -f "$pdf_path" ]]; then
        # Clean up PNGs
        rm -f "${output_dir}/${prefix}"_*.png
        log_ok "PDF created: $pdf_path"
    else
        log_error "Failed to create PDF"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

main() {
    local repetitions=""
    local create_pdf=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)
                SCREENSHOT_DIR="$2"
                shift 2
                ;;
            --prefix)
                SCREENSHOT_PREFIX="$2"
                shift 2
                ;;
            --delay)
                CLICK_DELAY="$2"
                shift 2
                ;;
            --countdown)
                COUNTDOWN="$2"
                shift 2
                ;;
            --no-pdf)
                create_pdf=false
                shift
                ;;
            --help|-h)
                usage
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [[ -z "$repetitions" ]]; then
                    repetitions="$1"
                else
                    die "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done
    
    # Validate repetitions
    if [[ -z "$repetitions" ]]; then
        usage
    fi
    
    if ! [[ "$repetitions" =~ ^[0-9]+$ ]] || [[ "$repetitions" -lt 1 ]]; then
        die "Please provide a valid positive number"
    fi
    
    # Check tools
    local session click_tool screenshot_tool
    session=$(detect_session)
    click_tool=$(detect_click_tool)
    screenshot_tool=$(detect_screenshot_tool)
    
    log_info "Session: $session"
    log_info "Screenshot tool: $screenshot_tool"
    log_info "Click tool: $click_tool"
    
    if [[ "$screenshot_tool" == "none" ]]; then
        die "No screenshot tool found"
    fi
    
    if [[ "$click_tool" == "none" ]]; then
        die "No click automation tool found"
    fi
    
    # Check click daemon if needed
    if ! check_click_daemon; then
        exit 1
    fi
    
    # Ensure output directory exists
    ensure_dir "$SCREENSHOT_DIR"
    
    # Countdown
    log_ok "Tools ready!"
    echo "Position cursor now! Starting in ${COUNTDOWN} seconds..."
    for ((i = COUNTDOWN; i > 0; i--)); do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    log_info "Starting automation..."
    
    # Main loop
    local screenshot_files=()
    for ((count = 1; count <= repetitions; count++)); do
        echo "[$count/$repetitions]"
        
        local output_file="${SCREENSHOT_DIR}/${SCREENSHOT_PREFIX}_${count}${SCREENSHOT_EXT}"
        
        # Take screenshot
        take_screenshot "$output_file" "fullscreen" >/dev/null
        screenshot_files+=("$output_file")
        
        # Click and wait
        sleep "$CLICK_DELAY"
        simulate_click "left"
        sleep "$CLICK_DELAY"
    done
    
    # Convert to PDF
    if [[ "$create_pdf" == true ]]; then
        convert_to_pdf "$SCREENSHOT_DIR" "$SCREENSHOT_PREFIX"
    else
        log_ok "Done! Screenshots saved in $SCREENSHOT_DIR"
    fi
}

main "$@"
