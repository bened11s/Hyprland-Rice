#!/usr/bin/env python3
"""Zwischenablage-Verlauf fuer modules/services/clipboard/Clipboard.qml.

Jede Operation schreibt genau eine JSON-Zeile auf stdout ({"ok": ...}).

  list                  Verlauf (cliphist list) + angeheftete Eintraege
  thumbs <id>...        Bild-Eintraege als verkleinerte PNGs in den Cache
  full <id>             ganzer Text eines Eintrags (gekappt)
  copy <id>             Eintrag zurueck in die Zwischenablage
  delete <id>           Eintrag aus dem Verlauf loeschen
  wipe                  ganzen Verlauf loeschen (Angeheftetes bleibt)
  pin <id>              Eintrag anheften bzw. wieder loesen
  copy-pin <key>        angehefteten Eintrag kopieren
  unpin <key>           angehefteten Eintrag loesen

Angeheftetes liegt als eigene Kopie in ~/.local/state/dynamic-island/clipboard
(pins.json + Dateien), unabhaengig von cliphist: es ueberlebt "wipe" und das
Verdraengen alter Eintraege, und die cliphist-IDs (die sich beim erneuten
Kopieren aendern) spielen keine Rolle.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("DYNAMIC_ISLAND_CLIP_CACHE")
             or Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "dynamic-island" / "clipboard")
STATE = Path(os.environ.get("DYNAMIC_ISLAND_CLIP_STATE")
             or Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "dynamic-island" / "clipboard")
PINS_FILE = STATE / "pins.json"

FULL_LIMIT = 20000          # Zeichen fuer "full"
THUMB_EDGE = 640            # laengste Kante der Vorschaubilder
BINARY = re.compile(r"^\[\[ binary data (?P<size>.+?) (?P<fmt>\w+) (?P<w>\d+)x(?P<h>\d+) \]\]$")


def out(**data) -> None:
    print(json.dumps({"ok": True, **data}, ensure_ascii=False))


def fail(msg: str) -> None:
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(0)


def cliphist(*args: str, data: bytes | None = None) -> bytes:
    res = subprocess.run(["cliphist", *args], input=data, capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.decode(errors="replace").strip() or f"cliphist {args[0]} gescheitert")
    return res.stdout


def history() -> list[tuple[str, str]]:
    """[(id, Vorschau)] neueste zuerst."""
    lines = cliphist("list").decode(errors="replace").splitlines()
    rows = []
    for line in lines:
        cid, _, preview = line.partition("\t")
        if cid.isdigit():
            rows.append((cid, preview))
    return rows


def line_for(cid: str) -> str | None:
    for line in cliphist("list").decode(errors="replace").splitlines():
        if line.split("\t", 1)[0] == cid:
            return line
    return None


def decode(cid: str) -> bytes:
    if not cid.isdigit():
        raise ValueError("ungueltige ID")
    return cliphist("decode", cid)


def describe(cid: str, preview: str) -> dict:
    m = BINARY.match(preview)
    if m:
        return {"id": cid, "kind": "image", "text": "", "fmt": m["fmt"], "size": m["size"],
                "w": int(m["w"]), "h": int(m["h"])}
    return {"id": cid, "kind": "text", "text": preview}


def thumb_path(cid: str) -> Path:
    return CACHE / f"{cid}.png"


def make_thumb(cid: str) -> str | None:
    dest = thumb_path(cid)
    if dest.exists():
        return str(dest)
    try:
        data = decode(cid)
        from io import BytesIO
        from PIL import Image
        img = Image.open(BytesIO(data))
        img.thumbnail((THUMB_EDGE, THUMB_EDGE))
        CACHE.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(".part")
        img.save(tmp, "PNG")
        tmp.replace(dest)
        return str(dest)
    except Exception:
        return None


# ---- Angeheftetes ----

def load_pins() -> list[dict]:
    try:
        pins = json.loads(PINS_FILE.read_text())
        return pins if isinstance(pins, list) else []
    except (OSError, ValueError):
        return []


def save_pins(pins: list[dict]) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = PINS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(pins, ensure_ascii=False, indent=1))
    tmp.replace(PINS_FILE)


def pin_file(pin: dict) -> Path:
    return STATE / pin["file"]


def public_pin(pin: dict) -> dict:
    p = {k: pin[k] for k in ("key", "kind", "text", "added") if k in pin}
    if pin["kind"] == "image":
        p["path"] = str(pin_file(pin))
    return p


def wl_copy(data: bytes) -> None:
    # wl-copy geht selbst in den Hintergrund und bedient die Ablage weiter
    subprocess.run(["wl-copy"], input=data, check=True)


# ---- Operationen ----

def op_list(_args):
    pins = load_pins()
    pinned = {(p["kind"], p.get("match", "")) for p in pins}
    entries = []
    ids = set()
    for cid, preview in history():
        e = describe(cid, preview)
        e["pinned"] = (e["kind"], preview) in pinned
        if e["kind"] == "image" and thumb_path(cid).exists():
            e["thumb"] = str(thumb_path(cid))
        entries.append(e)
        ids.add(cid)
    # Vorschaubilder verschwundener Eintraege aufraeumen
    if CACHE.is_dir():
        for f in CACHE.glob("*.png"):
            if f.stem not in ids:
                f.unlink(missing_ok=True)
    out(entries=entries, pins=[public_pin(p) for p in pins])


def op_thumbs(args):
    ids = [a for a in args if a.isdigit()]
    with ThreadPoolExecutor(max_workers=6) as pool:
        paths = dict(zip(ids, pool.map(make_thumb, ids)))
    out(thumbs={k: v for k, v in paths.items() if v})


def op_full(args):
    text = decode(args[0]).decode(errors="replace")
    out(id=args[0], text=text[:FULL_LIMIT], truncated=len(text) > FULL_LIMIT)


def op_copy(args):
    wl_copy(decode(args[0]))
    out(id=args[0])


def op_delete(args):
    line = line_for(args[0])
    if line is None:
        fail("Eintrag nicht mehr im Verlauf")
    cliphist("delete", data=(line + "\n").encode())
    thumb_path(args[0]).unlink(missing_ok=True)
    out(id=args[0])


def op_wipe(_args):
    cliphist("wipe")
    if CACHE.is_dir():
        for f in CACHE.glob("*.png"):
            f.unlink(missing_ok=True)
    out()


def op_pin(args):
    cid = args[0]
    line = line_for(cid)
    if line is None:
        fail("Eintrag nicht mehr im Verlauf")
    preview = line.split("\t", 1)[1] if "\t" in line else ""
    info = describe(cid, preview)
    pins = load_pins()
    for p in pins:
        if p["kind"] == info["kind"] and p.get("match") == preview:
            pin_file(p).unlink(missing_ok=True)
            save_pins([q for q in pins if q is not p])
            out(pinned=False, key=p["key"])
            return
    data = decode(cid)
    key = hashlib.sha1(data).hexdigest()[:16]
    if any(p["key"] == key for p in pins):
        out(pinned=True, key=key)
        return
    ext = info.get("fmt", "png") if info["kind"] == "image" else "txt"
    pin = {"key": key, "kind": info["kind"], "match": preview, "file": f"{key}.{ext}",
           "text": "" if info["kind"] == "image" else data.decode(errors="replace")[:400],
           "added": int(time.time())}
    STATE.mkdir(parents=True, exist_ok=True)
    pin_file(pin).write_bytes(data)
    save_pins([pin] + pins)
    out(pinned=True, key=key)


def find_pin(key: str) -> tuple[list[dict], dict]:
    pins = load_pins()
    for p in pins:
        if p["key"] == key:
            return pins, p
    fail("Angehefteter Eintrag fehlt")


def op_copy_pin(args):
    _pins, pin = find_pin(args[0])
    wl_copy(pin_file(pin).read_bytes())
    out(key=pin["key"])


def op_unpin(args):
    pins, pin = find_pin(args[0])
    pin_file(pin).unlink(missing_ok=True)
    save_pins([p for p in pins if p is not pin])
    out(key=pin["key"])


OPS = {
    "list": (op_list, 0), "thumbs": (op_thumbs, 0), "full": (op_full, 1),
    "copy": (op_copy, 1), "delete": (op_delete, 1), "wipe": (op_wipe, 0),
    "pin": (op_pin, 1), "copy-pin": (op_copy_pin, 1), "unpin": (op_unpin, 1),
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in OPS:
        fail("unbekannte Operation")
    fn, nargs = OPS[sys.argv[1]]
    args = sys.argv[2:]
    if len(args) < nargs:
        fail("zu wenige Argumente")
    try:
        fn(args)
    except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as e:
        fail(str(e))


if __name__ == "__main__":
    main()
