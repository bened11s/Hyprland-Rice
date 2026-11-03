#!/usr/bin/env python3
"""Screenshot-Helfer fuer modules/services/screenshot/Screenshot.qml.

  freeze <dir>
      Standbild jedes Monitors (grim, PPM) nach <dir>/<monitor>.ppm plus die
      sichtbaren Fenster. Eine JSON-Zeile:
      {"ok", "shots": {name: pfad}, "monitors": [{name,x,y,w,h,scale}],
       "windows": [{x,y,w,h,title,cls,monitor}]}  (obenliegende zuerst,
      Koordinaten global und logisch)

  act <aktion> <standbild> <x> <y> <w> <h> <logische-breite> <logische-hoehe>
      Ausschnitt (logisch, relativ zum Monitor) aus dem Standbild schneiden
      und weiterreichen. Aktionen:
        copy    in die Zwischenablage, Kopie im Cache, Nachricht mit
                "Speichern" / "Bearbeiten"
        save    nach ~/Pictures/Screenshots, ausserdem kopieren
        edit    in swappy oeffnen
        ocr     Text erkennen (tesseract deu+eng) und kopieren
        qr      QR-/Barcodes lesen (zbarimg), ersten Treffer kopieren
      Antwort: {"ok", ...} sofort; Nachrichten mit Knoepfen warten in einem
      abgekoppelten Kindprozess auf die Antwort (notify-send --wait).
"""

import json
import os
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "dynamic-island" / "screenshots"


def pictures_dir() -> Path:
    env = os.environ.get("DYNAMIC_ISLAND_SCREENSHOTS_DIR")
    if env:
        return Path(env)
    try:
        pics = subprocess.run(["xdg-user-dir", "PICTURES"], capture_output=True, text=True).stdout.strip()
    except OSError:
        pics = ""
    return Path(pics or HOME / "Pictures") / "Screenshots"


def out(**data) -> None:
    print(json.dumps({"ok": True, **data}, ensure_ascii=False), flush=True)


def fail(msg: str) -> None:
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False), flush=True)
    sys.exit(0)


def hypr(what: str):
    return json.loads(subprocess.run(["hyprctl", what, "-j"], capture_output=True, text=True, check=True).stdout)


# ---- freeze ----

def op_freeze(args):
    target = Path(args[0])
    target.mkdir(parents=True, exist_ok=True)
    monitors = [m for m in hypr("monitors") if not m.get("disabled")]

    def grab(m):
        path = target / f"{m['name']}.ppm"
        subprocess.run(["grim", "-t", "ppm", "-o", m["name"], str(path)], check=True)
        return m["name"], str(path)

    with ThreadPoolExecutor(max_workers=max(1, len(monitors))) as pool:
        shots = dict(pool.map(grab, monitors))

    visible = {}
    for m in monitors:
        ws = {m["activeWorkspace"]["id"]}
        special = (m.get("specialWorkspace") or {}).get("id", 0)
        if special:
            ws = {special}      # Spezial-Workspace liegt ueber allem
        visible[m["id"]] = (m["name"], ws)

    windows = []
    for c in hypr("clients"):
        mon = visible.get(c.get("monitor"))
        if not mon or not c.get("mapped") or c.get("hidden"):
            continue
        if c["workspace"]["id"] not in mon[1]:
            continue
        windows.append({
            "x": c["at"][0], "y": c["at"][1], "w": c["size"][0], "h": c["size"][1],
            "title": c.get("title", ""), "cls": c.get("class", ""), "monitor": mon[0],
            # Vollbild > schwebend > gekachelt, darin zuletzt fokussiert oben
            "_z": (-(c.get("fullscreen") or 0), not c.get("floating"), c.get("focusHistoryID", 99)),
        })
    windows.sort(key=lambda w: w["_z"])
    for w in windows:
        del w["_z"]

    out(shots=shots, windows=windows, monitors=[
        {"name": m["name"], "x": m["x"], "y": m["y"], "scale": m["scale"],
         "w": round(m["width"] / m["scale"]), "h": round(m["height"] / m["scale"])}
        for m in monitors])


# ---- act ----

def crop(src: str, x: float, y: float, w: float, h: float, lw: float, lh: float):
    from PIL import Image
    img = Image.open(src)
    fx, fy = img.width / lw, img.height / lh       # logisch -> Pixel (Skalierung)
    box = (round(x * fx), round(y * fy), round((x + w) * fx), round((y + h) * fy))
    box = (max(0, box[0]), max(0, box[1]), min(img.width, box[2]), min(img.height, box[3]))
    if box[2] - box[0] < 1 or box[3] - box[1] < 1:
        fail("Leerer Ausschnitt")
    return img.crop(box)


def stamp() -> str:
    return time.strftime("%Y-%m-%d_%H-%M-%S")


def save_png(img, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", compress_level=1)
    return path


def wl_copy_file(path: Path, mime: str = "image/png") -> None:
    with open(path, "rb") as f:
        subprocess.run(["wl-copy", "--type", mime], stdin=f, check=True)


def wl_copy_text(text: str) -> None:
    subprocess.run(["wl-copy"], input=text.encode(), check=True)


def notify_detached(args: list[str], handlers: dict) -> None:
    """notify-send mit Knoepfen. Wartet in einem abgekoppelten Enkelprozess
    auf die Antwort, damit die Shell sofort weitermachen kann."""
    sys.stdout.flush()
    if os.fork() != 0:
        return
    os.setsid()
    if os.fork() != 0:
        os._exit(0)
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    try:
        cmd = ["notify-send", "-a", "dynamic-island", "--wait"]
        cmd += [f"--action={k}={label}" for k, (label, _fn) in handlers.items()]
        res = subprocess.run(cmd + args, capture_output=True, text=True)
        chosen = res.stdout.strip().splitlines()[-1] if res.stdout.strip() else ""
        if chosen in handlers:
            handlers[chosen][1]()
    finally:
        os._exit(0)


def spawn(cmd: list[str]) -> None:
    subprocess.Popen(cmd, start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def tr(de: str, en: str) -> str:
    return en if os.environ.get("DYNAMIC_ISLAND_LANG", "en") == "en" else de


def act_copy(img):
    path = save_png(img, CACHE / f"{stamp()}.png")
    wl_copy_file(path)

    def keep():
        dest = pictures_dir() / f"Screenshot_{path.name}"
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(path, dest)
        spawn(["notify-send", "-a", "dynamic-island", "-i", str(dest),
               "-h", f"string:image-path:{dest}", tr("Screenshot gespeichert", "Screenshot saved"), str(dest)])

    notify_detached(["-i", str(path), "-h", f"string:image-path:{path}",
                     "-h", "boolean:x-dynamic-island-preview:true",
                     tr("Screenshot kopiert", "Screenshot copied"), f"{img.width} × {img.height}"],
                    {"default": ("", lambda: spawn(["swappy", "-f", str(path)])),
                     "save": (tr("Speichern", "Save"), keep),
                     "edit": (tr("Bearbeiten", "Edit"), lambda: spawn(["swappy", "-f", str(path)]))})
    out(path=str(path))


def act_save(img):
    path = save_png(img, pictures_dir() / f"Screenshot_{stamp()}.png")
    wl_copy_file(path)
    folder = str(path.parent)
    notify_detached(["-i", str(path), "-h", f"string:image-path:{path}",
                     "-h", "boolean:x-dynamic-island-preview:true",
                     tr("Screenshot gespeichert", "Screenshot saved"), path.name],
                    {"default": ("", lambda: spawn(["xdg-open", str(path)])),
                     "folder": (tr("Ordner", "Folder"), lambda: spawn(["xdg-open", folder])),
                     "edit": (tr("Bearbeiten", "Edit"), lambda: spawn(["swappy", "-f", str(path)]))})
    out(path=str(path))


def act_edit(img):
    path = save_png(img, CACHE / f"{stamp()}.png")
    spawn(["swappy", "-f", str(path)])
    out(path=str(path))


def ocr_langs() -> str:
    try:
        have = set(subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True)
                   .stdout.split()[1:])
    except OSError:
        fail("tesseract fehlt")
    langs = [lang for lang in ("deu", "eng") if lang in have]
    if not langs:
        fail(tr("Keine OCR-Sprachdaten (tesseract-data-deu/-eng)", "No OCR language data (tesseract-data-deu/-eng)"))
    return "+".join(langs)


def act_ocr(img):
    from PIL import ImageOps
    # Kleine Schrift vergroessern hilft tesseract deutlich; Graustufen reichen
    gray = ImageOps.grayscale(img)
    if gray.height < 400:
        f = min(4, max(2, round(400 / max(1, gray.height))))
        gray = gray.resize((gray.width * f, gray.height * f))
    path = save_png(gray, CACHE / "ocr.png")
    res = subprocess.run(["tesseract", str(path), "-", "-l", ocr_langs(), "--psm", "3"],
                         capture_output=True, text=True)
    path.unlink(missing_ok=True)
    lines = [ln.rstrip() for ln in res.stdout.splitlines()]
    # Mehrfache Leerzeilen zusammenziehen
    text, blank = [], False
    for ln in lines:
        if ln.strip():
            text.append(ln)
            blank = False
        elif not blank and text:
            text.append("")
            blank = True
    text = "\n".join(text).strip()
    if not text:
        spawn(["notify-send", "-a", "dynamic-island", "-i", "edit-find",
               tr("Kein Text erkannt", "No text found"), ""])
        out(text="")
        return
    wl_copy_text(text)
    preview = text if len(text) <= 240 else text[:240] + "…"
    spawn(["notify-send", "-a", "dynamic-island", "-i", "edit-copy",
           tr("Text kopiert", "Text copied"), preview.replace("&", "&amp;").replace("<", "&lt;")])
    out(text=text)


def act_qr(img):
    path = save_png(img, CACHE / "qr.png")
    res = subprocess.run(["zbarimg", "-q", "--raw", str(path)], capture_output=True, text=True)
    path.unlink(missing_ok=True)
    codes = [c for c in res.stdout.splitlines() if c.strip()]
    if not codes:
        spawn(["notify-send", "-a", "dynamic-island", "-i", "edit-find",
               tr("Kein Code gefunden", "No code found"), ""])
        out(codes=[])
        return
    first = codes[0]
    wl_copy_text(first)
    handlers = {}
    if first.startswith(("http://", "https://")):
        handlers["open"] = (tr("Öffnen", "Open"), lambda: spawn(["xdg-open", first]))
    body = first.replace("&", "&amp;").replace("<", "&lt;")
    if len(codes) > 1:
        body += "\n" + tr("+%d weitere", "+%d more") % (len(codes) - 1)
    notify_detached(["-i", "edit-copy", tr("Code kopiert", "Code copied"), body], handlers)
    out(codes=codes)


ACTIONS = {"copy": act_copy, "save": act_save, "edit": act_edit, "ocr": act_ocr, "qr": act_qr}


def op_act(args):
    if len(args) < 8 or args[0] not in ACTIONS:
        fail("act <aktion> <standbild> x y w h lw lh")
    try:
        nums = [float(a) for a in args[2:8]]
    except ValueError:
        fail("Koordinaten ungueltig")
    if not Path(args[1]).is_file():
        fail("Standbild fehlt")
    ACTIONS[args[0]](crop(args[1], *nums))


def main():
    ops = {"freeze": (op_freeze, 1), "act": (op_act, 2)}
    if len(sys.argv) < 2 or sys.argv[1] not in ops:
        fail("unbekannte Operation")
    fn, n = ops[sys.argv[1]]
    if len(sys.argv) - 2 < n:
        fail("zu wenige Argumente")
    try:
        fn(sys.argv[2:])
    except (OSError, ValueError, subprocess.CalledProcessError) as e:
        fail(str(e))


if __name__ == "__main__":
    main()
