#!/bin/bash
################################################################################
# Quelle: https://github.com/mahaveergurjar/Hyprlock-Dots
# Credit: mahaveergurjar -- Layouts, Farbschema und Widget-Skripte dieses
# Lockscreen-Setups stammen aus diesem Repo. Lokal angepasst; was geaendert
# wurde, steht im git log dieses Repos.
################################################################################
# Simple stopwatch script with Hyprlock update

SECONDS=0
while true; do
    # Format time as minutes and seconds
    time_elapsed="$(($SECONDS / 60)) min : $(($SECONDS % 60)) sec"
    echo "$time_elapsed"
    
    sleep 1
    ((SECONDS++))
done
