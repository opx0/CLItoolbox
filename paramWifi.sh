#!/bin/bash

NETWORKS=("aura" "codex")

# Function to get current network
get_current_network() {
    nmcli -t -f ACTIVE,SSID dev wifi | grep '^yes' | cut -d':' -f2
}

# Function to get available networks
get_available_networks() {
    nmcli -t -f SSID dev wifi | sort | uniq
}

# Function to switch networks
switch_network() {
    current_network=$(get_current_network)
    available_networks=$(get_available_networks)
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
}

# Function to watch for disconnections
watch_network() {
    echo "Watching for network disconnections..."
    while true; do
        current_network=$(get_current_network)
        if [ -z "$current_network" ]; then
            echo "Disconnected. Attempting to connect to available network..."
            for network in "${NETWORKS[@]}"; do
                if nmcli dev wifi connect "$network" >/dev/null 2>&1; then
                    echo "Connected to $network"
                    break
                fi
            done
        fi
        sleep 5
    done
}

# Main script
case "$1" in
    --watch)
        watch_network
        ;;
    --switch)
        switch_network
        ;;
    *)
        echo "Usage: $0 [--watch|--switch]"
        echo "  --watch: Monitor and auto-connect to available networks"
        echo "  --switch: Switch to next network in the list"
        exit 1
        ;;
esac