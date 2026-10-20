#!/bin/bash
# ====================================================================
#  selftest.sh - Sichtpruefung fuer die Hyprland-Oberflaeche
#  Erstellt: 04.10.2026, Nox
#
#  WARUM ES DIESES SKRIPT GIBT
#  ---------------------------
#  Ich habe am 04.10. gemeldet, Hyprland sei "voll funktionsfaehig",
#  weil alle Prozesse liefen, alle vier Monitore da waren und
#  "hyprctl configerrors" leer blieb. Das war falsch.
#
#  Rofi lief. Die Prozessliste war sauber. configerrors war leer.
#  Und der Starter war trotzdem kaputt - aus Gruenden, die erst am
#  06.10. sichtbar wurden (Nox):
#
#    1) Superallein war an "rofi -show menu" gebunden. "menu" ist in
#       rofi 2.0 KEIN Modus -> rofi zeigte einen Fehlerdialog:
#       "Mode menu is not found." Statt Programmliste.
#    2) Die Konfiguration verwies in mainbox auf ein Widget "listbox",
#       das es nicht gibt (richtig heisst es "listview") -> rofi blieb
#       bei der Eingabeleiste stehen, null Apps.
#
#  Die alte Behauptung hier, rofi habe "7 bis 10 Sekunden" gebraucht,
#  hielt keiner Messung stand: nach der Korrektur sind es 0,54
#  Sekunden bis die Liste steht - mit ausgeschaltetem Cache.
#
#  Prozesse und Logs beweisen, dass etwas LAEUFT.
#  Nur ein Pixelvergleich beweist, dass man etwas SIEHT.
#  Diese Pruefung gehoert deshalb ab jetzt bei jeder Aenderung dazu.
#
#  WIE
#  ---
#  grim nimmt den Bildschirm als PNG auf. KWin kann das nicht
#  (kein wlr-screencopy-Protokoll), Hyprland schon - deshalb laeuft
#  diese Pruefung ausschliesslich unter Hyprland.
#
#  Pro Test: Referenzbild ohne Programm -> Programm starten ->
#  in Halbsekunden-Abstaenden aufnehmen, bis sich etwas aendert ->
#  zaehlen, wie viele Pixel sich geaendert haben und ab wann.
#
#  Ergebnis landet in ~/.cache/hypr-selftest.log
#  Start:  ~/.config/hypr/hypr/selftest.sh
# ====================================================================

LOG="$HOME/.cache/hypr-selftest.log"
D=/tmp/opencode
WALL="$HOME/.local/share/wallpapers/Tokyo-Night/Tokyo-Night.jpg"

mkdir -p "$HOME/.cache" "$D"
: > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }

MON=$(hyprctl monitors 2>/dev/null | grep 'focused: yes' | grep -oE '^Monitor [A-Za-z0-9-]+' | cut -d' ' -f2)
[ -z "$MON" ] && MON=$(hyprctl monitors 2>/dev/null | grep -oE '^Monitor [A-Za-z0-9-]+' | head -1 | cut -d' ' -f2)

say "=== Selbsttest $(date '+%F %T') ==="
say "Monitor: ${MON:-UNBEKANNT}"
say ""

# Wie viele Pixel unterscheiden sich? Gibt die Hoehe des gezeichneten
# Rechtecks aus (0 = nichts gezeichnet).
pixel() {
  python3 - "$D/st-base.png" "$D/st-cur.png" <<'PY' 2>/dev/null || echo 0
import sys
from PIL import Image
import numpy as np
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int)
b = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(int)
if a.shape != b.shape:
    print(0); raise SystemExit
ys, xs = np.where(np.abs(a - b).sum(axis=2) > 12)
print(0 if len(ys) == 0 else ys.max() - ys.min() + 1)
PY
}

# $1 = Befehl, $2 = Zielhoehe in px (0 = "irgendetwas ueber 20px")
teste() {
  local name="$1" befehl="$2" ziel="${3:-0}"
  pkill -x rofi 2>/dev/null; pkill -x wofi 2>/dev/null
  pkill -x swaybg 2>/dev/null; sleep 1

  grim -o "$MON" "$D/st-base.png" 2>/dev/null
  if [ ! -s "$D/st-base.png" ]; then
    say "  $name"
    say "      ERGEBNIS=abbruch   grim liefert kein Bild"
    say "      (laeuft das unter Hyprland? WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-leer})"
    return
  fi

  hyprctl dispatch exec "$befehl" >/dev/null 2>&1
  local t0 t1 h=0 i
  t0=$(date +%s%N)
  for i in $(seq 1 30); do
    sleep 0.5
    grim -o "$MON" "$D/st-cur.png" 2>/dev/null
    h=$(pixel)
    if [ "$ziel" -eq 0 ] && [ "$h" -gt 20 ]; then break; fi
    if [ "$ziel" -gt 0 ] && [ "$h" -ge "$ziel" ]; then break; fi
  done
  t1=$(date +%s%N)
  local ms=$(( (t1 - t0) / 1000000 ))

  say "  $name"
  if [ "$h" -gt 20 ] 2>/dev/null; then
    say "      ERGEBNIS=sichtbar    gezeichnet ${h}px hoch, nach ${ms}ms"
  else
    say "      ERGEBNIS=UNSICHTBAR  0 Pixel geaendert, ${ms}ms gewartet"
  fi
}

say "### Grundlagen"
teste "Hintergrundbild (swaybg)" "swaybg -i $WALL -m fill"

# WICHTIG, 04.10.2026: frueher stand hier eine Zeile, die eine zweite
# Quickshell-Leiste gestartet hat:
#     teste "Statusleiste (Quickshell)" "qs -c .../tokyonight"
# Das ergibt ZWEI Leisten uebereinander - Quickshell ist kein
# Einzelgaenger, der eine zweite Instanz verhindert. Der Test hat
# damit mehr kaputt gemacht, als er pruefen sollte. Ersetzt durch
# eine blosse Prozess-Abfrage: die Leiste darf nicht doppelt laufen.
say "  Statusleiste (Quickshell)"
say "      Instanzen: $(pgrep -xc qs 2>/dev/null || echo 0)  $([ "$(pgrep -xc qs 2>/dev/null || echo 0)" -le 1 ] && echo '(genau eine - gut)' || echo '(ZU VIELE - Fehler)')"

say ""
say "### Starter  -  hier lag der gemeldete Fehler (nicht 7-10s, sondern LEER)"
teste "rofi PROGRAMME  (Super)"        "rofi -show drun"   400
teste "rofi PROGRAMME  (Super+Leer)"  "rofi -show drun"   400
teste "rofi FENSTER    (Super+Shift)" "rofi -show window" 200
teste "rofi AUSFUEHREN (Super+Strg)"  "rofi -show run"    100

say ""
say "### Rechtsklick und Desktop (paketabhaengig)"
teste "wofi PROGRAMME (Rechtsklick)" "wofi --show drun" 300
teste "pcmanfm Desktop-Symbole"  "pcmanfm-qt --desktop --set-pe-name=hyprland"

# Aufraeumen. 04.10.2026, Nox: pcmanfm-qt stand hier nicht auf der
# Liste und blieb nach dem Test als Desktop-Symbole-Ebene liegen.
# Ein Test, der seine eigene Hinterlassenschaft nicht abraeumt,
# gehoert nicht in diese Datei.
pkill -x rofi       2>/dev/null
pkill -x wofi       2>/dev/null
pkill -x pcmanfm-qt 2>/dev/null
pkill -x swaybg     2>/dev/null
# Hintergrundbild wieder aufsetzen - der Test hat es beendet.
[ -f "$WALL" ] && (setsid swaybg -i "$WALL" -m fill >/dev/null 2>&1 &)
sleep 1

say ""
say "=== Ende $(date '+%T') ==="
say ""
say "ZUSAMMENFASSUNG"
if grep -q 'ERGEBNIS=UNSICHTBAR' "$LOG"; then
  say "  mindestens ein Test UNSICHTBAR - siehe oben"
else
  say "  alle Tests sichtbar"
fi
if grep -q 'ERGEBNIS=abbruch' "$LOG"; then
  say "  Pruefung abgebrochen - grim kam nicht durch"
fi
say ""
say "Pakete (nur mit sudo installierbar):"
for p in wofi pcmanfm-qt; do
  command -v "$p" >/dev/null 2>&1 && say "  $p  vorhanden" || say "  $p  FEHLT"
done
