#!/usr/bin/env python3
"""Vergleichstest von `dynamic-island scheme` und `wallpaper`, nur fuer die Sandbox.

Aufruf: colours_scenarios.py <protokoll> <befehl>

Protokolliert Ausgaben, Exit-Code, alle Aufrufe von dconf, sudo, killall und Co.,
Anfragen an einen nachgebauten Hyprland-Socket, die Sequenzen an ein Terminal,
welche Dateien neu geschrieben wurden und deren Inhalt, Byte fuer Byte.
"""

import fcntl
import hashlib
import json
import os
import pty
import random
import re
import select
import shutil
import socket
import stat
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import assert_sandbox

HOME = Path(os.environ["HOME"])
CLI_ROOT = Path("/tmp/cli")
STUBS = Path("/tmp/stubs")
CALLS = Path("/tmp/aufrufe.log")
IMAGES = Path("/tmp/bilder")
RUNTIME = Path(os.environ["XDG_RUNTIME_DIR"])
SIG = "testsignatur"
FIXED_TIME = 1700000000
LOG: list[str] = []
ENV = {
    **{k: v for k, v in os.environ.items() if not k.startswith("XDG_") or k == "XDG_RUNTIME_DIR"},
    "PATH": f"{STUBS}:/usr/bin",
    "DYNAMIC_ISLAND_PYTHON_CLI": str(CLI_ROOT / "bin/dynamic-island"),
    "HYPRLAND_INSTANCE_SIGNATURE": SIG,
}
CONFIG = HOME / ".config/dynamic-island/cli.json"
STATE = HOME / ".local/state/dynamic-island"
SCHEME = STATE / "scheme.json"

STUB = r"""#!/bin/sh
n="$(basename "$0")"
if [ "$n" = sudo ] && [ "$2" = tee ]; then echo "sudo $* <- $(cat)" >> /tmp/aufrufe.log; exit 0; fi
echo "$n $*" >> /tmp/aufrufe.log
if [ "$n" = sudo ] && [ "$2" = mkdir ]; then shift 1; shift 1; mkdir "$@"; fi
if [ "$n" = notify-send ]; then echo 7; fi
if [ -e "/tmp/scheitert-$n" ]; then exit 1; fi
exit 0
"""


class FakeHyprland(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.provider = "lua"
        self.alive = True
        self.requests = []
        (RUNTIME / f"hypr/{SIG}").mkdir(parents=True, exist_ok=True)
        path = RUNTIME / f"hypr/{SIG}/.socket.sock"
        path.unlink(missing_ok=True)
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(str(path))
        self.server.listen(8)

    def run(self):
        while True:
            conn, _ = self.server.accept()
            with conn:
                msg = conn.recv(4096).decode()
                self.requests.append(msg)
                if not self.alive:
                    continue
                if msg == "j/status":
                    conn.sendall(json.dumps({"configProvider": self.provider, "version": "x"}).encode())
                elif msg == "j/monitors":
                    conn.sendall(json.dumps([{"width": 1920, "height": 1080}, {"width": 1000, "height": 800}]).encode())


def setup():
    STUBS.mkdir(exist_ok=True)
    for name in ("dconf", "killall", "sudo", "notify-send", "papirus-folders", "chromium", "brave", "google-chrome-stable"):
        (STUBS / name).write_text(STUB)
        (STUBS / name).chmod(0o755)
    (CLI_ROOT / "bin").mkdir(parents=True, exist_ok=True)
    ignore = shutil.ignore_patterns("__pycache__", "dynamic-island-rs")
    shutil.copytree("/tmp/work/dynamic-island/bin", CLI_ROOT / "bin", dirs_exist_ok=True, ignore=ignore)
    shutil.copytree("/tmp/work/dynamic-island/src", CLI_ROOT / "src", dirs_exist_ok=True, ignore=ignore)
    make_images()
    craft_schemes()


def make_images():
    from PIL import Image
    IMAGES.mkdir(exist_ok=True)

    def image(name, build, size=(300, 200), mode="RGB", **save):
        im = Image.new(mode, size)
        px = im.load()
        for y in range(size[1]):
            for x in range(size[0]):
                px[x, y] = build(x, y)
        im.save(IMAGES / name, **save)

    image("verlauf.png", lambda x, y: (x * 255 // 300, y * 255 // 200, 128))
    image("dunkel.jpg", lambda x, y: (x % 40, y % 30, 60), (640, 480), quality=90)
    image("hell.webp", lambda x, y: (240, 230 - x % 30, 200 + y % 40))
    image("bunt.tif", lambda x, y: ((x // 30) * 40 % 256, (y // 20) * 70 % 256, (x + y) // 2 % 256))
    image("grau.jpeg", lambda x, y: ((x + y) % 256,) * 3, (200, 200))
    # Gross genug fuer den Hash-Index und den Groessenfilter, mit Rauschen
    im = Image.frombytes("RGB", (1800, 1200), os.urandom(0) or bytes((i * 7919) % 251 for i in range(1800 * 1200 * 3)))
    im.save(IMAGES / "gross.png")
    frames = [Image.new("RGB", (120, 80), (i * 60, 10, 200 - i * 60)) for i in range(3)]
    frames[0].save(IMAGES / "bewegt.gif", save_all=True, append_images=frames[1:], duration=50)
    (IMAGES / "kaputt.png").write_text("kein bild")
    (IMAGES / "notiz.txt").write_text("text")
    (IMAGES / "GROSS.PNG").write_bytes((IMAGES / "verlauf.png").read_bytes())
    for path in IMAGES.iterdir():
        os.utime(path, (FIXED_TIME, FIXED_TIME))


PRIMARIES = ["000000", "101010", "555555", "565656", "a9a9a9", "aaaaaa", "ffffff", "ff0000", "b00000", "00ff00", "0000ff", "ffff00", "ff00ff", "00ffff",
             "8080ff", "90a0ff", "a080ff", "80a0ff", "c8c8ff", "d2c8ff", "c8d2ff", "6070ff", "7060ff", "ff8000", "b08000", "c0a000", "ffd080", "e0b880", "d0b090",
             "ffc0c0", "ffb0d0", "d090a0", "e0c0a0", "c04090", "ff60a0", "80ff80", "a0ff00", "60c040", "c0e0a0", "e0e0a0", "12ab34", "ab1234", "3412ab", "bada55",
             "c0ffee", "decade", "facade", "beefed", "dead00", "00dead", "ba0bab", "11f0a0", "a01f10", "fe0102", "0102fe", "02fe01", "e0d0c0", "c0d0e0", "d0e0c0", "abcdef"]


# Dazu Zufallsfarben, damit jeder Zweig der Entscheidung vorkommt
_rng = random.Random(1106)
PRIMARIES += [f"{_rng.randrange(1 << 24):06x}" for _ in range(240)]
# Blau dominant und R, G nah dran: Hier liegen die Grenzen bei 60 und 70 Prozent
PRIMARIES += [f"{r:02x}{g:02x}{b:02x}" for b in (200, 255) for r in range(100, 240, 28) for g in range(100, 240, 28) if r < b and g < b]
PRIMARIES += [f"{r:02x}{g:02x}c8" for r in range(116, 150, 6) for g in range(134, 158, 6)]
PRIMARIES += [f"{g:02x}{r:02x}c8" for r in range(116, 150, 6) for g in range(134, 158, 6)]


def craft_schemes():
    for i, primary in enumerate(PRIMARIES):
        path = CLI_ROOT / f"src/dynamic_island/data/schemes/zz-test/c{i}/dark.txt"
        path.parent.mkdir(parents=True, exist_ok=True)
        keep = (CLI_ROOT / "src/dynamic_island/data/schemes/catppuccin/mocha/dark.txt").read_text().splitlines()
        lines = [f"primary {primary}" if line.startswith("primary ") else line for line in keep]
        path.write_text("\n".join(lines) + "\n")


WARNING = "\x1b[33m:: Warning: failed to parse config, invalid JSON\x1b[0m\n"


def normalise(text: str) -> str:
    text = text.replace(str(HOME), "HOME")
    # Python warnt doppelt: Beim Import von shell.py liest es die Datei schon einmal
    text = text.replace(WARNING + WARNING, WARNING)
    return re.sub(r'(exception during "\w+\(\)"): [^\x1b]*', r"\1: <text>", text)


def fresh():
    for child in list(HOME.iterdir()):
        shutil.rmtree(child) if child.is_dir() and not child.is_symlink() else child.unlink()
    for f in Path("/tmp").glob("scheitert-*"):
        f.unlink()


def write_config(theme=None, **rest):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    base = {k: False for k in ("enableTerm", "enableHypr", "enableHyprlock", "enableGtk", "enableQt", "enableBtop", "enableCava", "enableDiscord", "enableFuzzel", "enableChromium", "enableSpicetify", "enableZed", "enableHtop", "enableNvtop", "enablePandora", "enableWarp")}
    base.update(theme or {})
    CONFIG.write_text(json.dumps({"theme": base, **rest}))


class Runner:
    def __init__(self, cli):
        self.cli = cli
        self.master, self.slave = pty.openpty()
        self.seen = {}
        self.hypr = FakeHyprland()
        self.hypr.start()

    def stat_all(self):
        out = {}
        for path in HOME.rglob("*"):
            st = path.lstat()
            out[path] = (st.st_ino, st.st_mtime_ns)
        return out

    def run(self, *args, env=None, tree=True, code_only=False, cwd=None):
        LOG.append("$ " + " ".join(args))
        before = self.stat_all()
        full = {**ENV, **(env or {})}
        res = subprocess.run(self.cli + list(args), capture_output=True, text=True, env=full, cwd=cwd or HOME, stdin=subprocess.DEVNULL, timeout=120)
        LOG.append(f"  exit {res.returncode}")
        if not code_only:
            if res.stdout:
                LOG.append("  out: " + normalise(res.stdout).rstrip("\n").replace("\n", "\n       "))
            if res.stderr and res.returncode == 0:
                LOG.append("  err: " + normalise(res.stderr).rstrip("\n").replace("\n", "\n       "))
        self.after(before, tree)
        return res

    def after(self, before, tree):
        lines = CALLS.read_text().rstrip("\n").split("\n") if CALLS.exists() else []
        # papirus-folders startet im Hintergrund: abwarten und ans Ende stellen
        if any("icon-theme" in line for line in lines):
            end = time.monotonic() + 0.3
            while time.monotonic() < end and not any("papirus-folders" in line for line in lines):
                time.sleep(0.005)
                lines = CALLS.read_text().rstrip("\n").split("\n")
        lines = [l for l in lines if "papirus-folders" not in l] + [l for l in lines if "papirus-folders" in l]
        if CALLS.exists():
            for line in lines:
                LOG.append("  [" + normalise(line) + "]")
            CALLS.unlink()
        if self.hypr.requests:
            LOG.append(f"  [hyprland {self.hypr.requests}]")
            self.hypr.requests.clear()
        data = b""
        while select.select([self.master], [], [], 0)[0]:
            data += os.read(self.master, 65536)
        if data:
            LOG.append(f"  [terminal {len(data)} Bytes {hashlib.sha256(data).hexdigest()[:16]}]")
        if not tree:
            return
        after = self.stat_all()
        changed = [p for p, v in after.items() if before.get(p) != v and not p.is_dir()]
        for path in sorted(changed):
            rel = path.relative_to(HOME)
            st = path.lstat()
            if path.is_symlink():
                LOG.append(f"  neu {rel} -> {normalise(os.readlink(path))}")
            elif rel.name == "hashes.json":
                data = json.loads(path.read_text())
                LOG.append(f"  neu {rel} {oct(stat.S_IMODE(st.st_mode))} {sorted((normalise(k), v[0], v[2]) for k, v in data.items())}")
            else:
                LOG.append(f"  neu {rel} {oct(stat.S_IMODE(st.st_mode))} {hashlib.sha256(path.read_bytes()).hexdigest()[:16]} {st.st_size}")
        for path in sorted(set(before) - set(after)):
            LOG.append(f"  weg {path.relative_to(HOME)}")


def scenario_scheme(r):
    LOG.append("=== scheme ohne Zustand")
    fresh()
    write_config()
    r.run("scheme", "get")
    r.run("scheme", "get", "-n", "-f", "-m", "-v")
    r.run("scheme", "get", "-v")
    for flags in (["-n"], ["-f"], ["-m"], ["-v"], ["-n", "-m"], ["-n", "-f", "-m", "-v"]):
        r.run("scheme", "list", *flags)
    r.run("scheme", "list")
    r.run("scheme", "set")
    LOG.append("=== scheme set")
    r.run("scheme", "set", "-n", "gruvbox")
    r.run("scheme", "get", "-n", "-f", "-m", "-v")
    r.run("scheme", "set", "-n", "gruvbox")
    r.run("scheme", "set", "-n", "catppuccin", "-f", "latte", "-m", "light")
    r.run("scheme", "get", "-n", "-f", "-m", "-v")
    r.run("scheme", "set", "-m", "dark")
    r.run("scheme", "set", "--flavour", "gibtsnicht")
    r.run("scheme", "set", "--flavour", "gibtsnicht", "--notify")
    r.run("scheme", "set", "-f", "mocha", "-m", "dark", "-v", "vibrant")
    r.run("scheme", "set", "-v", "vibrant")
    r.run("scheme", "set", "-n", "gibtsnicht")
    r.run("scheme", "set", "-m", "lila")
    r.run("scheme", "set", "-v", "lila")
    r.run("scheme", "set", "-n", "dynamic")
    r.run("scheme", "set", "-n", "dynamic", "--notify")
    r.run("scheme", "list", "-f", "-m")
    LOG.append("# Zufall: Das Ergebnis passt zusammen (bei dynamic ohne Wallpaper bricht es sauber ab)")
    for _ in range(12):
        res = subprocess.run(r.cli + ["scheme", "set", "-r"], capture_output=True, env=ENV, cwd=HOME, stdin=subprocess.DEVNULL)
        data = json.loads(SCHEME.read_text())
        path = CLI_ROOT / "src/dynamic_island/data/schemes" / data["name"] / data["flavour"] / f"{data['mode']}.txt"
        fits = data["name"] != "dynamic" and path.is_file() and data["colours"]["primary"] in path.read_text()
        if not fits:
            LOG.append(f"  !! passt nicht: {data['name']} {data['flavour']} {data['mode']} exit {res.returncode}")
    r.after({}, False)
    LOG.append("=== kaputter Zustand")
    SCHEME.write_text("{kaputt")
    r.run("scheme", "get", "-n")
    SCHEME.write_text('{"name": "catppuccin"}')
    r.run("scheme", "get", "-n", code_only=True)
    SCHEME.write_text(json.dumps({"name": "catppuccin", "flavour": "mocha", "mode": "dark", "variant": "tonalspot", "colours": {"primary": "abcdef"}}))
    write_config({"enableTerm": True})
    r.run("scheme", "set", "-v", "neutral", code_only=True)
    write_config()


WALLS = ["verlauf.png", "dunkel.jpg", "hell.webp", "bunt.tif", "grau.jpeg", "gross.png", "bewegt.gif"]


def scenario_wallpaper(r):
    LOG.append("=== wallpaper")
    fresh()
    write_config({"enableHypr": True, "enableGtk": True, "enableQt": True, "enableBtop": True, "enableCava": True, "enableHyprlock": True, "enableSpicetify": True, "enableTerm": True})
    r.run("wallpaper")
    r.run("wallpaper", "-p")
    r.run("scheme", "set", "-n", "dynamic")
    r.run("wallpaper", "-f", str(IMAGES / "notiz.txt"), code_only=True)
    r.run("wallpaper", "-f", str(IMAGES / "gibtsnicht.png"), code_only=True)
    r.run("wallpaper", "-f", str(IMAGES / "GROSS.PNG"), code_only=True)
    r.run("wallpaper", "-f", str(IMAGES / "kaputt.png"), code_only=True)
    r.run("wallpaper", "-p", str(IMAGES / "kaputt.png"), code_only=True)
    r.run("wallpaper", "-p", str(IMAGES / "gibtsnicht.png"), code_only=True)
    for name in WALLS:
        path = str(IMAGES / name)
        LOG.append(f"# {name}")
        r.run("wallpaper", "-p", path)
        r.run("wallpaper", "-p", path)
        r.run("wallpaper", "-p", path, "-N")
    for name in WALLS:
        path = str(IMAGES / name)
        LOG.append(f"# setzen: {name}")
        r.run("wallpaper", "-f", path)
        r.run("wallpaper")
        r.run("wallpaper", "-p")
        r.run("scheme", "get", "-n", "-f", "-m", "-v")
        r.run("wallpaper", "-f", path)
        r.run("wallpaper", "-f", path, "-N")
    LOG.append("# Relativer Pfad und Symlink")
    (HOME / "link.png").symlink_to(IMAGES / "verlauf.png")
    r.run("wallpaper", "-f", "link.png")
    r.run("wallpaper", "-f", "./link.png", "-v", "vibrant")
    r.run("wallpaper", "-p", "link.png")
    LOG.append("# Stile")
    path = str(IMAGES / "dunkel.jpg")
    r.run("wallpaper", "-f", path)
    for variant in ("tonalspot", "vibrant", "expressive", "fidelity", "fruitsalad", "monochrome", "neutral", "rainbow", "content"):
        r.run("wallpaper", "-v", variant)
        r.run("scheme", "set", "-m", "light")
        r.run("scheme", "set", "-m", "dark")
        r.run("scheme", "set", "-f", "hard")
        r.run("scheme", "set", "-f", "default")
    r.run("wallpaper", "-v", "auto")
    r.run("wallpaper", "-v", "rainbow", "--for", str(IMAGES / "hell.webp"))
    r.run("wallpaper", "-p", str(IMAGES / "hell.webp"))
    r.run("wallpaper", "-v", "auto", "--for", str(IMAGES / "hell.webp"))
    r.run("wallpaper", "-f", str(IMAGES / "bunt.tif"), "-v", "expressive")
    r.run("wallpaper", "-f", str(IMAGES / "bunt.tif"), "-v", "auto")
    r.run("wallpaper", "-f", str(IMAGES / "bunt.tif"), "-v", "neutral", "-N")
    r.run("scheme", "set", "-v", "content")
    r.run("scheme", "list")
    r.run("wallpaper", "-v", "lila")
    LOG.append("# festes Schema: das Bild aendert nichts an den Farben")
    r.run("scheme", "set", "-n", "nord")
    r.run("wallpaper", "-f", str(IMAGES / "verlauf.png"))
    r.run("wallpaper", "-v", "vibrant")
    r.run("scheme", "set", "-v", "fidelity")
    r.run("wallpaper", "-p", str(IMAGES / "verlauf.png"))
    LOG.append("# veralteter Cache")
    r.run("scheme", "set", "-n", "dynamic")
    for smart in HOME.rglob("smart.json"):
        data = json.loads(smart.read_text())
        data["version"] = 1
        smart.write_text(json.dumps(data))
    r.run("wallpaper", "-p", str(IMAGES / "verlauf.png"))
    for score in HOME.rglob("dark.json"):
        score.write_text("{kaputt")
    r.run("wallpaper", "-p", str(IMAGES / "verlauf.png"))


def scenario_random(r):
    LOG.append("=== wallpaper -r")
    fresh()
    write_config()
    d = HOME / "w"
    (d / "tief").mkdir(parents=True)
    shutil.copy2(IMAGES / "verlauf.png", d / "a.png")
    r.run("wallpaper", "-r", str(d), "-n")
    r.run("wallpaper")
    LOG.append("# nur das aktuelle Bild: Fehler")
    r.run("wallpaper", "-r", str(d), "-n", code_only=True)
    shutil.copy2(IMAGES / "dunkel.jpg", d / "tief/b.jpg")
    (d / "c.txt").write_text("x")
    r.run("wallpaper", "-r", str(d), "-n")
    r.run("wallpaper")
    r.run("wallpaper", "-r", str(d), "-n", "-N")
    r.run("wallpaper")
    r.run("wallpaper", "-r", str(HOME / "gibtsnicht"), "-n", code_only=True)
    LOG.append("# Groessenfilter: kleinster Monitor 1000x800, Faktor 0.8")
    shutil.copy2(IMAGES / "gross.png", d / "gross.png")
    os.utime(d / "gross.png", (FIXED_TIME, FIXED_TIME))
    (HOME / ".local/state/dynamic-island/wallpaper/path.txt").write_text("/gibtsnicht")
    (d / "a.png").unlink()
    (d / "tief/b.jpg").unlink()
    r.run("wallpaper", "-r", str(d))
    r.run("wallpaper")
    (d / "gross.png").unlink()
    shutil.copy2(IMAGES / "verlauf.png", d / "klein.png")
    r.run("wallpaper", "-r", str(d), code_only=True)
    r.hypr.alive = False
    r.run("wallpaper", "-r", str(d), code_only=True)
    r.hypr.alive = True
    r.run("wallpaper", "-r", str(d), "-t", "0.1", code_only=True)
    LOG.append("# Standardordner")
    pics = HOME / "Pictures/Wallpapers"
    pics.mkdir(parents=True)
    shutil.copy2(IMAGES / "hell.webp", pics / "h.webp")
    r.run("wallpaper", "-r", "-n")
    r.run("wallpaper")
    other = HOME / "anders"
    other.mkdir()
    shutil.copy2(IMAGES / "grau.jpeg", other / "g.jpeg")
    r.run("wallpaper", "-r", "-n", env={"DYNAMIC_ISLAND_WALLPAPERS_DIR": str(other)})
    r.run("wallpaper")
    (HOME / "bilder/Wallpapers").mkdir(parents=True)
    shutil.copy2(IMAGES / "bunt.tif", HOME / "bilder/Wallpapers/b.tif")
    r.run("wallpaper", "-r", "-n", env={"XDG_PICTURES_DIR": str(HOME / "bilder")})
    r.run("wallpaper")


def scenario_theme(r):
    LOG.append("=== alle Apps an")
    fresh()
    everything = {k: True for k in ("enableTerm", "enableHypr", "enableHyprlock", "enableGtk", "enableQt", "enableBtop", "enableCava", "enableDiscord", "enableFuzzel", "enableChromium", "enableSpicetify", "enableZed", "enableHtop", "enableNvtop", "enablePandora", "enableWarp")}
    hook = 'echo "$SCHEME_NAME $SCHEME_FLAVOUR $SCHEME_MODE $SCHEME_VARIANT $SCHEME_COLOURS $WALLPAPER_PATH $THUMBNAIL_PATH" >> "$HOME/hook.log"; echo laut; echo fehler >&2'
    # Ohne Chromium: Python puffert print() in einer Pipe, die Hook-Ausgabe kaeme sonst davor
    write_config({**everything, "enableChromium": False, "postHook": hook, "iconTheme": "Mein-Thema"}, wallpaper={"postHook": 'echo "W $WALLPAPER_PATH $THUMBNAIL_PATH $SCHEME_NAME" >> "$HOME/hook.log"'})
    r.run("scheme", "set", "-n", "catppuccin", "-f", "mocha", "-m", "dark")
    r.run("scheme", "set", "-m", "light", "-f", "latte")
    r.run("scheme", "set", "-m", "light", "-f", "latte")
    r.run("scheme", "set", "-v", "vibrant")
    r.run("wallpaper", "-f", str(IMAGES / "verlauf.png"))
    r.run("scheme", "set", "-n", "dynamic")
    r.run("wallpaper", "-f", str(IMAGES / "dunkel.jpg"))
    LOG.append("# Icons je Modus, Zed als Symlink")
    write_config({**everything, "iconThemeDark": "Dunkel", "iconThemeLight": "Hell", "iconTheme": "Egal"})
    zed = HOME / ".config/zed/themes/dynamic-island.json"
    zed.parent.mkdir(parents=True, exist_ok=True)
    zed.unlink(missing_ok=True)
    zed.symlink_to(HOME / "ziel.json")
    r.run("scheme", "set", "-n", "nord", "-m", "dark")
    r.run("scheme", "set", "-n", "catppuccin", "-f", "latte", "-m", "light")
    LOG.append("# Hyprland: Lua, klassisch, nicht erreichbar")
    write_config({"enableHypr": True})
    r.hypr.provider = "hyprlang"
    r.run("scheme", "set", "-n", "nord", "-m", "dark")
    r.hypr.alive = False
    r.run("scheme", "set", "-n", "gruvbox")
    r.hypr.alive = True
    r.hypr.provider = "lua"
    r.run("scheme", "set", "-n", "nord")
    LOG.append("# einzelne Programme scheitern, der Rest laeuft weiter")
    write_config({**everything})
    Path("/tmp/scheitert-dconf").touch()
    Path("/tmp/scheitert-killall").touch()
    r.run("scheme", "set", "-n", "gruvbox")
    Path("/tmp/scheitert-dconf").unlink()
    Path("/tmp/scheitert-killall").unlink()
    shutil.rmtree(HOME / ".config/Equicord", ignore_errors=True)
    (HOME / ".config/Equicord").write_text("Datei statt Ordner")
    r.run("scheme", "set", "-n", "catppuccin")
    (HOME / ".config/Equicord").unlink()
    LOG.append("# kaputte cli.json")
    CONFIG.write_text("{kaputt")
    r.run("scheme", "set", "-n", "gruvbox")
    CONFIG.unlink()
    r.run("scheme", "set", "-n", "nord")
    LOG.append("# eigene Vorlagen")
    write_config()
    templates = CONFIG.parent / "templates"
    templates.mkdir()
    (templates / "formen.txt").write_text(
        "{{ primary.hex }}|{{primary.hexalpha}}|{{ primary.rgb }}|{{ primary.rgbalpha }}|{{ primary.ansi }}\n"
        "{{ mode }}|{{mode}}|{{  mode\n  }}|{{ gibtsnicht.hex }}|{{ primary.quatsch }}|{{ primary }}|{{ a.b.c }}|{{ }}|{{}}|{\n"
        "{{{ primary.hex }}}|{{ primary.hex {{ primary.hex }}|{{ primary.hex\n}}|} }|ä{{ primary.hex }}ö|{{ $primary }}\n{{"
    )
    (templates / "zweite.conf").write_text("x = {{ surface.hex }}\n")
    (templates / "unterordner").mkdir()
    r.run("scheme", "set", "-n", "gruvbox")
    r.run("scheme", "set", "-n", "gruvbox", "-f", "medium", code_only=True)
    LOG.append("# auf den Lock warten")
    write_config({"enableBtop": True})
    (STATE).mkdir(parents=True, exist_ok=True)
    with open(STATE / "theme.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        proc = subprocess.Popen(r.cli + ["scheme", "set", "-n", "nord"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=HOME)
        time.sleep(0.5)
        LOG.append(f"  wartet: {proc.poll() is None}")
        fcntl.flock(lock, fcntl.LOCK_UN)
    LOG.append(f"  exit {proc.wait(20)}")
    r.run("scheme", "get", "-n")
    LOG.append("# Der neueste Stand auf der Platte gewinnt nach dem Warten")
    with open(STATE / "theme.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        proc = subprocess.Popen(r.cli + ["scheme", "set", "-n", "catppuccin", "-f", "mocha"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=HOME)
        time.sleep(0.5)
        data = json.loads(SCHEME.read_text())
        data["colours"]["primary"] = "123456"
        SCHEME.write_text(json.dumps(data))
        fcntl.flock(lock, fcntl.LOCK_UN)
    proc.wait(20)
    r.run("scheme", "get", "-n")


def scenario_papirus(r):
    LOG.append("=== Ordnerfarbe aus der Hauptfarbe")
    fresh()
    write_config({"enableGtk": True})
    for i, primary in enumerate(PRIMARIES):
        LOG.append(f"# {primary}")
        r.run("scheme", "set", "-n", "zz-test", "-f", f"c{i}", "-m", "dark", tree=False)
    LOG.append("# ohne Papirus-Ordner und ohne papirus-folders")
    (STUBS / "papirus-folders").unlink()
    r.run("scheme", "set", "-n", "nord", tree=False)
    (STUBS / "papirus-folders").write_text(STUB)
    (STUBS / "papirus-folders").chmod(0o755)


def scenario_all_schemes(r):
    LOG.append("=== alle mitgelieferten Schemata")
    fresh()
    write_config({"enableHypr": True, "enableHyprlock": True, "enableGtk": True, "enableQt": True, "enableBtop": True, "enableCava": True, "enableSpicetify": True, "enableTerm": True, "enableFuzzel": True, "enableNvtop": True, "enableHtop": True, "enablePandora": True, "enableWarp": True, "enableZed": True, "enableDiscord": True})
    root = CLI_ROOT / "src/dynamic_island/data/schemes"
    for name in sorted(p.name for p in root.iterdir() if p.is_dir() and p.name != "zz-test"):
        for flavour in sorted(p.name for p in (root / name).iterdir() if p.is_dir()):
            for mode in sorted(p.stem for p in (root / name / flavour).iterdir() if p.is_file()):
                r.run("scheme", "set", "-n", name, "-f", flavour, "-m", mode)


def scenario_real_wallpapers(r):
    LOG.append("=== deine echten Wallpaper (nur lesend)")
    real = Path("/tmp/wall-echt")
    if not real.is_dir():
        LOG.append("# nicht eingehaengt")
        return
    fresh()
    write_config({"enableHypr": True, "enableGtk": True, "enableQt": True})
    r.run("scheme", "set", "-n", "dynamic", code_only=True, tree=False)
    walls = sorted(p for p in real.rglob("*") if p.is_file() and p.suffix in (".jpg", ".jpeg", ".png", ".webp", ".gif"))
    step = max(1, len(walls) // 25)
    for wall in walls[::step]:
        LOG.append(f"# {wall.name}")
        r.run("wallpaper", "-p", str(wall))
        r.run("wallpaper", "-f", str(wall))
    r.run("scheme", "list")


SCENARIOS = [scenario_scheme, scenario_wallpaper, scenario_random, scenario_theme, scenario_papirus, scenario_all_schemes, scenario_real_wallpapers]


def main():
    assert_sandbox()
    setup()
    out, cli = sys.argv[1], [sys.argv[2]]
    runner = Runner(cli)
    only = os.environ.get("COMPARE_ONLY")
    for scenario in SCENARIOS:
        if not only or only in scenario.__name__:
            scenario(runner)
    with open(out, "w") as f:
        f.write("\n".join(LOG) + "\n")


if __name__ == "__main__":
    main()
