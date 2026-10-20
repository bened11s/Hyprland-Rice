#!/usr/bin/env bash
# ====================================================================
#  screenshot.sh - Bildschirmfotos unter Hyprland
#  Erstellt von Nox am 03.10.2026, korrigiert 04.10.2026
#
#  Aufruf:  screenshot.sh full   -> ganzer Bildschirm (alle Monitore)
#           screenshot.sh area   -> Bereich auswaehlen
#           screenshot.sh color  -> Farbe auswaehlen (hyprpicker)
#
#  Ergebnis landet in ~/Bilder/Screenshots UND in der Zwischenablage.
# ====================================================================

set -u

MODE="${1:-full}"

# Bilderordner wie im System eingestellt
PICDIR="$(xdg-user-dir PICTURES 2>/dev/null)"
[ -z "$PICDIR" ] && PICDIR="$HOME/Bilder"
OUTDIR="$PICDIR/Screenshots"

mkdir -p "$OUTDIR"

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Hyprland" -i computer-screen "Screenshot" "$1" 2>/dev/null
    fi
    return 0
}

# Wandert das Bild in die Zwischenablage. wl-copy bleibt im
# Hintergrund laufen, weil es die Daten sonst nicht mehr haelt.
to_clipboard() {
    wl-copy -t image/png <"$1" 2>/dev/null &
    return 0
}

case "$MODE" in
    full)
        sleep 0.2   # kurz warten, bis die Taste losgelassen ist
        FILE="$OUTDIR/Bildschirm_${STAMP}.png"
        if grim "$FILE" 2>/dev/null; then
            to_clipboard "$FILE"
            notify "Gespeichert: $(basename "$FILE")"
        else
            notify "FEHLER: grim konnte nicht aufnehmen"
        fi
        ;;

    area)
        sleep 0.3
        # slurp erst beenden, wenn es wirklich eine Ausgabe gab.
        # Sonst wuerde grim mit leerem -g "" laufen und die Meldung
        # waere "grim kaputt" statt "Auswahl abgebrochen".
        REGION="$(slurp 2>/dev/null)" || REGION=""
        if [ -z "$REGION" ]; then
            notify "Auswahl abgebrochen"
            exit 0
        fi
        FILE="$OUTDIR/Bereich_${STAMP}.png"
        if grim -g "$REGION" "$FILE" 2>/dev/null; then
            to_clipboard "$FILE"
            notify "Gespeichert: $(basename "$FILE")"
        else
            notify "FEHLER: grim konnte den Bereich nicht aufnehmen"
        fi
        ;;

    color)
        if hyprpicker >/dev/null 2>&1; then
            notify "Farbe gewaehlt"
        fi
        ;;

    *)
        echo "Aufruf: $0 full|area|color" >&2
        exit 1
        ;;
esac
