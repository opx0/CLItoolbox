#!/bin/bash
output_file="$HOME/Pictures/hello.png"
#grim -g "$(slurp)" "$output_file"
grim -g "$(slurp)" - | tee "$output_file" | wl-copy
#echo "Screenshot saved to: $output_file"
