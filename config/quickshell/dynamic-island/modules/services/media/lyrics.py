#!/usr/bin/env python3
"""Songtext fuer einen Titel von lrclib.net holen, mit Cache.

Aufruf (aus Lyrics.qml):
    lyrics.py <cache-dir> <artist> <title> <album> <dauer-in-s>

Gibt genau eine JSON-Zeile aus:
    {"source": "lrclib", "synced": true, "lines": [{"t": 12340, "text": "..."}]}
    {"source": "lrclib", "synced": false, "lines": [{"t": -1, "text": "..."}]}
    {"none": true}

Ein Ergebnis liegt danach in <cache-dir>/<hash>.json. "Nichts gefunden" wird
auch gemerkt, aber nur eine Woche lang – lrclib waechst.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://lrclib.net/api"
AGENT = "dynamic-island-shell (github.com/Gamecat-HD/Hyprland-Rice)"
NONE_TTL = 7 * 24 * 3600
STAMP = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def get(path: str, params: dict) -> object:
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    try:
        with urllib.request.urlopen(req, timeout=8) as res:
            return json.load(res)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def parse_lrc(text: str) -> list:
    lines = []
    for raw in text.splitlines():
        stamps = STAMP.findall(raw)
        if not stamps:
            continue
        words = STAMP.sub("", raw).strip()
        for m, s in stamps:
            lines.append({"t": round((int(m) * 60 + float(s)) * 1000), "text": words})
    lines.sort(key=lambda l: l["t"])
    return lines


def pack(hit: dict | None) -> dict:
    if not hit or hit.get("instrumental"):
        return {"none": True}
    if hit.get("syncedLyrics"):
        lines = parse_lrc(hit["syncedLyrics"])
        if lines:
            return {"source": "lrclib", "synced": True, "lines": lines}
    if hit.get("plainLyrics"):
        lines = [{"t": -1, "text": l.strip()} for l in hit["plainLyrics"].splitlines()]
        return {"source": "lrclib", "synced": False, "lines": lines}
    return {"none": True}


def lookup(artist: str, title: str, album: str, duration: float) -> dict:
    params = {"artist_name": artist, "track_name": title}
    if album:
        params["album_name"] = album
    if duration > 0:
        params["duration"] = round(duration)
    hit = get("get", params)
    if hit and (hit.get("syncedLyrics") or hit.get("plainLyrics")):
        return pack(hit)

    # Ohne exakten Treffer (anderes Album, Dauer weicht ab): suchen und den
    # Treffer mit passender Dauer nehmen, synchrone Texte bevorzugt
    found = get("search", {"artist_name": artist, "track_name": title}) or []

    def score(h: dict) -> tuple:
        off = abs((h.get("duration") or 0) - duration) if duration > 0 else 0
        return (off > 4, not h.get("syncedLyrics"), off)

    found = [h for h in found if h.get("syncedLyrics") or h.get("plainLyrics")]
    return pack(min(found, key=score) if found else None)


def main() -> None:
    cache_dir, artist, title, album, duration = sys.argv[1:6]
    duration = float(duration or 0)
    key = hashlib.sha1(f"{artist.lower()}\x1f{title.lower()}\x1f{round(duration)}".encode()).hexdigest()
    path = os.path.join(cache_dir, key + ".json")

    try:
        with open(path) as f:
            cached = json.load(f)
        if not cached.get("none") or time.time() - os.path.getmtime(path) < NONE_TTL:
            print(json.dumps(cached))
            return
    except (OSError, ValueError):
        pass

    try:
        result = lookup(artist, title, album, duration)
    except (OSError, ValueError) as e:
        # Netz weg o.ae.: nichts merken, beim naechsten Titel neu versuchen
        print(json.dumps({"none": True, "error": str(e)}))
        return

    os.makedirs(cache_dir, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(result, f)
    os.replace(tmp, path)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
