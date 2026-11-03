#!/bin/sh
# Sitzung sperren. Welcher Sperrbildschirm startet, entscheidet die
# Shell-Einstellung "Sperrbildschirm" (shell.json, lockscreen.style):
#
#   karte     Lockscreen der dynamic-island-Shell (quickshell/dynamic-island/
#             modules/lock); laeuft die Shell nicht, hyprlock mit
#             ~/.config/hypr/hyprlock.conf
#   vollbild  hyprlock mit ~/.config/hypr/hyprlock-full.conf (grosse Uhr,
#             Wochentag, Datum, Begruessung ueber dem unscharfen Wallpaper)
#
# Benutzt von SUPER+L (profiles/*.lua), hypridle (lock_cmd), dem Power-Menue
# der Notch und dem Idle-Dienst der Shell. Stuerzt die Shell bei gesperrter
# Sitzung ab, holt SUPER+ALT+L hyprlock zur Rettung
# (allow_session_lock_restore).

pidof hyprlock >/dev/null && exit 0

if out=$(qs -c dynamic-island ipc call lock isLocked 2>/dev/null); then
    [ "$out" = "true" ] && exit 0
fi

style=$(jq -r '.lock.style // "karte"' "$HOME/.config/dynamic-island/shell.json" 2>/dev/null)
if [ "$style" = "vollbild" ]; then
    exec hyprlock -c "$HOME/.config/hypr/hyprlock-full.conf"
fi

if qs -c dynamic-island ipc call lock lock 2>/dev/null; then
    exit 0
fi

exec hyprlock
