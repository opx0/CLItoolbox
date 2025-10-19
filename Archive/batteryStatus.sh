total_time_remain() {
    time_remain=$(acpi | grep -oE '[0-9]+:[0-9]+:[0-9]+')
    IFS=':' read -r hours minutes seconds <<< "$time_remain"
    total_minutes=$((10#$hours * 60 + 10#$minutes)) 
    notify-send $total_minutes
}

while true
do
    battery_status=$(acpi | grep -oE 'Charging|Discharging')
    batteryPercentage=$(acpi | grep -oP '[0-9]+%')

    if [ "$battery_status" = 'Charging' ]; then
        if [ "${batteryPercentage%?}" -ge 75 ]; then
            notify-send "Battery is charging more than 75%: $batteryPercentage, disconnect charger"
            xdg-screensaver lock

        else
            notify-send "Battery is charging, but not in the range: $batteryPercentage"
        fi
    else
        notify-send "Not charging: $battery_status"
        
        if [ "${batteryPercentage%?}" -le 45 ]; then
            notify-send "Connect charger"
            xdg-screensaver lock
        else
            if [ "${batteryPercentage%?}" -le 21 ]; then
                notify-send 'You may charge based on your work dependency'
            else
                notify-send "Battery is $batteryPercentage, should enough for work" 
            fi
        fi
    fi

    # remaining_time=$(total_time_remain)
    # sleep_minutes=$((remaining_time / 5))

    # notify-send "Battery will run out after: $remaining_time min"
    # notify-send "Sleeping for $sleep_minutes minutes before checking again"
    # sleep "$sleep_minutes"m
    notify-send "Will notify after 10min"
    sleep 10m
done
