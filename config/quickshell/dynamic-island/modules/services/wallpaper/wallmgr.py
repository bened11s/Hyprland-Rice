#!/usr/bin/env python3
"""Wallpaper-Verwaltung fuer das Einstellungs-Fenster (WallManager.qml).

Eigenstaendig, laeuft per `python3 -I`. Jede Operation schreibt genau eine
JSON-Zeile auf stdout: {"ok": true, ...} oder {"ok": false, "error": "..."}.

  looks                         verfuegbare Terminal-Looks (fastfetch)
  folders                       alle Unterordner des Wallpaper-Ordners
  look KEY LOOK                 Terminal-Look fuer ein Bild/einen Ordner
                                festlegen (LOOK "" = Zuordnung entfernen)
  move PATH ORDNER              Bild in einen Unterordner verschieben ("" = oberste Ebene)
  trash PATH                    Bild in den Papierkorb
  mkdir ORDNER                  neuen Unterordner anlegen
  rename-folder ALT NEU         Unterordner umbenennen

Schluessel sind wie in scenes.json relativ zum Wallpaper-Ordner:
"Ordner/bild.jpg" fuer ein Bild, "Ordner/" fuer einen Ordner.

Verschieben/Umbenennen zieht alles mit, was am Pfad haengt: Szenen
(scenes.json), Stil je Bild (variants.json), Terminal-Looks
(terminal-looks.tsv), Vorschaubilder und – ist es das aktuelle Bild – den
Wallpaper-State (path.txt, current).
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
WALLS = Path(os.environ.get("DYNAMIC_ISLAND_WALLPAPERS_DIR") or HOME / "Pictures/Wallpapers")
CONFIG = HOME / ".config/dynamic-island"
STATE = HOME / ".local/state/dynamic-island"
LOOKS_FILE = Path(os.environ.get("DYNAMIC_ISLAND_LOOKS_FILE") or CONFIG / "terminal-looks.tsv")
SCENES_FILE = Path(os.environ.get("DYNAMIC_ISLAND_SCENES_FILE") or CONFIG / "scenes.json")
VARIANTS_FILE = STATE / "wallpaper/variants.json"
PATH_FILE = STATE / "wallpaper/path.txt"
CURRENT_LINK = STATE / "wallpaper/current"
THUMBS = HOME / ".cache/dynamic-island/thumbs"
FASTFETCH = Path(os.environ.get("DYNAMIC_ISLAND_FASTFETCH_DIR") or HOME / ".config/fastfetch")

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".jxl", ".gif"}


class Fail(Exception):
    pass


def out(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def write_atomic(path: Path, text: str, mode: int | None = None):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(text)
    if mode is not None:
        tmp.chmod(mode)
    elif path.exists():
        tmp.chmod(path.stat().st_mode & 0o777)
    tmp.replace(path)


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(WALLS.resolve()).as_posix()
    except ValueError:
        raise Fail(f"liegt nicht im Wallpaper-Ordner: {path}")


def folder_path(name: str) -> Path:
    """Unterordner aus Benutzereingabe – ohne Ausbrechen aus dem Ordner."""
    name = name.strip().strip("/")
    if name == "":
        return WALLS
    parts = name.split("/")
    if any(p in ("", ".", "..") or p.startswith(".") for p in parts):
        raise Fail(f"ungueltiger Ordnername: {name}")
    return WALLS.joinpath(*parts)


# ---- Terminal-Looks ----

def read_looks() -> list[tuple[str, str]]:
    try:
        lines = LOOKS_FILE.read_text().splitlines()
    except FileNotFoundError:
        return []
    pairs = []
    for line in lines:
        if line.startswith("#") or "\t" not in line:
            continue
        key, look = line.split("\t", 1)
        if key and look:
            pairs.append((key, look.strip()))
    return pairs


def write_looks(pairs: list[tuple[str, str]]):
    head = ("# Terminal-Look je Wallpaper (Einstellungen > Wallpaper > Bibliothek).\n"
            "# <Bild oder Ordner/ relativ zu ~/Pictures/Wallpapers>\\t<Look>\n"
            "# Look: scheme | miku | Ordner in ~/.config/fastfetch. Gelesen von\n"
            "# ~/.config/fish/functions/__terminal_look.fish\n")
    body = "".join(f"{k}\t{v}\n" for k, v in sorted(pairs, key=lambda p: p[0].lower()))
    write_atomic(LOOKS_FILE, head + body)


def available_looks() -> list[dict]:
    def card(folder: Path) -> str:
        pics = sorted(folder.glob("*.png"))
        return str(pics[0]) if pics else ""

    looks = [
        {"id": "scheme", "title": "Farbschema", "desc": "Farben des aktuellen Schemas, Karte aus dem Wallpaper",
         "card": "", "cards": 0},
        {"id": "miku", "title": "Vocaloid", "desc": "VOCALOID-NET-HUD",
         "card": card(FASTFETCH / "Pictures/tactical"), "cards": len(list((FASTFETCH / "Pictures/tactical").glob("*.png")))},
    ]
    if FASTFETCH.is_dir():
        for d in sorted(FASTFETCH.iterdir(), key=lambda p: p.name.lower()):
            if d.is_dir() and (d / "config.jsonc").is_file():
                title = " ".join(w.capitalize() for w in d.name.replace("_", "-").split("-"))
                # Titel aus dem Looks-Editor (plugins/terminal/looks.py), falls gesetzt
                try:
                    title = json.loads((d / "look.json").read_text()).get("title") or title
                except (OSError, ValueError, AttributeError):
                    pass
                looks.append({"id": d.name, "title": title, "desc": f"~/.config/fastfetch/{d.name}",
                              "card": card(d / "Pictures"), "cards": len(list((d / "Pictures").glob("*.png")))})
    return looks


def set_look(key: str, look: str):
    key = key.strip()
    if key in ("", "/") or key.startswith("/") or ".." in key.split("/"):
        raise Fail(f"ungueltiger Schluessel: {key}")
    if look and look not in {l["id"] for l in available_looks()}:
        raise Fail(f"unbekannter Look: {look}")
    pairs = [p for p in read_looks() if p[0] != key]
    if look:
        pairs.append((key, look))
    write_looks(pairs)


# ---- Umzug: alles nachziehen, was am Pfad haengt ----

def remap(old_rel: str, new_rel: str, is_dir: bool):
    """Schluessel old_rel -> new_rel (bei Ordnern alles darunter)."""

    def map_rel(key: str) -> str | None:
        if is_dir:
            prefix = old_rel + "/"
            return new_rel + "/" + key[len(prefix):] if key.startswith(prefix) else None
        return new_rel if key == old_rel else None

    # Terminal-Looks
    pairs = read_looks()
    changed = False
    for i, (k, v) in enumerate(pairs):
        nk = map_rel(k)
        if nk is not None:
            pairs[i] = (nk, v)
            changed = True
    if changed:
        write_looks(pairs)

    # Szenen – Reihenfolge der Schluessel bleibt erhalten
    try:
        scenes = json.loads(SCENES_FILE.read_text())
        old = scenes.get("scenes", {})
        new = {}
        changed = False
        for k, v in old.items():
            nk = map_rel(k)
            new[nk if nk is not None else k] = v
            changed |= nk is not None
        if changed:
            scenes["scenes"] = new
            write_atomic(SCENES_FILE, json.dumps(scenes, indent=2, ensure_ascii=False) + "\n")
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    # Stil je Bild (absolute Pfade)
    old_abs, new_abs = str(WALLS / old_rel), str(WALLS / new_rel)
    try:
        variants = json.loads(VARIANTS_FILE.read_text())
        moved = {}
        for k, v in variants.items():
            if is_dir and k.startswith(old_abs + "/"):
                moved[new_abs + k[len(old_abs):]] = v
            elif not is_dir and k == old_abs:
                moved[new_abs] = v
            else:
                moved[k] = v
        if moved != variants:
            write_atomic(VARIANTS_FILE, json.dumps(moved, indent=2, ensure_ascii=False) + "\n")
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    # Vorschaubilder (<rel>.jpg bzw. der ganze Ordner)
    src = THUMBS / (old_rel if is_dir else old_rel + ".jpg")
    dst = THUMBS / (new_rel if is_dir else new_rel + ".jpg")
    if src.exists() and not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        src.rename(dst)

    # Aktuelles Wallpaper
    try:
        current = PATH_FILE.read_text().strip()
    except FileNotFoundError:
        current = ""
    target = None
    if is_dir and current.startswith(old_abs + "/"):
        target = new_abs + current[len(old_abs):]
    elif not is_dir and current == old_abs:
        target = new_abs
    if target:
        write_atomic(PATH_FILE, target + "\n")
        if CURRENT_LINK.is_symlink() or not CURRENT_LINK.exists():
            CURRENT_LINK.unlink(missing_ok=True)
            CURRENT_LINK.symlink_to(target)


def move(path: str, folder: str):
    src = Path(path)
    if not src.is_file():
        raise Fail(f"Datei fehlt: {path}")
    old_rel = rel(src)
    dest_dir = folder_path(folder)
    if not dest_dir.is_dir():
        raise Fail(f"Ordner fehlt: {folder}")
    dst = dest_dir / src.name
    if dst.resolve() == src.resolve():
        return {"path": str(src)}
    if dst.exists():
        raise Fail(f"{src.name} gibt es in {folder or 'der obersten Ebene'} schon")
    shutil.move(str(src), str(dst))
    remap(old_rel, rel(dst), False)
    return {"path": str(dst)}


def trash(path: str):
    src = Path(path)
    if not src.is_file():
        raise Fail(f"Datei fehlt: {path}")
    r = rel(src)
    res = subprocess.run(["gio", "trash", "--", str(src)], capture_output=True, text=True)
    if res.returncode != 0:
        raise Fail(res.stderr.strip() or "gio trash fehlgeschlagen")
    (THUMBS / (r + ".jpg")).unlink(missing_ok=True)
    # Zuordnung des Bilds faellt weg; Szenen bleiben (Papierkorb ist umkehrbar)
    pairs = read_looks()
    if any(k == r for k, _ in pairs):
        write_looks([p for p in pairs if p[0] != r])
    return {"path": str(src)}


def make_folder(name: str):
    d = folder_path(name)
    if d == WALLS:
        raise Fail("Ordnername fehlt")
    if d.exists():
        raise Fail(f"{name} gibt es schon")
    d.mkdir(parents=True)
    return {"folder": rel(d)}


def rename_folder(old: str, new: str):
    src, dst = folder_path(old), folder_path(new)
    if src == WALLS or dst == WALLS:
        raise Fail("Ordnername fehlt")
    if not src.is_dir():
        raise Fail(f"Ordner fehlt: {old}")
    if dst.exists():
        raise Fail(f"{new} gibt es schon")
    old_rel = rel(src)
    # Look nach Ordnernamen (fastfetch/<ordner>) haengt am alten Namen –
    # als feste Zuordnung mitnehmen, sonst ist er nach dem Umbenennen weg
    convention = src.name.lower()
    pairs = read_looks()
    if convention != dst.name.lower() and not any(k == old_rel + "/" for k, _ in pairs):
        if convention == "miku" or (FASTFETCH / convention / "config.jsonc").is_file():
            pairs.append((old_rel + "/", convention))
            write_looks(pairs)
    dst.parent.mkdir(parents=True, exist_ok=True)
    src.rename(dst)
    remap(old_rel, rel(dst), True)
    return {"folder": rel(dst)}


def folders():
    found = []
    for root, dirs, _ in os.walk(WALLS):
        dirs[:] = sorted((d for d in dirs if not d.startswith(".")), key=str.lower)
        for d in dirs:
            found.append((Path(root) / d).relative_to(WALLS).as_posix())
    return sorted(found, key=str.lower)


def main(argv: list[str]):
    if not argv:
        raise Fail("Operation fehlt")
    op, args = argv[0], argv[1:]
    need = {"looks": 0, "folders": 0, "look": 2, "move": 2, "trash": 1, "mkdir": 1, "rename-folder": 2}
    if op not in need:
        raise Fail(f"unbekannte Operation: {op}")
    if len(args) != need[op]:
        raise Fail(f"{op} braucht {need[op]} Argumente")

    if op == "looks":
        return {"looks": available_looks()}
    if op == "folders":
        return {"folders": folders()}
    if op == "look":
        set_look(*args)
        return {}
    if op == "move":
        return move(*args)
    if op == "trash":
        return trash(*args)
    if op == "mkdir":
        return make_folder(*args)
    return rename_folder(*args)


if __name__ == "__main__":
    try:
        out(ok=True, **(main(sys.argv[1:]) or {}))
    except Fail as e:
        out(ok=False, error=str(e))
    except OSError as e:
        out(ok=False, error=f"{e.strerror}: {e.filename}" if e.filename else str(e))
