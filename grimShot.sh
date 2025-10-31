#!/bin/bash

dir="$HOME/Pictures"
base="hello"
ext=".png"

#output_file="${dir}/${base}${ext}"


 timestamp=$(date +%Y%m%d_%H%M%S)
 output_file="${dir}/${base}_${timestamp}${ext}"

 counter=1
 while [[ -f "$output_file" ]]; do
     output_file="${dir}/${base}_${timestamp}_${counter}${ext}"
     ((counter++))
 done

grim "$output_file" 2>/dev/null
