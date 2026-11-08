#!/usr/bin/env bash
################################################################################
# Quelle: https://github.com/mahaveergurjar/Hyprlock-Dots
# Credit: mahaveergurjar -- Layouts, Farbschema und Widget-Skripte dieses
# Lockscreen-Setups stammen aus diesem Repo. Lokal angepasst; was geaendert
# wurde, steht im git log dieses Repos.
################################################################################

if [[ "$(playerctl -p spotify status 2>/dev/null)" == "Playing" ]]; then
    pkill glava

    # Start Glava (NOT desktop mode)
    glava &
    sleep 0.6

    # Focus Glava window
    hyprctl dispatch focuswindow class:glava
    sleep 0.1

    # Fullscreen focused window
    hyprctl dispatch fullscreen 

    # Lock screen
    hyprlock --config ~/.config/hyprlock/music.conf
else
    hyprlock
fi

pkill glava
