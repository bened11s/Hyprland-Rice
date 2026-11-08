#!/usr/bin/env python3
"""Vergleichstest der Terminal-Looks, nur fuer die Sandbox.

Aufruf: looks_scenarios.py <protokoll> <befehl...>

Protokolliert jede JSON-Antwort, den Dateibaum und alles, was bei fastfetch und
gio ankommt. Erzeugte Dateien werden ueber ihren sha256 verglichen, also Byte fuer
Byte. Fastfetch und gio sind Attrappen, nur der letzte Teil nutzt das echte fastfetch.
"""

import hashlib
import json
import os
import random
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import assert_sandbox

HOME = Path(os.environ["HOME"])
FF = HOME / "ff"
STATE_DIR = HOME / "state"
STUBS = Path("/tmp/stubs")
CALLS = Path("/tmp/aufrufe.log")
REAL = Path("/tmp/ff-echt")
LOG: list[str] = []
ENV = {**os.environ, "DYNAMIC_ISLAND_FASTFETCH_DIR": str(FF), "DYNAMIC_ISLAND_STATE_DIR": str(STATE_DIR),
       "PATH": f"{STUBS}:/usr/bin"}

STUB_FASTFETCH = r"""#!/usr/bin/env python3
import json, os, re, sys
cfg = sys.argv[sys.argv.index("-c") + 1]
raw = open(cfg, encoding="utf-8").read()
with open("/tmp/aufrufe.log", "a") as f:
    f.write("fastfetch %s COLUMNS=%s endung=%s\n" % (" ".join(a for a in sys.argv[1:] if a != cfg), os.environ.get("COLUMNS"), cfg[-6:]))
    f.write("  config " + raw + "\n")
mode = open("/tmp/ff-modus").read().strip() if os.path.exists("/tmp/ff-modus") else ""
if mode == "fehler":
    sys.stderr.write("erste Zeile\nletzte Zeile  \n")
    sys.exit(3)
if mode == "fehler-still":
    sys.exit(3)
if mode == "fehler-mit-ausgabe":
    print("trotzdem")
    sys.exit(3)
if mode == "haengt":
    import time
    time.sleep(40)
if mode == "kaputt":
    sys.stdout.buffer.write(b"\xff\xfe\n")
    sys.exit(0)
if mode.startswith("datei:"):
    sys.stdout.buffer.write(open(mode[6:], "rb").read())
    sys.exit(0)
conf = json.loads(raw)
for m in conf.get("modules", []):
    print(m if isinstance(m, str) else m.get("format", m.get("type", "?")))
"""

STUB_GIO = r"""#!/bin/sh
echo "gio $*" | sed "s#$HOME#HOME#g" >> /tmp/aufrufe.log
if [ -e /tmp/gio-scheitert ]; then echo "  Papierkorb voll  " >&2; exit 1; fi
rm -rf "$2"
"""


def setup_stubs():
    STUBS.mkdir(exist_ok=True)
    (STUBS / "fastfetch").write_text(STUB_FASTFETCH)
    (STUBS / "gio").write_text(STUB_GIO)
    for f in STUBS.iterdir():
        f.chmod(0o755)


def normalise(text: str) -> str:
    text = text.replace(str(HOME), "HOME")
    # Texte der Parser und Ausnahmen sind je Sprache anders, die Shell zeigt sie nur an
    text = re.sub(r"(look\.json kaputt): [^\"]*", r"\1: <text>", text)
    text = re.sub(r"(kein gueltiges JSONC) \([^\"]*\)", r"\1 (<text>)", text)
    text = re.sub(r"(Eingabe ist kein JSON): [^\"]*", r"\1: <text>", text)
    text = re.sub(r'"error": "(\w*(Error|Exception|Ausnahme)\w*|Ausnahme): [^\n]*"\}', '"error": "<Ausnahme>"}', text)
    return text


def drain_calls():
    if CALLS.exists():
        text = CALLS.read_text().replace("\r", "")
        CALLS.unlink()
        for line in text.rstrip("\n").split("\n"):
            LOG.append("  [" + normalise(line) + "]")


def run(cli, *args, stdin_text=None, tree=False):
    shown = " ".join(a if len(a) < 90 else a[:60] + f"…({hashlib.sha256(a.encode()).hexdigest()[:8]})" for a in args)
    LOG.append(f"$ {shown}")
    res = subprocess.run(cli + list(args), capture_output=True, env=ENV, cwd=HOME, timeout=60,
                         input=stdin_text.encode() if stdin_text is not None else b"")
    out = res.stdout.decode()
    LOG.append(f"  exit {res.returncode} {normalise(out).rstrip()}")
    drain_calls()
    if tree:
        snapshot()
    try:
        return json.loads(out)
    except ValueError:
        return {}


def snapshot(root=None):
    root = root or FF
    LOG.append("  [baum]")
    if not root.exists():
        return
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root)
        st = path.lstat()
        mode = oct(stat.S_IMODE(st.st_mode))
        if path.is_dir():
            LOG.append(f"    {rel}/ {mode}")
        elif path.suffix == ".png" and st.st_size:
            from PIL import Image
            with Image.open(path) as im:
                # Im PNG steht die Uhrzeit, darum die Bildpunkte vergleichen
                LOG.append(f"    {rel} {mode} {im.size} {im.mode} {hashlib.sha256(im.tobytes()).hexdigest()[:16]}")
        else:
            LOG.append(f"    {rel} {mode} {hashlib.sha256(path.read_bytes()).hexdigest()[:16]} {st.st_size}")


def write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def fresh():
    shutil.rmtree(FF, ignore_errors=True)
    shutil.rmtree(STATE_DIR, ignore_errors=True)
    FF.mkdir()
    for f in ("/tmp/ff-modus", "/tmp/gio-scheitert"):
        if os.path.exists(f):
            os.unlink(f)


E = "\u001b"
CONFIG = """// Kommentar mit "Anfuehrungszeichen"
{
    /* Block
       ueber Zeilen */
    "$schema": "x",
    "logo": {"type": "kitty", "source": "a.png"},
    "display": {
        "separator": " ",
        "color": {"keys": "1;38;2;10;20;30", "separator": "38;2;40;50;60", "title": "38;2;10;20;30"},
        "bar": {"color": {"elapsed": "38;2;1;2;3", "total": "48;2;9;9;9"}, "width": 10},
        "percent": {"color": {"green": "32"}},
        "zahl": 1.0, "exp": 1e5, "klein": 1e-7, "an": true, "nichts": null, "liste": [1, 2.5, "x", [],],
    },
    "modules": [
        "title",
        "break",
        {"type": "custom", "format": "\\u001b[1;38;2;10;20;30mKopf \\u001b[0m<tag> ä 日本語 // kein Kommentar"},
        {"type": "custom", "format": "=== Abschnitt \\u001b[38;2;200;100;50mfarbe\\u001b[0m"},
        {"type": "custom", "format": "\\u001b[mleer \\u001b[38;5;33m256 \\u001b[48;2;1;2;3mbg"},
        {"type": "os", "key": "OS", "keyColor": "38;2;10;20;30", "format": "{1}"},
        {"type": "memory", "key": "RAM", "keyColor": "1;38;2;40;50;60", "percent": {"type": 3}},
        {"type": "custom", "format": "a,]b"},
    ],
}
"""
COMPACT = """{
    "logo": {"type": "kitty", "source": "b.png"},
    "display": {
        "separator": " ",
        "color": {"keys": "1;38;2;10;20;30", "separator": "38;2;40;50;60", "title": "38;2;10;20;30"},
        "bar": {"color": {"elapsed": "38;2;1;2;3", "total": "48;2;9;9;9"}, "width": 6},
        "percent": {"color": {"green": "32"}},
        "zahl": 1, "exp": 1e5, "klein": 1e-7, "an": 1, "liste": [1.0, 2.5, "x", []]
    },
    "extra": true,
    "modules": [
        "title",
        {"type": "custom", "format": "\\u001b[1;38;2;10;20;30mKurz\\u001b[0m"},
        {"type": "os", "key": "OS", "keyColor": "38;2;10;20;30", "format": "{2}"},
        "cpu",
        {"type": "memory", "key": "RAM", "keyColor": "1;38;2;40;50;60", "percent": {"type": 3}}
    ]
}
"""
MINI = """{
    "modules": [
        {"type": "custom", "format": "\\u001b[38;2;77;77;77mMini"},
        "title",
        "break"
    ]
}
"""


def make_look(lid="demo", compact=True, mini=True):
    d = FF if lid == "miku" else FF / lid
    write(d / "config.jsonc", CONFIG)
    if compact:
        write(d / "compact.jsonc", COMPACT)
    if mini:
        write(d / "mini.jsonc", MINI)
    return d


def scenario_get_save(cli):
    LOG.append("=== get, save, import")
    fresh()
    run(cli, "list")
    make_look("demo")
    make_look("miku")
    make_look("nur-config", compact=False, mini=False)
    write(FF / "Pictures/x.png", "")
    write(FF / "Pictures/tactical/B.png", "")
    write(FF / "Pictures/tactical/a.png", "")
    write(FF / "Pictures/tactical/c.txt", "")
    write(FF / "demo/Pictures/z.png", "")
    write(FF / "demo/Pictures/Y.png", "")
    (FF / "ohne-config").mkdir()
    run(cli, "list")
    look = run(cli, "get", "demo")["look"]
    LOG.append("# get legt nichts an")
    snapshot()
    run(cli, "get", "miku")
    run(cli, "get", "nur-config")
    run(cli, "save", "demo", "--json", json.dumps(look, ensure_ascii=False), tree=True)
    run(cli, "get", "demo")
    LOG.append("# Speichern ueber stdin, ohne Aenderung")
    run(cli, "save", "demo", stdin_text=json.dumps(look), tree=True)
    LOG.append("# von Hand geaendert: Konflikt")
    with open(FF / "demo/compact.jsonc", "a") as f:
        f.write("// Hand\n")
    current = run(cli, "get", "demo")["look"]
    run(cli, "save", "demo", "--json", json.dumps(current), tree=True)
    run(cli, "save", "demo", "--json", json.dumps(current), "--force", tree=True)
    LOG.append("# Zeilenenden: Python liest \\r\\n als \\n")
    (FF / "demo/mini.jsonc").write_bytes((FF / "demo/mini.jsonc").read_bytes().replace(b"\n", b"\r\n"))
    current = run(cli, "get", "demo")["look"]
    run(cli, "save", "demo", "--json", json.dumps(current), tree=True)
    run(cli, "raw-get", "demo", "mini")
    run(cli, "import", "nur-config", tree=True)
    run(cli, "import", "nur-config", tree=True)
    run(cli, "import", "gibtsnicht")
    run(cli, "import", "miku", tree=True)
    run(cli, "list")
    (FF / "demo/look.json").write_text("{kaputt")
    run(cli, "get", "demo")
    run(cli, "list")
    (FF / "demo/look.json").write_text('{"version": 1, "title": "x"}')
    run(cli, "get", "demo")
    run(cli, "list")
    (FF / "demo/look.json").write_text("[1]")
    run(cli, "list")
    shutil.rmtree(FF / "demo")
    (FF / "GROSS").mkdir()
    write(FF / "GROSS/config.jsonc", "{}")
    run(cli, "list")
    shutil.rmtree(FF / "GROSS")
    write(FF / "kaputt/config.jsonc", "{ nein")
    run(cli, "list")


def scenario_arguments(cli):
    LOG.append("=== Argumente und Fehler")
    fresh()
    make_look("demo")
    for args in ([], ["gibtsnicht"], ["get"], ["save"], ["import"], ["preview"], ["preview", "riesig"], ["check"], ["new"], ["delete"],
                 ["cards"], ["card-make", "demo"], ["card-remove", "demo"], ["raw-get", "demo"], ["raw-get", "demo", "riesig"],
                 ["raw-set", "demo"], ["raw-off", "demo"], ["palette"], ["get", "demo", "--from"], ["get", "demo", "--unbekannt", "-x"],
                 ["get", "GROSS"], ["get", "../demo"], ["get", "pictures"], ["get", ".orig"], ["get", "a" * 65], ["cards", "BAD"],
                 ["save", "demo", "--json", "{"], ["save", "demo", "--json", "[]"], ["preview", "mini", "--json", "{"],
                 ["delete", "miku"], ["delete", "fehlt"], ["palette", "/gibtsnicht"], ["palette", "/gibtsnicht", "x"],
                 ["card-make", "demo", "/gibtsnicht"], ["card-remove", "demo", "a/b"], ["card-remove", "demo", ".x"], ["card-remove", "demo", "fehlt.png"],
                 ["scheme-palette"], ["new", "demo"], ["new", "miku"], ["new", "x y"]):
        run(cli, *args)


GOOD_PALETTE = {"primary": "#112233", "accent": "#AABBCC"}


def base_look(**changes):
    look = {"version": 1, "title": "T", "palette": GOOD_PALETTE, "base": {"display": {}}, "sizes": {}, "rows": []}
    look.update(changes)
    return look


BAD_LOOKS = [
    [], "x", {}, {"version": 2}, {"version": "1"}, {"version": 1}, {"version": 1.0, "palette": []},
    {"version": True, "palette": {}, "base": {}, "rows": []},
    {"version": 1, "palette": {"1a": "#000000"}}, {"version": 1, "palette": {"a": "#00000"}}, {"version": 1, "palette": {"a": 5}},
    {"version": 1, "palette": {"a": None}}, {"version": 1, "palette": {"a" * 33: "#000000"}}, {"version": 1, "palette": {}},
    {"version": 1, "palette": {}, "base": [], "rows": []}, {"version": 1, "palette": {}, "base": {}, "rows": {}},
    {"version": 1, "palette": {}, "base": {}, "rows": [1]}, {"version": 1, "palette": {}, "base": {}, "rows": [{}]},
    {"version": 1, "palette": {}, "base": {}, "rows": [{"m": 1}]},
]

MARKUP = ["<@primary>x", "<b @accent>y</>", "<#abcdef>z", "<bg@primary>", "<bg#123456>", "<<raw>", "<>", "<b>", "<d i u>", "<31>", "<0>", "</>",
          "<@fehlt>", "<quatsch>", "<@1a>", "<#12>", "<bg>", "< b  @primary >", "kein tag", "a<b", "a>b", "<<<b>", "<<>", "<a<b>"]
COLOR_VALUES = ["@primary", "b @accent", "#abcdef", "bg@primary", "bg#123456", "b", "d", "/", "31", "1 31", "bg", "x", "", "@fehlt", " b ", "1;38;2;1;2;3",
                "<@primary>x", "<b>", "b\n", "@primary\n"]


def scenario_build(cli):
    LOG.append("=== Erzeugen: Markup, Farben, Patches")
    fresh()
    write(FF / "demo/config.jsonc", '{"modules": []}')
    for bad in BAD_LOOKS:
        run(cli, "save", "demo", "--json", json.dumps(bad))
        run(cli, "preview", "mini", "--json", json.dumps(bad))
    for text in MARKUP:
        look = base_look(rows=[{"m": {"type": "custom", "format": text}}])
        run(cli, "preview", "config", "--json", json.dumps(look))
    for value in COLOR_VALUES:
        look = base_look(base={"display": {"color": {"keys": value}}, "keyColor": value, "other": value}, rows=[{"m": {"type": "x", "keyColor": value, "format": value}}])
        run(cli, "preview", "config", "--json", json.dumps(look))
    LOG.append("# Zeilen und Patches")
    rows = [
        {"m": "title"},
        {"m": "weg", "sizes": {"compact": False, "mini": False}},
        {"m": "ersetzt", "sizes": {"mini": {"=": {"type": "neu"}}}},
        {"m": {"type": "a", "x": 1, "tief": {"p": 1, "q": 2}}, "sizes": {"compact": {"x": 2, "tief": {"p": None, "r": 3}, "neu": "<b>n"}, "mini": {"x": None}}},
        {"m": {"type": "b"}, "sizes": None},
        {"m": {"type": "c"}, "sizes": {"mini": None}},
    ]
    look = base_look(base={"display": {"a": 1, "b": {"c": 2}}, "logo": "x", "modules": ["alt"]},
                     sizes={"compact": {"patch": {"display": {"a": None, "b": {"d": 3}}, "logo": None}}, "mini": {"patch": {"neu": 1}}},
                     rows=rows)
    for size in ("config", "compact", "mini"):
        run(cli, "preview", size, "--json", json.dumps(look))
    run(cli, "save", "patches", "--json", json.dumps(look), tree=True)
    for sizes in ({"mini": True}, {"mini": 5}, {"mini": "x"}, {"mini": []}, [], "x", 5):
        run(cli, "preview", "mini", "--json", json.dumps(base_look(rows=[{"m": {"type": "a"}, "sizes": sizes}])))
    run(cli, "preview", "mini", "--json", json.dumps(base_look(rows=[{"m": "text", "sizes": {"mini": {"x": 1}}}])))
    run(cli, "preview", "mini", "--json", json.dumps(base_look(sizes=[])))
    run(cli, "preview", "mini", "--json", json.dumps(base_look(sizes={"mini": 5})))
    run(cli, "preview", "mini", "--json", json.dumps(base_look(sizes={"mini": {"patch": 5}})))
    LOG.append("# leere Kopfdaten, Titel und Sonderzeichen")
    run(cli, "save", "kopf1", "--json", json.dumps(base_look(base={}, rows=[])), tree=True)
    run(cli, "save", "kopf2", "--json", json.dumps({"version": 1, "palette": {}, "base": {"ä": "ö\n\"\\\t\u0001🎵\u007f"}, "rows": [{"m": "ä"}]}), tree=True)
    run(cli, "save", "kopf3", "--json", json.dumps(base_look(title=None, base={"z": 1e16, "y": 1e-5, "x": 1.5, "w": 100000000000000000000.0}, rows=[])), tree=True)
    run(cli, "save", "kopf4", "--json", json.dumps(base_look(title=5, generated={"mini": "alt"}, rows=[])), tree=True)
    run(cli, "save", "kopf5", "--json", json.dumps(base_look(generated=None)), tree=True)


def scenario_lifecycle(cli):
    LOG.append("=== new, delete, Karten, eigene Dateien")
    fresh()
    make_look("miku")
    run(cli, "new", "kopie-von_miku.x", tree=True)
    make_look("quelle")
    run(cli, "new", "kopie2", "--from", "quelle", "--title", "Mein Titel ä", tree=True)
    run(cli, "new", "kopie2", "--from", "quelle")
    run(cli, "new", "kopie3", "--from", "gibtsnicht")
    run(cli, "delete", "kopie2", tree=True)
    Path("/tmp/gio-scheitert").touch()
    run(cli, "delete", "kopie-von_miku.x", tree=True)
    os.unlink("/tmp/gio-scheitert")
    LOG.append("# eigene Dateien")
    run(cli, "raw-get", "quelle", "mini")
    run(cli, "raw-get", "quelle", "config")
    run(cli, "raw-set", "quelle", "mini", "--text", '{"modules": ["title"]}', tree=True)
    run(cli, "raw-set", "quelle", "compact", stdin_text='// mit Kommentar\n{"modules": ["break",],}\n', tree=True)
    run(cli, "raw-set", "quelle", "compact", "--text", "{ nein")
    run(cli, "raw-set", "quelle", "compact", "--text", "[1]")
    run(cli, "list")
    run(cli, "get", "quelle")
    current = run(cli, "get", "quelle")["look"]
    run(cli, "save", "quelle", "--json", json.dumps(current), tree=True)
    run(cli, "check", "quelle")
    run(cli, "new", "mit-raw", "--from", "quelle", tree=True)
    run(cli, "raw-off", "quelle", "mini", tree=True)
    run(cli, "raw-off", "quelle", "compact", "--adopt", tree=True)
    run(cli, "raw-off", "gibtsnicht", "mini")
    make_look("adopt")
    run(cli, "raw-set", "adopt", "mini", "--text", '{"modules": ["a"]}')
    run(cli, "raw-set", "adopt", "compact", "--text", '{"modules": ["b"]}')
    run(cli, "raw-off", "adopt", "mini", "--adopt", tree=True)


def scenario_preview(cli):
    LOG.append("=== Vorschau: ANSI und Breiten")
    fresh()
    make_look("demo")
    samples = {
        "farben": "\x1b[1;38;2;10;20;30mfett\x1b[22m normal \x1b[3mkursiv\x1b[23m \x1b[4mu\x1b[24m \x1b[2md\x1b[0m\n"
                  "\x1b[31mrot\x1b[39m \x1b[91mhell\x1b[49m \x1b[41mbg\x1b[101mbg2\x1b[0m \x1b[38;5;5ma\x1b[38;5;100mb\x1b[38;5;240mc\x1b[48;5;16md\x1b[48;5;231me\x1b[0m\n"
                  "\x1b[m\x1b[;1mx\x1b[0;;1my\x1b[38;2;1mz\x1b[38;5mq\x1b[0m\n",
        "steuerung": "a\x1b[2Cb\x1b[?25lc\x1b[Kd\x1b[1;1He\x1b[?25hf\n\x1b[1mfarbe bleibt\nueber zeilen\x1b[0m\n",
        "breiten": "日本語 abc\nＡＢＣ\né́x\n​‍⁠a\n👍🏽👨‍👩‍👧\n" + "x" * 33 + "\n" + "y" * 51 + "\n" + "z" * 65 + "\n한글\nา่\ǹ\n",
        "zu-hoch": "".join(f"z{i}\n" for i in range(30)),
        "zeilenenden": "a\r\nb\rc\n\n\n",
        "leer": "",
        "nur-leer": "\n\n\n",
        "segmente": "\x1b[31ma\x1b[31mb\x1b[0mc\x1b[0md\x1b[1m\x1b[0me\n",
    }
    for name, text in samples.items():
        path = Path(f"/tmp/ausgabe-{name}")
        path.write_bytes(text.encode())
        Path("/tmp/ff-modus").write_text(f"datei:{path}")
        LOG.append(f"# {name}")
        for size in ("config", "compact", "mini"):
            run(cli, "preview", size, "--raw", "demo")
    for mode in ("fehler", "fehler-still", "fehler-mit-ausgabe", "kaputt"):
        Path("/tmp/ff-modus").write_text(mode)
        LOG.append(f"# {mode}")
        run(cli, "preview", "mini", "--raw", "demo")
    os.unlink("/tmp/ff-modus")
    run(cli, "preview", "mini", "--raw", "gibtsnicht")
    run(cli, "preview", "mini", "--raw", "scheme")
    write(STATE_DIR / "theme/fastfetch.jsonc", '{"modules": ["schema-config"]}')
    write(STATE_DIR / "theme/fastfetch-mini.jsonc", '{"logo": 1, "modules": ["schema-mini"]}')
    run(cli, "preview", "config", "--raw", "scheme")
    run(cli, "preview", "mini", "--raw", "scheme")
    run(cli, "preview", "compact", "--raw", "scheme")
    run(cli, "check", "demo")
    write(FF / "liste/config.jsonc", "[1]")
    run(cli, "preview", "config", "--raw", "liste")
    LOG.append("# ohne fastfetch")
    saved = STUBS / "fastfetch"
    moved = STUBS / "weg"
    saved.rename(moved)
    empty_env = dict(ENV)
    ENV["PATH"] = str(STUBS)
    run(cli, "preview", "mini", "--raw", "demo") if cli[0] != "python3" else run(["/usr/bin/python3", *cli[1:]], "preview", "mini", "--raw", "demo")
    ENV.clear()
    ENV.update(empty_env)
    moved.rename(saved)
    LOG.append("# haengt: Zeitlimit 15 s")
    Path("/tmp/ff-modus").write_text("haengt")
    run(cli, "preview", "mini", "--raw", "demo")
    os.unlink("/tmp/ff-modus")


def scenario_images(cli):
    LOG.append("=== Bilder: Karten und Paletten")
    from PIL import Image
    fresh()
    make_look("demo")
    imgs = HOME / "bilder"
    imgs.mkdir(exist_ok=True)
    rng = random.Random(7)

    def image(name, build, size=(320, 240)):
        im = Image.new("RGB", size)
        px = im.load()
        for y in range(size[1]):
            for x in range(size[0]):
                px[x, y] = build(x, y)
        im.save(imgs / name)
        return imgs / name

    grad = image("verlauf.png", lambda x, y: (x * 255 // 320, y * 255 // 240, 128))
    grey = image("grau bild (1).png", lambda x, y: (x * 255 // 320,) * 3)
    black = image("schwarz.png", lambda x, y: (0, 0, 0))
    bunt = image("bunt.jpg", lambda x, y: ((x // 40) * 30 % 256, (y // 30) * 70 % 256, (x + y) // 3 % 256))
    rausch = image("rausch.png", lambda x, y: (rng.randrange(256), rng.randrange(256), rng.randrange(256)))
    sonder = image("---.png", lambda x, y: (200, 10, 10), (10, 10))
    for path in (grad, grey, black, bunt, rausch, sonder):
        run(cli, "palette", str(path))
        run(cli, "palette", str(path), "2")
        run(cli, "palette", str(path), "30")
        run(cli, "palette", str(path), "-1")
    (imgs / "kaputt.png").write_text("kein bild")
    run(cli, "palette", str(imgs / "kaputt.png"))
    run(cli, "palette", "~/bilder/verlauf.png", "3")
    for wallpaper in sorted(Path("/tmp/work/screenshots").glob("*"))[:4]:
        run(cli, "palette", str(wallpaper), "12")
    LOG.append("# Karten")
    run(cli, "cards", "demo")
    run(cli, "card-make", "demo", str(grad), tree=True)
    run(cli, "card-make", "demo", str(grad), "@primary", tree=True)
    run(cli, "card-make", "demo", str(grey), "#ff0000", tree=True)
    run(cli, "card-make", "demo", str(sonder), "00ff00", tree=True)
    run(cli, "card-make", "demo", str(grad), "@fehlt")
    run(cli, "card-make", "demo", str(grad), "rot")
    run(cli, "card-make", "demo", str(imgs / "kaputt.png"), "#000000", tree=True)
    run(cli, "card-make", "miku", str(grad))
    run(cli, "cards", "demo")
    run(cli, "card-remove", "demo", "verlauf.png", tree=True)
    Path("/tmp/gio-scheitert").touch()
    run(cli, "card-remove", "demo", "verlauf-2.png", tree=True)
    os.unlink("/tmp/gio-scheitert")
    write(FF / "ohne-primary/config.jsonc", '{"modules": []}')
    run(cli, "card-make", "ohne-primary", str(grad), tree=True)
    LOG.append("# Schema")
    run(cli, "scheme-palette")
    write(STATE_DIR / "scheme.json", "{kaputt")
    run(cli, "scheme-palette")
    write(STATE_DIR / "scheme.json", json.dumps({"colours": {"primary": "ABCDEF", "tertiary": "123456", "secondary": "12345", "outline": "00gg00"}}))
    run(cli, "scheme-palette")
    write(STATE_DIR / "scheme.json", json.dumps({}))
    run(cli, "scheme-palette")


def scenario_fuzz(cli):
    LOG.append("=== Zufaellige Konfigurationen: Ausrichten der Zeilen (difflib)")
    rng = random.Random(20261106)
    kinds = ["os", "cpu", "memory", "custom", "title", "break", "gpu", "disk"]

    def module():
        kind = rng.choice(kinds)
        if kind in ("title", "break"):
            return kind
        m = {"type": kind}
        if kind == "custom":
            m["format"] = rng.choice(["=== a", "--- b", "c", " d", "<x>e", "\u001b[1mf", "日本", ""])
        else:
            if rng.random() < 0.5:
                m["key"] = rng.choice(["K", "L", "ä"])
            if rng.random() < 0.3:
                m["keyColor"] = f"38;2;{rng.randrange(4)};0;0"
            if rng.random() < 0.2:
                m["tief"] = {"a": rng.randrange(3), "b": rng.choice([1, 1.0, True, "x", None])}
        return m

    for case in range(120):
        fresh()
        base = [module() for _ in range(rng.randrange(0, 18))]

        def variant():
            out = []
            for m in base:
                roll = rng.random()
                if roll < 0.2:
                    continue
                if roll < 0.35:
                    out.append(module())
                out.append(m)
            if rng.random() < 0.3 and len(out) > 1:
                i, j = rng.randrange(len(out)), rng.randrange(len(out))
                out[i], out[j] = out[j], out[i]
            return out

        display = {"color": {"keys": f"38;2;{rng.randrange(3)};1;1"}, "w": rng.choice([1, 1.0])}
        write(FF / "f/config.jsonc", json.dumps({"display": display, "modules": base}, ensure_ascii=False))
        write(FF / "f/compact.jsonc", json.dumps({"display": display, "x": rng.randrange(2), "modules": variant()}, ensure_ascii=False))
        write(FF / "f/mini.jsonc", json.dumps({"modules": variant()}, ensure_ascii=False))
        look = run(cli, "get", "f")
        if case % 4 == 0 and "look" in look:
            run(cli, "save", "f", "--json", json.dumps(look["look"], ensure_ascii=False), tree=True)


def scenario_real_looks(cli):
    LOG.append("=== deine echten Looks (Kopie)")
    if not REAL.is_dir():
        LOG.append("# nicht eingehaengt")
        return
    fresh()
    shutil.rmtree(FF)
    shutil.copytree(REAL, FF, ignore=shutil.ignore_patterns("*.png", "*.jpg", "*.webp"))
    run(cli, "list")
    ids = [l["id"] for l in run(cli, "list")["looks"]]
    LOG.append(f"# Looks: {ids}")
    for lid in ids:
        res = run(cli, "get", lid)
        for size in ("config", "compact", "mini"):
            run(cli, "raw-get", lid, size)
            run(cli, "preview", size, "--raw", lid)
            if "look" in res:
                run(cli, "preview", size, "--json", json.dumps(res["look"], ensure_ascii=False))
        run(cli, "check", lid)
    snapshot()
    for lid in ids:
        res = run(cli, "get", lid)
        if res.get("managed"):
            LOG.append(f"# {lid}: Speichern ohne Aenderung erzeugt dieselben Dateien, kein Konflikt")
            run(cli, "save", lid, "--json", json.dumps(res["look"], ensure_ascii=False), tree=True)
    for lid in ids:
        run(cli, "import", lid, tree=True)


def scenario_real_fastfetch(cli):
    LOG.append("=== echtes fastfetch, nur feste Texte")
    fresh()
    ENV["PATH"] = "/usr/bin"
    look = base_look(rows=[{"m": {"type": "custom", "format": "<b @primary>Kopf</> normal"}}, {"m": {"type": "custom", "format": "<@accent>日本語</> ä"}}, {"m": "break"}, {"m": {"type": "custom", "format": "ende"}}])
    for size in ("config", "compact", "mini"):
        run(cli, "preview", size, "--json", json.dumps(look))
    run(cli, "save", "echt", "--json", json.dumps(look))
    run(cli, "check", "echt")
    run(cli, "raw-set", "echt", "mini", "--text", '{"modules": [{"type": "custom", "format": "\\u001b[1;31mroh"}]}')
    run(cli, "preview", "mini", "--raw", "echt")
    ENV["PATH"] = f"{STUBS}:/usr/bin"


SCENARIOS = [scenario_get_save, scenario_arguments, scenario_build, scenario_lifecycle, scenario_preview, scenario_images,
             scenario_fuzz, scenario_real_looks, scenario_real_fastfetch]


def main():
    assert_sandbox()
    setup_stubs()
    out, cli = sys.argv[1], sys.argv[2:]
    only = os.environ.get("COMPARE_ONLY")
    for scenario in SCENARIOS:
        if not only or only in scenario.__name__:
            scenario(cli)
    with open(out, "w") as f:
        f.write("\n".join(LOG) + "\n")


if __name__ == "__main__":
    main()
