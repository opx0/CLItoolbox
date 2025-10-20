#!/usr/bin/env bash

set -euo pipefail

ADMIN="$(id -nu 1000)"
YAY_CACHE="/home/$ADMIN/.cache/yay"
total_freed=0

get_size() {
    du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0
}

show_deleted() {
    local name="$1" size="$2" count="${3:-}"
    if [[ $size -gt 0 ]]; then
        size_mb=$((size / 1024 / 1024))
        [[ -n "$count" ]] && echo "✓ $name: $count items, ${size_mb}M" || echo "✓ $name: ${size_mb}M"
        total_freed=$((total_freed + size))
    fi
}

echo "🗑️  Cleanup started..."

if [[ -d "$YAY_CACHE" ]]; then
    before=$(get_size "$YAY_CACHE")
    mapfile -t installed < <(pacman -Qqm 2>/dev/null || true)
    removed=0

    while IFS= read -r -d '' dir; do
        pkg="$(basename "$dir")"
        if ! printf '%s\n' "${installed[@]}" | grep -qFx "$pkg"; then
            rm -rf "$dir"
            ((removed++))
        else
            rm -rf "$dir"/{src,pkg} 2>/dev/null || true
        fi
    done < <(find "$YAY_CACHE" -mindepth 1 -maxdepth 1 -type d -print0)

    show_deleted "YAY cache" $((before - $(get_size "$YAY_CACHE"))) "$removed pkgs"
fi

before=$(get_size "/var/cache/pacman/pkg")
count=$(paccache -qrk1 2>&1 | grep -oP '\d+(?= packages removed)' || echo 0)
ucount=$(paccache -qruk0 2>&1 | grep -oP '\d+(?= packages removed)' || echo 0)
show_deleted "Pacman cache" $((before - $(get_size "/var/cache/pacman/pkg"))) "$((count + ucount)) pkgs"

if orphans=$(pacman -Qdtq 2>/dev/null); then
    count=$(echo "$orphans" | wc -l)
    echo "$orphans" | pacman -Rns --noconfirm - &>/dev/null || true
    echo "✓ Orphans: $count pkgs removed"
fi

before=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[GM]' | head -1 || echo "0M")
journalctl --vacuum-time=3d &>/dev/null || true
after=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+[GM]' | head -1 || echo "0M")
[[ "$before" != "$after" ]] && echo "✓ Journal: $before → $after"

before=$(get_size "/home/$ADMIN/.cache")
find /home/$ADMIN/.cache -mindepth 1 -maxdepth 1 \( -name chromium -o -name google-chrome -o -name mozilla -o -name thumbnails \) -exec rm -rf {} + 2>/dev/null || true
show_deleted "Browser cache" $((before - $(get_size "/home/$ADMIN/.cache")))

dev_freed=0
for cache in .npm/_cacache .gradle/caches .cargo/registry/cache .android/build-cache; do
    [[ -d "/home/$ADMIN/$cache" ]] && { dev_freed=$((dev_freed + $(get_size "/home/$ADMIN/$cache"))); rm -rf "/home/$ADMIN/$cache"; }
done
show_deleted "Dev caches" $dev_freed

find /home -type d \( -name __pycache__ -o -name .pytest_cache -o -name node_modules/.cache \) -exec rm -rf {} + 2>/dev/null || true

before=$(get_size "/tmp")
find /tmp -mindepth 1 -delete 2>/dev/null || true
show_deleted "Temp files" $((before - $(get_size "/tmp")))

echo "✅ Total: $((total_freed / 1024 / 1024))M freed"
df -h / | awk 'NR==2 {print "💾 Free: " $4 " (" $5 " used)"}'
