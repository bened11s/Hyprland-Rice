#!/usr/bin/env bash
# ====================================================================
#  Autostart.sh - Startet die Bestandteile fuer einen Hyprland-Start
#  Erstellt von Nox am 03.10.2026, ueberarbeitet am 04.10.2026
#
#  Aufruf: einmalig aus autostart.conf beim Start von Hyprland.
#  Logs:  ~/.cache/hypr-start.log     (Was wurde gestartet?)
#         ~/.cache/hypr-monitors.log  (Was hat Hyprland erkannt?)
#         ~/.cache/hypr-swaybg.log    (Ausgabe des Hintergrundbildes)
#
#  Grundsatz: Jeder Schritt ist einzeln abgesichert. Ein Fehler hier
#  darf den restlichen Start niemals aufhalten.
# ====================================================================

LOG="$HOME/.cache/hypr-start.log"
MONLOG="$HOME/.cache/hypr-monitors.log"
BGLOG="$HOME/.cache/hypr-swaybg.log"

# Hintergrundbild - identisch zum Wallpaper unter Plasma
WALL="$HOME/.local/share/wallpapers/Tokyo-Night/Tokyo-Night.jpg"

log() {
    printf '[hypr-start] %s\n' "$*" >>"$LOG"
}

: >"$LOG"
log "Hyprland-Autostart gestartet"

# --- 0. Monitore protokollieren -------------------------------------
# Wichtig fuer die Fehlersuche: genau das, was Hyprland erkannt hat.
# Beim ersten Test war nur die Statusleiste zu sehen - dieses Log
# sagt uns danach, ob die richtigen Grafikkarten ueberhaupt da waren.
{
    echo "=== $(date '+%F %T') - hyprctl version ==="
    hyprctl version 2>&1
    echo
    echo "=== hyprctl monitors all ==="
    hyprctl monitors all 2>&1
    echo
    echo "=== Grafikkarten, die Hyprland benutzt ==="
    echo "AQ_DRM_DEVICES=${AQ_DRM_DEVICES:-<nicht gesetzt>}"
} >"$MONLOG" 2>&1

# --- 1. Unsere eigene Statusleiste ----------------------------------
# Gleiche Leiste wie unter Plasma: ~/.config/quickshell/tokyonight
# Die Leiste waehlt ihre Monitore selbst (ausser dem Hauptmonitor
# HDMI-A-1), funktioniert also unter jedem Compositor.
if command -v qs >/dev/null 2>&1; then
    setsid qs -c "$HOME/.config/quickshell/tokyonight" >/dev/null 2>&1 &
    log "Statusleiste (Quickshell) gestartet"
else
    log "FEHLER: qs (Quickshell) nicht gefunden"
fi

# --- 2. Hintergrundbild ---------------------------------------------
# WARUM SWAYBG UND NICHT HYPRPAPER?
# Das hyprpaper 0.8.4 dieser Installation hat ein unbekanntes
# Config-Format. Es kennt den Schluessel "preload" nicht mehr
# (der String fehlt vollstaendig im Binary) und meldet fuer jeden
# Monitor "has no target: no wp will be created". Genau das war der
# schwarze Bildschirm beim ersten Test.
# swaybg hat gar keine Config-Datei und laeuft unter jedem
# wlroots-Compositor.
#
# WICHTIG: swaybg 1.2.2 kennt KEIN -f/--pidfile. Deshalb wird die
# PID hier nicht ueber eine Datei, sondern ueber pgrep/pkill
# verwaltet. Die Ausgabe landet in hypr-swaybg.log.
(
    # Auf die Monitore warten (maximal 10 Sekunden)
    for _ in $(seq 1 20); do
        sleep 0.5
        if hyprctl monitors 2>/dev/null | grep -q "Monitor"; then
            break
        fi
    done

    if [ ! -r "$WALL" ]; then
        log "FEHLER: Hintergrundbild nicht lesbar: $WALL"
        exit 0
    fi

    if ! command -v swaybg >/dev/null 2>&1; then
        log "FEHLER: swaybg nicht installiert - kein Hintergrundbild"
        exit 0
    fi

    if pgrep -x swaybg >/dev/null 2>&1; then
        log "Hintergrundbild laeuft bereits"
    else
        setsid swaybg -i "$WALL" -m fill >"$BGLOG" 2>&1 &
        sleep 1
        if pgrep -x swaybg >/dev/null 2>&1; then
            log "Hintergrundbild (swaybg) gestartet: $(basename "$WALL")"
            # Welche Monitore hat swaybg gesehen? Das ist die
            # entscheidende Zeile fuer die Fehlersuche.
            while read -r line; do
                log "swaybg: $line"
            done <"$BGLOG"
        else
            log "FEHLER: swaybg ist sofort wieder ausgestiegen. Ausgabe:"
            sed 's/^/         /' "$BGLOG" >>"$LOG" 2>/dev/null
        fi
    fi
) &

# --- 3. Mauszeiger wie unter Plasma ---------------------------------
sleep 1
if hyprctl setcursor WhiteSur-cursors 24 >/dev/null 2>&1; then
    log "Mauszeiger gesetzt: WhiteSur-cursors 24"
else
    log "HINWEIS: Mauszeiger konnte nicht gesetzt werden"
fi

log "Autostart fertig"
