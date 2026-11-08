#!/usr/bin/env python3
"""Eigene Systemklaenge fuer modules/services/sounds/Sounds.qml.

Eine JSON-Zeile je Aufruf ({"ok": ...}).

  list                 {"custom": {name: pfad}} – welche Klaenge ersetzt sind
  pick                 Dateiauswahl (kdialog, sonst zenity) -> {"path": ""|pfad}
  import <name> <pfad> Datei pruefen und als <name>.wav ablegen (ffmpeg:
                       48 kHz mono, hoechstens 5 s, laengere blenden aus)
  reset <name>         eigenen Klang loeschen (dann gilt wieder der eingebaute)

Ablage: ~/.config/dynamic-island/sounds/<name>.wav (DYNAMIC_ISLAND_SOUNDS_DIR).
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

NAMES = ("message", "shutter", "plug", "unplug", "lock", "unlock", "connect", "disconnect")
MAX_SEC = 5.0
FADE = 0.3
DIR = Path(os.environ.get("DYNAMIC_ISLAND_SOUNDS_DIR")
           or Path.home() / ".config" / "dynamic-island" / "sounds")


def out(**data) -> None:
    print(json.dumps({"ok": True, **data}, ensure_ascii=False), flush=True)


def fail(msg: str) -> None:
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False), flush=True)
    sys.exit(0)


def op_list(_args):
    custom = {}
    for name in NAMES:
        p = DIR / f"{name}.wav"
        if p.is_file():
            custom[name] = str(p)
    out(custom=custom)


def op_pick(_args):
    start = str(Path.home())
    filters = "*.wav *.ogg *.oga *.flac *.mp3 *.opus *.m4a"
    if shutil.which("kdialog"):
        cmd = ["kdialog", "--title", "Klang wählen", "--getopenfilename", start, f"Audio ({filters})"]
    elif shutil.which("zenity"):
        cmd = ["zenity", "--file-selection", "--title=Klang wählen", f"--file-filter=Audio | {filters}"]
    else:
        fail("Kein Dateidialog (kdialog oder zenity)")
    res = subprocess.run(cmd, capture_output=True, text=True)
    out(path=res.stdout.strip() if res.returncode == 0 else "")


def duration(path: str) -> float:
    res = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        return float(res.stdout.strip())
    except ValueError:
        fail("Keine lesbare Audiodatei")


def op_import(args):
    name, src = args[0], args[1]
    if name not in NAMES:
        fail("Unbekannter Klang")
    if src.startswith("file://"):
        from urllib.parse import unquote
        src = unquote(src[7:])
    if not Path(src).is_file():
        fail("Datei nicht gefunden")
    dur = duration(src)
    if dur <= 0:
        fail("Keine lesbare Audiodatei")
    af = ["-af", f"afade=t=out:st={MAX_SEC - FADE}:d={FADE}"] if dur > MAX_SEC else []
    DIR.mkdir(parents=True, exist_ok=True)
    dest = DIR / f"{name}.wav"
    tmp = DIR / f".{name}.tmp.wav"
    res = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-vn", "-t", str(MAX_SEC), *af,
                          "-ac", "1", "-ar", "48000", "-c:a", "pcm_s16le", str(tmp)],
                         capture_output=True, text=True)
    if res.returncode != 0 or not tmp.is_file():
        tmp.unlink(missing_ok=True)
        fail("Umwandeln gescheitert: " + (res.stderr.strip().splitlines() or ["ffmpeg"])[-1])
    tmp.replace(dest)
    out(name=name, path=str(dest), trimmed=dur > MAX_SEC)


def op_reset(args):
    if args[0] not in NAMES:
        fail("Unbekannter Klang")
    (DIR / f"{args[0]}.wav").unlink(missing_ok=True)
    out(name=args[0])


OPS = {"list": (op_list, 0), "pick": (op_pick, 0), "import": (op_import, 2), "reset": (op_reset, 1)}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in OPS:
        fail("unbekannte Operation")
    fn, n = OPS[sys.argv[1]]
    if len(sys.argv) - 2 < n:
        fail("zu wenige Argumente")
    try:
        fn(sys.argv[2:])
    except OSError as e:
        fail(str(e))


if __name__ == "__main__":
    main()
