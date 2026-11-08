#!/usr/bin/env bash
################################################################################
# Eigene Ergaenzung -- nicht Teil von Hyprlock-Dots.
# Das uebrige Lockscreen-Setup in diesem Ordner stammt aus
# https://github.com/mahaveergurjar/Hyprlock-Dots (Credit: mahaveergurjar).
################################################################################
# Sperrt den Bildschirm mit Layout 12 und baut vorher den Hintergrund neu,
# damit immer das gerade aktive Wallpaper drunterliegt.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/lockbg.sh" || echo "lock: Hintergrund konnte nicht gebaut werden, nehme den alten" >&2
exec hyprlock -c "$DIR/../layout12.conf" --grace 1 "$@"
