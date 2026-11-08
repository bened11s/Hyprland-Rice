#!/bin/sh
# Sitzung beenden, vorher Apps sauber schliessen, die ihren Zustand erst beim
# Beenden schreiben. Spotify ignoriert SIGTERM und speichert seine
# Einstellungen nur, wenn das Fenster regulaer geschlossen wird; ein direktes
# `hyprctl dispatch exit` reisst ihm die Wayland-Verbindung weg und die
# Aenderungen seit dem letzten Start sind verloren.
#
#   session-exit.sh logout|reboot|poweroff

classes='^(Spotify)$'

addrs=$(hyprctl -j clients | jq -r --arg re "$classes" \
    '.[] | select((.class | test($re)) or (.initialTitle | test("^Spotify"))) | .address')

for a in $addrs; do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
done

# bis zu 5 s warten, bis die Fenster weg sind
i=0
while [ -n "$addrs" ] && [ $i -lt 50 ]; do
    left=$(hyprctl -j clients | jq -r '.[].address')
    still=
    for a in $addrs; do
        echo "$left" | grep -qx "$a" && still=1
    done
    [ -z "$still" ] && break
    sleep 0.1
    i=$((i + 1))
done
# Spotify schreibt die Prefs erst nach dem Schliessen des Fensters
[ -n "$addrs" ] && sleep 1

case "$1" in
    logout) hyprctl dispatch 'hl.dsp.exit()' ;;
    reboot) systemctl reboot ;;
    poweroff) systemctl poweroff ;;
    *) echo "usage: $0 logout|reboot|poweroff" >&2; exit 1 ;;
esac
