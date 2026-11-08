#!/usr/bin/env bash
################################################################################
# Eigene Ergaenzung -- nicht Teil von Hyprlock-Dots.
# Das uebrige Lockscreen-Setup in diesem Ordner stammt aus
# https://github.com/mahaveergurjar/Hyprlock-Dots (Credit: mahaveergurjar).
################################################################################
################################################################################
# lockbg.sh -- baut den Hintergrund fuer den Lockscreen.
#
# Warum ueberhaupt ein Script?
#
#   1. hyprlock skaliert ein Hintergrundbild, dessen Seitenverhaeltnis nicht zum
#      Schirm passt, bei fraktionaler Skalierung (hier 1.25) unsauber -- es
#      entsteht eine harte Kante mit einem gezoomten, unscharfen Bereich.
#      Liefern wir ein Bild in exakt der Aufloesung des Monitors, ist Cover
#      gleich Contain und es gibt nichts mehr zu skalieren.
#
#   2. hyprlock kann nur den *ganzen* Hintergrund blurren, nicht eine Spalte.
#      Die unscharfe Spalte links (dort stehen Uhr, Avatar, Passwortfeld und
#      das Musik-Widget) wird deshalb hier ins Bild gerechnet -- mit einer
#      Breite, die wir exakt kennen, statt sie einem Renderfehler zu ueberlassen.
#
# Quelle ist immer das aktive Wallpaper der dynamic-island-Shell.
# Aufruf ohne Argumente; Ergebnis landet in $OUT.
################################################################################
set -uo pipefail

WALL_LINK="$HOME/.local/state/dynamic-island/wallpaper/current"
OUT="${XDG_CACHE_HOME:-$HOME/.cache}/hyprlock/background.png"

# Breite der unscharfen Spalte in *logischen* Pixeln (so, wie die Widget-
# Positionen in der Layout-Config gezaehlt werden). Die Widgets von Layout 12
# sitzen um x = Mitte-630; bei 2304 logischer Breite ist das x = 522. Eine
# Spalte von 1044 legt diese Mitte genau in ihre Mitte.
COL_LOGICAL="${LOCKBG_COL:-1044}"

# Weicher Uebergang statt harter Kante, ebenfalls in logischen Pixeln.
FEATHER_LOGICAL="${LOCKBG_FEATHER:-160}"

BLUR="${LOCKBG_BLUR:-0x18}"        # ImageMagick-Sigma
DARKEN="${LOCKBG_DARKEN:-62}"      # Helligkeit der Spalte in % (Text lesbar)

die() { echo "lockbg: $*" >&2; exit 1; }

command -v magick >/dev/null || die "ImageMagick (magick) fehlt"
[ -e "$WALL_LINK" ] || die "kein aktives Wallpaper unter $WALL_LINK"
WALL="$(readlink -f "$WALL_LINK")"
[ -f "$WALL" ] || die "Wallpaper-Ziel existiert nicht: $WALL"

# Aufloesung und Skalierung des Monitors, auf dem gesperrt wird.
read -r PHYS_W PHYS_H SCALE < <(
    hyprctl monitors -j 2>/dev/null | python3 -c '
import json,sys
try:
    mons = json.load(sys.stdin)
except Exception:
    sys.exit(1)
m = next((x for x in mons if x.get("focused")), mons[0] if mons else None)
if not m: sys.exit(1)
print(m["width"], m["height"], m.get("scale", 1))
' 2>/dev/null
) || die "konnte Monitor nicht ermitteln (laeuft Hyprland?)"

[ -n "${PHYS_W:-}" ] || die "keine Monitorgroesse"

# logische -> physische Pixel
COL=$(python3 -c "print(max(1, round($COL_LOGICAL * $SCALE)))")
FEATHER=$(python3 -c "print(max(1, round($FEATHER_LOGICAL * $SCALE)))")
[ "$COL" -ge "$PHYS_W" ] && COL=$((PHYS_W - 1))

mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. Wallpaper exakt auf die Monitoraufloesung bringen (cover + mittig croppen).
magick "$WALL" \
    -resize "${PHYS_W}x${PHYS_H}^" \
    -gravity center -extent "${PHYS_W}x${PHYS_H}" \
    "$TMP/base.png" || die "Skalieren fehlgeschlagen"

# 2. Ganzflaechig unscharf + abgedunkelt als Zwischenbild.
magick "$TMP/base.png" \
    -blur "$BLUR" \
    -modulate "$DARKEN,100,100" \
    "$TMP/blurred.png" || die "Blur fehlgeschlagen"

# 3. Maske: links deckend, dann ueber FEATHER weich auf durchsichtig.
SOLID=$((COL - FEATHER)); [ "$SOLID" -lt 0 ] && SOLID=0
magick -size "${PHYS_W}x${PHYS_H}" xc:black \
    -fill white -draw "rectangle 0,0 ${SOLID},${PHYS_H}" \
    -fill white -draw "rectangle ${SOLID},0 ${COL},${PHYS_H}" \
    "$TMP/mask_hard.png" || die "Maske fehlgeschlagen"

# Weicher Verlauf im Feather-Bereich
magick -size "${FEATHER}x${PHYS_H}" gradient:white-black "$TMP/grad.png"
magick "$TMP/mask_hard.png" \
    -fill black -draw "rectangle ${SOLID},0 ${PHYS_W},${PHYS_H}" \
    "$TMP/mask.png"
magick "$TMP/mask.png" "$TMP/grad.png" -geometry "+${SOLID}+0" -composite "$TMP/mask.png"

# 4. Unscharfe Spalte ueber das scharfe Bild maskieren.
magick "$TMP/base.png" "$TMP/blurred.png" "$TMP/mask.png" \
    -compose over -composite "$OUT" || die "Compositing fehlgeschlagen"

echo "lockbg: $OUT  (${PHYS_W}x${PHYS_H}, Spalte ${COL}px physisch / ${COL_LOGICAL} logisch, Quelle: $(basename "$WALL"))"
