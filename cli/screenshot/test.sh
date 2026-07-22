#!/usr/bin/env bash
# click-capture — Hyprland/Wayland, stealth mode

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
SCREENSHOT_DIR="${HOME}/Pictures/QArchive"
PREFIX="Q"
CLICK_DELAY="0.5"
COUNTDOWN=5
CREATE_PDF=true
KEEP_IMAGES=true
LOG="${HOME}/.local/log/click-capture.log"

# ── usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") <repetitions> [options]

Options:
  --dir DIR         Output directory  (default: ~/Pictures/QArchive)
  --prefix PREFIX   File prefix       (default: Q)
  --delay SECONDS   Delay per action  (default: 0.5)
  --countdown SECS  Startup countdown (default: 5)
  --no-pdf          Skip PDF conversion
  --delete          Delete PNGs after PDF is created (default: move to raw/)
  -h, --help        Show this help

Examples:
  $(basename "$0") 10
  $(basename "$0") 5 --delay 1 --prefix Shot
  $(basename "$0") 20 --no-pdf
  $(basename "$0") 30 --delete
EOF
    exit 0
}

# ── notification helper ───────────────────────────────────────────────────────
# comment the notify-send line to disable all notifications
notify() {
    notify-send "$@"
    :
}

# ── arg parsing ───────────────────────────────────────────────────────────────
REPS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)       SCREENSHOT_DIR="$2"; shift 2 ;;
        --prefix)    PREFIX="$2";         shift 2 ;;
        --delay)     CLICK_DELAY="$2";    shift 2 ;;
        --countdown) COUNTDOWN="$2";      shift 2 ;;
        --no-pdf)    CREATE_PDF=false;    shift   ;;
        --delete)    KEEP_IMAGES=false;   shift   ;;
        -h|--help)   usage ;;
        -*)          echo "Unknown option: $1"; exit 1 ;;
        *)  [[ -z "$REPS" ]] && REPS="$1" || { echo "Unexpected argument: $1"; exit 1; }
            shift ;;
    esac
done

[[ -z "$REPS" ]] && usage

# ── validation ────────────────────────────────────────────────────────────────
[[ "$REPS"        =~ ^[0-9]+$          && "$REPS" -gt 0 ]] || { echo "Error: repetitions must be a positive integer"; exit 1; }
[[ "$COUNTDOWN"   =~ ^[0-9]+$                           ]] || { echo "Error: --countdown must be a positive integer";  exit 1; }
[[ "$CLICK_DELAY" =~ ^[0-9]+(\.[0-9]+)?$               ]] || { echo "Error: --delay must be a positive number";       exit 1; }

# ── dependency check ──────────────────────────────────────────────────────────
for cmd in grim dotool; do
    command -v "$cmd" &>/dev/null || { echo "Missing dependency: $cmd"; exit 1; }
done

# ── terminal detection — if no tty, silently redirect everything to log ───────
mkdir -p "$(dirname "$LOG")"
if [[ ! -t 1 ]]; then
    exec >> "$LOG" 2>&1
    echo "──── $(date '+%Y-%m-%d %H:%M:%S')  reps=$REPS  delay=$CLICK_DELAY ────"
fi

# ── setup ─────────────────────────────────────────────────────────────────────
RUN_DIR="${SCREENSHOT_DIR}/${PREFIX}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"
trap 'notify -u critical "click-capture" "Interrupted — cleaned up"; rm -rf "$RUN_DIR"; exit 1' INT TERM

# ── countdown ─────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    echo "Position cursor. Starting in ${COUNTDOWN}s..."
    for ((i=COUNTDOWN; i>0; i--)); do echo -n "$i "; sleep 1; done
    echo ""
else
    sleep "$COUNTDOWN"
fi

# ── capture loop ──────────────────────────────────────────────────────────────
for ((n=1; n<=REPS; n++)); do
    printf -v idx "%04d" "$n"
    out="${RUN_DIR}/${PREFIX}_${idx}.png"
    grim "$out"
    sleep "$CLICK_DELAY"
    echo "click left" | dotool
    sleep "$CLICK_DELAY"
    echo "[$n/$REPS] $out"
done

trap - INT TERM

# ── PDF conversion ────────────────────────────────────────────────────────────
if [[ "$CREATE_PDF" == true ]]; then
    PDF="${SCREENSHOT_DIR}/${PREFIX}_$(date +%H%M%S).pdf"
    if command -v magick &>/dev/null; then
        magick "${RUN_DIR}/${PREFIX}"_*.png "$PDF"
    elif command -v convert &>/dev/null; then
        convert "${RUN_DIR}/${PREFIX}"_*.png "$PDF"
    else
        echo "ImageMagick not found — PNGs kept in: $RUN_DIR"
        notify -u critical "click-capture" "ImageMagick not found — PNGs kept in: $RUN_DIR"
        exit 1
    fi
    if [[ "$KEEP_IMAGES" == true ]]; then
        RAW_DIR="${SCREENSHOT_DIR}/raw"
        mkdir -p "$RAW_DIR"
        mv "$RUN_DIR" "$RAW_DIR/"
        echo "PDF saved: $PDF"
        echo "PNGs kept: ${RAW_DIR}/$(basename "$RUN_DIR")"
    else
        rm -rf "$RUN_DIR"
        echo "PDF saved: $PDF"
    fi
    notify -u low "click-capture ✓" "$(basename "$PDF")"
else
    echo "Done. Screenshots saved in: $RUN_DIR"
    notify -u low "click-capture ✓" "$(basename "$RUN_DIR")"
fi
