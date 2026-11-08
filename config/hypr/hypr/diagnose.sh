#!/usr/bin/env bash
# ====================================================================
#  diagnose.sh - Misst, ob und wie lange Hyprland wirklich sichtbar ist
#  Fassung 2 vom 04.10.2026, Nox
#
#  WARUM FASSUNG 2
#  ---------------
#  Fassung 1 hat genau einmal gemessen, 20 Sekunden nach dem Login.
#  Damit wurde ein schwarzer Bildschirm als "alles in Ordnung"
#  gemeldet, weil zu diesem Zeitpunkt noch alles leuchtete. Der
#  Bildschirm wurde kurz danach schwarz. Ein Messgerät, das nur eine
#  Momentaufnahme macht, beantwortet die Frage "wird es nachher
#  schwarz?" nicht.
#
#  Ausserdem schrieben die Abschnitte 2, 4, 5 und 7 ihre Daten nach
#  stdout statt in die Logdatei - im Log standen nur die
#  Ueberschriften. Behoben mit einer Umleitung in Zeile XY.
#
#  DIE KERNMETRIKE
#  ---------------
#  Wie viele "Cannot commit when a page-flip is awaiting"-Meldungen
#  stehen zu jedem Messzeitpunkt im Log?
#    - waechst die Zahl nicht mehr  -> die Ausgabewege haengen nicht
#    - waechst sie weiter           -> der Weg zum Bildschirm ist verstopft
#  Das trennt "Bild kam einmal an" von "Bild kommt dauerhaft an".
#
#  Aufruf:  automatisch aus autostart.conf, 20s nach dem Login
#           oder von Hand:  ~/.config/hypr/hypr/diagnose.sh
#  Ergebnis: ~/.cache/hypr-diagnose.log  +  .png je Monitor und Runde
# ====================================================================

LOG="$HOME/.cache/hypr-diagnose.log"
DIR="$HOME/.cache/hypr-diagnose"
mkdir -p "$DIR" "$HOME/.cache"

# ALLES landet in der Logdatei - stdout eingeschlossen. Genau hier
# hatte Fassung 1 den Fehler gemacht.
exec > >(tee -a "$LOG") 2>&1

echo "==================================================================="
echo " HYPRLAND-BILDBEFUND (Fassung 2)   Start $(date '+%F %T')"
echo "==================================================================="
echo

if ! pgrep -x Hyprland >/dev/null 2>&1; then
  echo "ERGEBNIS: Hyprland laeuft NICHT. Keine Diagnose moeglich."
  echo "  (Dieses Skript muss aus einer Hyprland-Sitzung heraus laufen.)"
  exit 0
fi
echo "[1] Hyprland laeuft, PID $(pgrep -x Hyprland | tr '\n' ' ')"

# Signatur frisch ableiten: Hyprland erzeugt bei jedem Start ein neues
# Verzeichnis, ein fester Wert waere beim naechsten Start falsch.
S=$(ls -t /run/user/1000/hypr/ 2>/dev/null | grep -v '^$' | head -1)
export HYPRLAND_INSTANCE_SIGNATURE="$S"
LOGF="/run/user/1000/hypr/$S/hyprland.log"
echo "[1b] Instanz-Signatur: ${S:-unbekannt}"
echo "[1c] Logdatei:        ${LOGF:-keine}"
echo

echo "[2] hyprctl monitors"
echo "-------------------------------------------------------------------"
hyprctl monitors 2>&1 | grep -vE '^\s*$' | cut -c1-150 || echo "    hyprctl antwortet nicht"
echo

echo "[3] DRM-Hardware"
echo "-------------------------------------------------------------------"
for c in /sys/class/drm/card*; do
  n=$(basename "$c")
  case "$n" in card[0-9]*) ;; *) continue ;; esac
  drv=$(cat "$c/device/uevent" 2>/dev/null | grep -oP '(?<=DRIVER=).*')
  conn=$(ls "$c/device/drm/" 2>/dev/null | grep -E '^card[0-9]+-' | sed "s/^$n-//" | tr '\n' ',')
  echo "    $n  Treiber=$(printf '%-8s' "${drv:-?}")  ${conn}"
done
echo "    (evdi = DisplayLink, hat planmaessig keinen Render-Node)"
echo

# ---------------------------------------------------------------------
# Eine Messrunde
# ---------------------------------------------------------------------
runde() {
  local nr="$1" tag="$2"
  echo
  echo "==================================================================="
  echo " RUNDE $nr   $(date '+%T')   (+${3}s seit Skriptstart)"
  echo "==================================================================="

  # Die Kennzahl, um die es geht
  local flip=0 warn=0
  if [ -f "$LOGF" ]; then
    flip=$(grep -c 'page-flip is awaiting' "$LOGF" 2>/dev/null || echo 0)
    warn=$(grep -cE '^\s*(WARN|ERR|CRIT)' "$LOGF" 2>/dev/null || echo 0)
  fi
  echo "  [K] Page-Flip-Fehler bisher: $flip    ERR/WARN gesamt: $warn"
  if [ "$nr" -gt 1 ] && [ -n "${PREV_FLIP:-}" ]; then
    if [ "$flip" -eq "$PREV_FLIP" ]; then
      echo "      -> UNVERAENDERT seit der letzten Runde. Ausgabewege haengen nicht."
    else
      echo "      -> +$((flip - PREV_FLIP)) seit der letzten Runde. Es kommen FEHLER dazu."
    fi
  fi
  PREV_FLIP="$flip"

  local mons
  mons=$(hyprctl monitors 2>/dev/null | grep -oE '^Monitor [A-Za-z0-9-]+' | cut -d' ' -f2)
  if [ -z "$mons" ]; then
    echo "  hyprctl liefert keine Monitornamen - grim wird uebersprungen"
    return
  fi

  for m in $mons; do
    local f="$DIR/${tag}_$m.png"
    if ! grim -o "$m" "$f" >/dev/null 2>&1 || [ ! -s "$f" ]; then
      echo "  Monitor $m: Aufnahme FEHLGESCHLAGEN"
      continue
    fi
    echo "  Monitor $m  ->  $(basename "$f")"
    python3 - "$f" <<'PY' 2>&1
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int)
h, w = a.shape[:2]
f = a.reshape(-1, 3)
g = f.mean(axis=1).reshape(h, w)
black = (f.max(axis=1) < 10).mean() * 100
uniq = len(np.unique(f[::11], axis=0))
print("      %dx%d  Mittel %d,%d,%d  schwarz %.1f%%  Farben %d" % (
    w, h, *f.mean(axis=0).astype(int), black, uniq))
row = []
for rx in range(4):
    c = g[0:h//3, rx*w//4:(rx+1)*w//4]
    row.append("%3d" % c.mean())
print("      Helligkeit oben: " + " ".join(row) +
      "   (0 = schwarz, 255 = hell)")
print("      => INHALT" if black < 95 else "      => SCHWARZ")
PY
  done
}

t0=$(date +%s)
runde 1 A "$(( $(date +%s) - t0 ))"
sleep 45
runde 2 B 45

# Der Starter-Test (selftest.sh) oeffnet acht Fenster und stiehlt
# dabei achtmal den Fokus. Das gehoert NICHT in jeden automatischen
# Start - das wuerde beim taeglichen Arbeiten stoeren. Er ist ueber
# die Tastebindung SUPER+UMSCHALT+F1 aufrufbar.

echo
echo "==================================================================="
echo " ENDE $(date '+%T')"
echo "==================================================================="
echo " Starter-Test von Hand:  SUPER+UMSCHALT+F1"
echo "                        Ergebnis in ~/.cache/hypr-selftest.log"
sync