#!/bin/bash
# Screenshot + click automation (requires: ydotoold, grim, imagemagick)

# Config
SCREENSHOT_DIR="$HOME/Pictures"
SCREENSHOT_PREFIX="Q"
SCREENSHOT_EXT=".png"
YDOTOOL_SOCKET="/run/user/1000/.ydotool_socket"

# Check if ydotoold service is running
check_ydotoold() {
    if pgrep -x "ydotoold" > /dev/null && [ -S "$YDOTOOL_SOCKET" ]; then
        return 0
    else
        return 1
    fi
}

# Take screenshot (numbered, or timestamped if uncommented)
take_screenshot() {
    local num=$1
    local output_file="${SCREENSHOT_DIR}/${SCREENSHOT_PREFIX}_${num}${SCREENSHOT_EXT}"
    # Uncomment below for timestamped filenames
    # local timestamp=$(date +%Y%m%d_%H%M%S)
    # local output_file="${SCREENSHOT_DIR}/${SCREENSHOT_PREFIX}_${timestamp}${SCREENSHOT_EXT}"
    grim "$output_file" 2>/dev/null
    echo "Screenshot saved: $output_file"
}

# Validate arguments
if [ -z "$1" ]; then
    echo "Usage: $0 <number_of_repetitions>"
    exit 1
fi

repetitions=$1

if ! [[ "$repetitions" =~ ^[0-9]+$ ]] || [ "$repetitions" -lt 1 ]; then
    echo "Error: Please provide a valid positive number"
    exit 1
fi

# Check service status
if ! check_ydotoold; then
    echo "ERROR: ydotoold is NOT running!"
    echo "Run in another terminal: sudo ydotoold --socket-own=\$(id -u):\$(id -g) --socket-path=\"$YDOTOOL_SOCKET\""
    exit 1
fi

# Start automation
echo "✓ ydotoold running"
echo "Position cursor now! Starting in 5 seconds..."

sleep 5

# Main loop: screenshot + click
count=1
while [ $count -le $repetitions ]; do
    echo "[$count/$repetitions]"
    take_screenshot $count
    sleep 0.5
    ydotool click 0xC0
    sleep 0.5
    count=$((count + 1))
done

# Convert screenshots to PDF
pdf_time=$(date +%H%M%S)
pdf_name="Qz_${pdf_time}.pdf"
echo "Converting to PDF..."
cd "$SCREENSHOT_DIR"
magick ${SCREENSHOT_PREFIX}_*.png "$pdf_name"
sleep 2 # Wait for ImageMagick to finish
rm -f ${SCREENSHOT_PREFIX}_*.png
echo "✓ Done: $SCREENSHOT_DIR/$pdf_name"
