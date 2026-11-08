#!/usr/bin/env bash
# Vorschaubilder fuer das Wallpaper-Karussell (siehe Wallpapers.qml).
#
#   thumbs.sh <wallpaper-ordner> <thumb-ordner>
#
# Legt je Bild <thumb-ordner>/<relativer pfad>.jpg an (480x270, mittig auf
# 16:9 zugeschnitten - genau der Ausschnitt, den ein 16:9-Monitor zeigt) und
# gibt fuer jedes Bild, dessen Vorschau bereitsteht, den relativen Pfad aus:
# vorhandene sofort, neue, sobald sie fertig sind. Erneuert wird nur, was
# fehlt oder aelter als das Original ist.
#
# Warum ueberhaupt: Qt dekodiert alle Bilder der Shell in EINEM Thread. Das
# Karussell lud vorher die Originale (bis 7500x5000, 40 MB PNG) und staute
# damit alles dahinter - vor allem den Hintergrund, der dann sekundenlang auf
# dem alten Bild haengen blieb.

walls=${1:?Wallpaper-Ordner fehlt}
thumbs=${2:?Thumb-Ordner fehlt}
cd "$walls" || exit 1

export thumbs
export VIPS_CONCURRENCY=1   # parallel laufen mehrere Prozesse, nicht Threads

make_thumb() {
    local rel=$1 out="$thumbs/$1.jpg"
    local tmp="$out.tmp.jpg"
    mkdir -p "${out%/*}"
    # vips liest JPEGs verkleinert und PNGs zeilenweise - auch riesige Bilder
    # brauchen so kaum Speicher. magick faengt ab, was vips nicht kennt.
    if vipsthumbnail "$rel" --size 480x270 --smartcrop centre -o "$tmp[Q=85,strip]" 2>/dev/null \
        || magick "$rel[0]" -thumbnail 480x270^ -gravity center -extent 480x270 -quality 85 "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$out" && printf '%s\n' "$rel"
    else
        rm -f "$tmp"
    fi
}
export -f make_thumb

# Erst alles melden, was schon da ist (das Karussell zeigt es sofort), dann
# die fehlenden parallel und mit niedriger Prioritaet nachziehen
missing=()
while IFS= read -r -d '' rel; do
    if [[ -s "$thumbs/$rel.jpg" && "$thumbs/$rel.jpg" -nt "$rel" ]]; then
        printf '%s\n' "$rel"
    else
        missing+=("$rel")
    fi
done < <(find . -type f -not -path '*/.*' \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.jxl' -o -iname '*.gif' \) \
    -printf '%P\0')

((${#missing[@]})) || exit 0
printf '%s\0' "${missing[@]}" | nice -n 10 xargs -0 -P 4 -I{} bash -c 'make_thumb "$1"' _ {}
