#!/usr/bin/env python3
"""Wallhaven-Suche fuer die Wallpaper-Auswahl (Plugin `wallhaven`).

Eigenstaendig (nur Stdlib, nicht das CLI-Paket), damit das Plugin als .dip
mitwandern kann. Aufruf: python3 -I wallhaven.py search|download|key …

Die Shell ruft das per Process auf und liest NDJSON von stdout:
  search   -> erst {"type": "result", "meta": …, "items": […]}, dann je fertigem
              Thumbnail {"type": "thumb", "id": …, "thumb": PFAD} (parallel geladen,
              die Kacheln koennen also sofort mit Platzhaltern erscheinen)
  fetch    -> {"type": "preview", "id": …, "path": JPG}: Vollbild in den Cache,
              auf Bildschirmbreite verkleinert (Vorschau in voller Qualitaet)
  download -> {"type": "done", "id": …, "path": PFAD} bzw. {"type": "error", …};
              nimmt das Original aus dem fetch-Cache, wenn es schon da ist

Kein Key noetig (SFW/Sketchy). Ein Key fuer NSFW/eigene Filter kommt aus
$WALLHAVEN_API_KEY oder ~/.local/state/dynamic-island/plugins/wallhaven/apikey - nicht
aus shell.json/cli.json, die liegen im Dotfiles-Repo.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from argparse import Namespace
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = "https://wallhaven.cc/api/v1"
UA = "dynamic-island-wallhaven/1.0"
SORTINGS = ("relevance", "date_added", "random", "views", "favorites", "toplist")
TOP_RANGES = ("1d", "3d", "1w", "1M", "3M", "6M", "1y")

home = Path.home()
# Gleiche Orte wie plugin.cachePath()/statePath() und Wallpapers.qml
cache_dir = Path(os.getenv("XDG_CACHE_HOME", home / ".cache")) / "dynamic-island/plugins/wallhaven"
state_dir = Path(os.getenv("XDG_STATE_HOME", home / ".local/state")) / "dynamic-island/plugins/wallhaven"
wallpapers_dir = Path(os.getenv("DYNAMIC_ISLAND_WALLPAPERS_DIR", home / "Pictures/Wallpapers"))

thumbs_dir: Path = cache_dir / "thumbs"
# fetch: Originale + verkleinerte Vorschauen, nach Groesse begrenzt (prune)
full_dir: Path = cache_dir / "full"
preview_dir: Path = cache_dir / "preview"
CACHE_LIMIT = 400 << 20
key_path: Path = state_dir / "apikey"
# Eigener Unterordner: der Scan der Shell findet die Bilder so von selbst
download_dir: Path = wallpapers_dir / "Wallhaven"


def emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def api_key() -> str | None:
    key = os.getenv("WALLHAVEN_API_KEY")
    if not key:
        try:
            key = key_path.read_text().strip()
        except OSError:
            pass
    return key or None


def fetch(url: str, timeout: float = 15) -> bytes:
    # Erst hier: urllib kostet sonst jeden CLI-Aufruf ~20 ms Startzeit
    from urllib.request import Request, urlopen

    headers = {"User-Agent": UA}
    if url.startswith(API) and (key := api_key()):
        headers["X-API-Key"] = key
    with urlopen(Request(url, headers=headers), timeout=timeout) as r:
        return r.read()


def describe(err: Exception) -> str:
    from urllib.error import HTTPError

    if isinstance(err, HTTPError):
        return {
            401: "API-Key ungueltig",
            404: "Nicht gefunden",
            429: "Zu viele Anfragen (max. 45/min) - kurz warten",
        }.get(err.code, f"HTTP {err.code}")
    return str(getattr(err, "reason", err))


def local_path(item_id: str) -> str | None:
    for ext in ("jpg", "png"):
        p = download_dir / f"wallhaven-{item_id}.{ext}"
        if p.exists():
            return str(p)
    return None


def write_atomic(path: Path, data: bytes) -> None:
    # Eigener Name je Prozess: ein abgebrochener fetch und ein neuer duerfen
    # sich nicht die halbe Datei teilen (Reste raeumt prune weg)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.part")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def full_name(item_id: str, url: str) -> str:
    ext = "png" if url.lower().endswith(".png") else "jpg"
    return f"wallhaven-{item_id}.{ext}"


def cached_full(item_id: str) -> Path | None:
    for ext in ("jpg", "png"):
        p = full_dir / f"wallhaven-{item_id}.{ext}"
        if p.exists():
            return p
    return None


def shrink(src: Path, dest: Path, width: int) -> Path:
    """Verkleinert auf `width` (nie vergroessert) als JPEG; ohne vips/magick
    bleibt es beim Original."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(f"{dest.stem}.{os.getpid()}.part.jpg")
    cmds = [
        ["vipsthumbnail", str(src), "--size", f"{width}x>", "-o", f"{tmp}[Q=88,strip]"],
        ["magick", str(src), "-resize", f"{width}x>", "-quality", "88", "-strip", str(tmp)],
    ]
    for cmd in cmds:
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            continue
        if tmp.exists():
            os.replace(tmp, dest)
            return dest
    tmp.unlink(missing_ok=True)
    return src


def prune() -> None:
    """Haelt full/ + preview/ unter CACHE_LIMIT (aelteste zuerst) und raeumt
    Reste abgebrochener Laeufe (*.part, aelter als 10 min) weg."""
    now = time.time()
    files = []
    for d in (full_dir, preview_dir, thumbs_dir):
        if not d.is_dir():
            continue
        for f in d.iterdir():
            try:
                st = f.stat()
            except OSError:
                continue
            if ".part" in f.name:
                if now - st.st_mtime > 600:
                    f.unlink(missing_ok=True)
            elif d is not thumbs_dir:
                files.append((st.st_mtime, st.st_size, f))
    total = sum(size for _, size, _ in files)
    for _, size, f in sorted(files):
        if total <= CACHE_LIMIT:
            break
        f.unlink(missing_ok=True)
        total -= size


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        try:
            if self.args.action == "search":
                self.search()
            elif self.args.action == "fetch":
                self.fetch()
            elif self.args.action == "download":
                self.download()
            elif self.args.action == "key":
                self.set_key()
        except Exception as e:
            emit({"type": "error", "message": describe(e)})
            sys.exit(1)

    def set_key(self) -> None:
        key = (self.args.value or "").strip()
        if key:
            key_path.parent.mkdir(parents=True, exist_ok=True)
            write_atomic(key_path, key.encode())
            key_path.chmod(0o600)
        else:
            key_path.unlink(missing_ok=True)
        emit({"type": "key", "set": bool(key)})

    def search(self) -> None:
        from urllib.parse import urlencode

        a = self.args
        params = {
            "q": a.query or "",
            "categories": a.categories,
            "purity": a.purity,
            "sorting": a.sorting,
            "order": "desc",
            "page": a.page,
        }
        if a.sorting == "toplist":
            params["topRange"] = a.top_range
        if a.sorting == "random" and a.seed:
            params["seed"] = a.seed
        if a.atleast:
            params["atleast"] = a.atleast
        if a.ratios:
            params["ratios"] = a.ratios
        if a.colors:
            params["colors"] = a.colors.lstrip("#")

        res = json.loads(fetch(f"{API}/search?{urlencode(params)}"))
        meta = res.get("meta", {})
        items = []
        todo = []
        for w in res.get("data", []):
            thumb = thumbs_dir / f"{w['id']}.jpg"
            cached = thumb.exists()
            items.append(
                {
                    "id": w["id"],
                    "url": w["url"],
                    "full": w["path"],
                    "thumb": str(thumb) if cached else "",
                    "resolution": w["resolution"],
                    "ratio": w.get("ratio"),
                    "size": w.get("file_size", 0),
                    "fileType": w.get("file_type", ""),
                    "purity": w.get("purity"),
                    "category": w.get("category"),
                    "favorites": w.get("favorites", 0),
                    "views": w.get("views", 0),
                    "colors": w.get("colors", []),
                    "local": local_path(w["id"]),
                }
            )
            if not cached:
                todo.append((w["id"], w["thumbs"]["large"], thumb))

        emit(
            {
                "type": "result",
                "meta": {
                    "page": meta.get("current_page", a.page),
                    "lastPage": meta.get("last_page", 1),
                    "total": meta.get("total", len(items)),
                    "seed": meta.get("seed"),
                },
                "items": items,
            }
        )

        def load(job: tuple[str, str, Path]) -> None:
            item_id, url, path = job
            try:
                write_atomic(path, fetch(url, timeout=10))
                emit({"type": "thumb", "id": item_id, "thumb": str(path)})
            except Exception:
                pass

        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(load, todo))

    def full_url(self) -> str:
        return self.args.url or json.loads(fetch(f"{API}/w/{self.args.id}"))["data"]["path"]

    def fetch(self) -> None:
        item_id = self.args.id
        preview = preview_dir / f"{item_id}-{self.args.width}.jpg"
        if not preview.exists():
            # Schon heruntergeladen: von dort verkleinern statt neu laden
            src = Path(p) if (p := local_path(item_id)) else cached_full(item_id)
            if not src:
                url = self.full_url()
                src = full_dir / full_name(item_id, url)
                write_atomic(src, fetch(url, timeout=120))
            preview = shrink(src, preview, self.args.width)
            prune()
        else:
            preview.touch()
        emit({"type": "preview", "id": item_id, "path": str(preview)})

    def download(self) -> None:
        item_id = self.args.id
        if not (path := local_path(item_id)):
            download_dir.mkdir(parents=True, exist_ok=True)
            if cached := cached_full(item_id):
                # Vom fetch schon da: nur umziehen (gleiches Dateisystem = sofort)
                target = download_dir / cached.name
                tmp = target.with_name(f"{target.name}.{os.getpid()}.part")
                shutil.move(cached, tmp)
                os.replace(tmp, target)
            else:
                url = self.full_url()
                target = download_dir / full_name(item_id, url)
                write_atomic(target, fetch(url, timeout=120))
            path = str(target)

        emit({"type": "done", "id": item_id, "path": path})


def parse_args() -> Namespace:
    parser = argparse.ArgumentParser(prog="wallhaven.py", description="search and download wallpapers from wallhaven.cc")
    cmd = parser.add_subparsers(dest="action", required=True)

    p = cmd.add_parser("search", help="search wallhaven (prints NDJSON)")
    p.add_argument("query", nargs="?", default="", help="search terms (tags, -tag, @user, like:ID, type:png)")
    p.add_argument("-s", "--sorting", choices=SORTINGS, default="relevance")
    p.add_argument("-r", "--top-range", choices=TOP_RANGES, default="1M", help="only for toplist")
    p.add_argument("-c", "--categories", default="111", help="bits general/anime/people, e.g. 110")
    p.add_argument("-u", "--purity", default="100", help="bits sfw/sketchy/nsfw, e.g. 110 (nsfw needs a key)")
    p.add_argument("-a", "--atleast", help="minimum resolution, e.g. 2560x1440")
    p.add_argument("--ratios", help="comma list, e.g. 16x9,21x9")
    p.add_argument("--colors", help="hex colour from the wallhaven palette")
    p.add_argument("-p", "--page", type=int, default=1)
    p.add_argument("--seed", help="seed of the first page for random sorting")

    p = cmd.add_parser("fetch", help="cache the full image and print a screen-sized preview")
    p.add_argument("id", help="wallhaven id, e.g. w533px")
    p.add_argument("--url", help="full image url (skips the lookup)")
    p.add_argument("-w", "--width", type=int, default=2560, help="preview width (never upscaled)")

    p = cmd.add_parser("download", help="download a wallpaper into the Wallhaven folder")
    p.add_argument("id", help="wallhaven id, e.g. w533px")
    p.add_argument("--url", help="full image url (skips the lookup)")

    p = cmd.add_parser("key", help="store the API key (empty removes it)")
    p.add_argument("value", nargs="?", default="")

    return parser.parse_args()


if __name__ == "__main__":
    Command(parse_args()).run()
