#!/usr/bin/env bash
# ====================================================================
#  wallpaper.sh - Hintergrundbild neu laden oder wechseln
#  Erstellt von Nox am 04.10.2026
#
#  Aufruf:
#     wallpaper.sh            -> neu laden (gleiches Bild)
#     wallpaper.sh PFAD       -> anderes Bild nehmen
#     wallpaper.sh stop       -> Hintergrundbild abschalten
#
#  Wenn du das Bild tauschen willst, ohne Hyprland neu zu starten:
#     cp ~/Bilder/neues.jpg \
#        ~/.local/share/wallpapers/Tokyo-Night/Tokyo-Night.jpg
#     wallpaper.sh
#
#  Bindestaste dafuer: Super+Shift+B  (siehe binds.conf)
#  (Stand 04.10.2026: hier stand frueher "W". W war belegt, weil
#  Super+Shift+W die Fenstergroesse veraendert - siehe binds.conf)
# ====================================================================

set -u

WALL="$HOME/.local/share/wallpapers/Tokyo-Night/Tokyo-Night.jpg"
LOG="$HOME/.cache/hypr-swaybg.log"

# Alles Beendige stoppen, damit nie zwei Hintergrundbilder kaempfen
# (swaybg 1.2.2 hat keine Pidfile-Option, daher so)
if pgrep -x swaybg >/dev/null 2>&1; then
    pkill -x swaybg
    sleep 0.3
fi

case "${1:-}" in
    stop)
        echo "Hintergrundbild abgeschaltet."
        exit 0
        ;;
    "")  # Bild bleibt wie es ist
        ;;
    *)
        if [ ! -r "$1" ]; then
            echo "FEHLER: Datei nicht lesbar: $1" >&2
            exit 1
        fi
        WALL="$1"
        ;;
esac

if ! command -v swaybg >/dev/null 2>&1; then
    echo "FEHLER: swaybg ist nicht installiert." >&2
    exit 1
fi

setsid swaybg -i "$WALL" -m fill >"$LOG" 2>&1 &
sleep 1

if pgrep -x swaybg >/dev/null 2>&1; then
    echo "Hintergrundbild gesetzt: $WALL"
    sed 's/^/  /' "$LOG" 2>/dev/null
else
    echo "FEHLER: swaybg ist nicht gestartet:" >&2
    sed 's/^/  /' "$LOG" >&2 2>/dev/null
    exit 1
fi
