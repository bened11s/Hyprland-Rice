#!/usr/bin/env python3
"""Ruhige Bildbereiche eines Wallpapers finden (fuer die Widget-Platzierung).

Aufruf (aus Scenes.qml):
    calm.py <bild> <cache-dir>

Rechnet auf einem kleinen Abzug (am besten dem 480x270-Thumbnail der
Wallpaper-Auswahl) ein 32x18-Raster aus:
    busy  Kantendichte je Zelle, 0..1 (0 = glatte Flaeche, Himmel, Schwarz)
    luma  mittlere Helligkeit je Zelle, 0..1
und gibt es als eine JSON-Zeile aus: {"cols":32,"rows":18,"busy":[...],"luma":[...]}
(zeilenweise, oben links zuerst). Die eigentliche Platzsuche macht Scenes.qml,
sie kennt die Groessen der Widgets.

Ergebnis wird nach Pfad+Groesse+mtime gecacht.
"""

import hashlib
import json
import os
import sys

from PIL import Image, ImageFilter, ImageOps

COLS, ROWS = 32, 18


def analyse(path: str) -> dict:
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("L")
        # Wie das Wallpaper auf 16:9 zugeschnitten wird (fill + Mitte)
        im = ImageOps.fit(im, (320, 180), Image.Resampling.BILINEAR)

    edges = im.filter(ImageFilter.FIND_EDGES)
    # Feine Texturen (Rauschen, Sterne) zaehlen weniger als echte Kanten
    edges = edges.point(lambda v: 0 if v < 12 else min(255, v * 2))
    busy = edges.resize((COLS, ROWS), Image.Resampling.BOX)
    luma = im.resize((COLS, ROWS), Image.Resampling.BOX)

    b = [v / 255 for v in busy.tobytes()]
    peak = max(b) or 1
    return {
        "cols": COLS,
        "rows": ROWS,
        "busy": [round(min(1.0, v / peak), 3) for v in b],
        "luma": [round(v / 255, 3) for v in luma.tobytes()],
    }


def main() -> None:
    path, cache_dir = sys.argv[1], sys.argv[2]
    st = os.stat(path)
    key = hashlib.sha1(f"{path}\x1f{st.st_size}\x1f{int(st.st_mtime)}".encode()).hexdigest()
    cache = os.path.join(cache_dir, key + ".json")
    try:
        with open(cache) as f:
            print(f.read().strip())
            return
    except OSError:
        pass

    result = json.dumps(analyse(path))
    os.makedirs(cache_dir, exist_ok=True)
    with open(cache + ".tmp", "w") as f:
        f.write(result)
    os.replace(cache + ".tmp", cache)
    print(result)


if __name__ == "__main__":
    main()
