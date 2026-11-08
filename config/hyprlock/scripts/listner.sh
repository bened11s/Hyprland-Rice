#!/bin/bash
################################################################################
# Quelle: https://github.com/mahaveergurjar/Hyprlock-Dots
# Credit: mahaveergurjar -- Layouts, Farbschema und Widget-Skripte dieses
# Lockscreen-Setups stammen aus diesem Repo. Lokal angepasst; was geaendert
# wurde, steht im git log dieses Repos.
################################################################################

tail -f /tmp/dunst_log | while read -r line; do
    echo "New Notification: $line"
    hyprctl hyprlock:text notify1 "$line"
done
