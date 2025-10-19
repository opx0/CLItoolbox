#!/bin/bash

dir="$HOME/Pictures"
base="a"
ext=".png"

max_num=0
for file in "$dir/${base}_"[0-9][0-9]"$ext"; do
    if [ -f "$file" ]; then
        num=$(basename "$file" "$ext" | sed "s/${base}_//")
        if [ "$num" -gt "$max_num" ]; then
            max_num=$num
        fi
    fi
done

next_num=$((max_num + 1))
output_file="$dir/${base}_$(printf "%02d" $next_num)$ext"
grim "$output_file"
