#!/bin/sh
# Sitzung sperren: der Lockscreen der dynamic-island-Shell (modules/lock),
# laeuft die Shell nicht, hyprlock (~/.config/hypr/hyprlock.conf).
#
# Benutzt von SUPER+L (profiles/simple.lua), hypridle (lock_cmd) und dem
# Power-Menue der Notch. Stuerzt die Shell bei gesperrter Sitzung ab, holt
# SUPER+ALT+L hyprlock zur Rettung (allow_session_lock_restore).

pidof hyprlock >/dev/null && exit 0

if out=$(qs -c dynamic-island ipc call lock isLocked 2>/dev/null); then
    [ "$out" = "true" ] && exit 0
    qs -c dynamic-island ipc call lock lock && exit 0
fi

exec hyprlock
