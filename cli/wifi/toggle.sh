#!/bin/bash

NETWORKS=("aura" "codex")

current_network=$(nmcli -t -f ACTIVE,SSID dev wifi | grep '^yes' | cut -d':' -f2)
available_networks=$(nmcli -t -f SSID dev wifi | sort | uniq)

next_network=""
found_current=false

for network in "${NETWORKS[@]}"; do
    if echo "$available_networks" | grep -q "^$network$"; then
        if [ "$found_current" = true ]; then
            next_network=$network
            break
        fi
        if [ "$network" = "$current_network" ]; then
            found_current=true
        fi
    fi
done

if [ -z "$next_network" ]; then
    for network in "${NETWORKS[@]}"; do
        if echo "$available_networks" | grep -q "^$network$"; then
            next_network=$network
            break
        fi
    done
fi

if [ -n "$next_network" ] && [ "$next_network" != "$current_network" ]; then
    echo "Switching from $current_network to $next_network"
    nmcli dev wifi connect "$next_network"
fi
