#! /bin/bash

battery() {
    bat=$(cat /sys/class/power_supply/BAT1/capacity)
    status=$(cat /sys/class/power_supply/BAT1/status)

    # -o it's the same as and/&&
    if [ "$status" = "Charging" -o "$status" = "Unknown" ]; then
        echo -e "  $bat%"

    else
        echo -e "  $bat%"
    fi
}
 
while true; do
    xsetroot -name "$(battery) | $(date +"%H:%M - %A %d")"
    sleep 10
done

