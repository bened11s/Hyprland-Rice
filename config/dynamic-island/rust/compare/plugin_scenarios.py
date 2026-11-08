#!/usr/bin/env python3
"""Vergleichstest von `dynamic-island plugin`, nur fuer die Sandbox.

Aufruf: plugin_scenarios.py <protokoll> <diese-fassung> <andere-fassung>

Jeder Befehl laeuft in einem frischen HOME. Protokolliert werden Ausgaben,
Exit-Code und der ganze Dateibaum danach (Pfad, Modus, Inhalt, Zeitstempel).
Mit der anderen Fassung entstehen Pakete, die diese dann importiert, so ist
auch der Austausch zwischen Alt und Neu abgedeckt.
"""

import hashlib
import io
import json
import os
import pty
import re
import select
import shutil
import stat
import subprocess
import sys
import tarfile
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import assert_sandbox

HOME = Path(os.environ["HOME"])
PLUGINS = HOME / ".config/quickshell/dynamic-island/plugins"
STATE = HOME / ".config/dynamic-island/plugins.json"
REAL_PLUGINS = Path("/tmp/work/quickshell/dynamic-island/plugins")
FIXED_TIME = 1700000000
LOG: list[str] = []
ENV = {**os.environ, "DYNAMIC_ISLAND_PYTHON_CLI": "/tmp/work/dynamic-island/bin/dynamic-island"}


def normalise(text: str) -> str:
    # Das Suffix haengt davon ab, ob zwei Sicherungen in dieselbe Sekunde fallen
    text = re.sub(r"\d{8}-\d{6}(-\d+)*", "<zeit>", text)
    text = re.sub(r"/tmp/dip-\w+", "/tmp/dip-X", text)
    text = re.sub(r"\.plugins-\w+", ".plugins-X", text)
    # Texte der JSON- und Gzip-Bibliotheken sind je Sprache anders
    for lead in (r"ist kein gueltiges JSON", r"fehlt oder ist kaputt", r"Kein \.dip-Paket \(tar\.gz erwartet\)"):
        text = re.sub(rf"({lead}): [^\"\n]*", r"\1: <text>", text)
    text = re.sub(r"(e\.json): Expecting [^\"\n]*", r"\1: <text>", text)
    text = re.sub(r"(e\.json): key must [^\"\n]*", r"\1: <text>", text)
    text = re.sub(r"(keine\.json): [^\"\n]*", r"\1: <text>", text)
    # Die Kompression darf anders ausfallen
    text = re.sub(r'"size": \d+', '"size": N', text)
    text = re.sub(r"\(\d+(\.\d+)? [KMG]?B, ", "(N, ", text)
    return text


def snapshot() -> None:
    LOG.append("  [baum]")
    lines = []
    for path in sorted(HOME.rglob("*")):
        rel = normalise(str(path.relative_to(HOME)))
        st = path.lstat()
        mode = oct(stat.S_IMODE(st.st_mode))
        if path.is_symlink():
            lines.append(f"    {rel} -> {os.readlink(path)}")
        elif path.is_dir():
            lines.append(f"    {rel}/ {mode}")
        elif path.name == "hashes.json":
            raw = path.read_text()
            data = json.loads(raw)
            same = raw == json.dumps(data)
            index = {normalise(k): [v[0], v[2]] for k, v in data.items()}
            lines.append(f"    {rel} {mode} python-format={same} {sorted(index.items())}")
        else:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
            age = "fest" if int(st.st_mtime) == FIXED_TIME else "neu"
            if path.suffix == ".dip" or path.name.endswith("settings.json") or path.name == "e.json":
                digest = "export"  # Inhalt prueft inspect(), dort ohne Zeitstempel
            lines.append(f"    {rel} {mode} {digest} {age}")
    LOG.extend(sorted(lines))


def run(cli, *args, tree=False, code_only=False, stdin=subprocess.DEVNULL):
    LOG.append(f"$ {' '.join(args)}")
    res = subprocess.run(cli + list(args), stdin=stdin, capture_output=True, text=True, env=ENV, cwd=HOME)
    LOG.append(f"  exit {res.returncode}")
    if code_only:
        return res
    if res.stdout:
        LOG.append("  out: " + normalise(res.stdout).rstrip("\n").replace("\n", "\n       "))
    if res.stderr:
        LOG.append("  err: " + normalise(res.stderr).rstrip("\n").replace("\n", "\n       "))
    if tree:
        snapshot()
    return res


def run_pty(cli, answer, *args):
    """Antwortet wie ein Mensch auf die Rueckfrage."""
    LOG.append(f"$ (Terminal, Antwort {answer!r}) {' '.join(args)}")
    master, slave = pty.openpty()
    proc = subprocess.Popen(cli + list(args), stdin=slave, stdout=slave, stderr=slave, env=ENV, cwd=HOME, close_fds=True)
    os.close(slave)
    os.write(master, answer.encode() + b"\n")
    out = b""
    while True:
        ready, _, _ = select.select([master], [], [], 5)
        if not ready:
            break
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        out += chunk
    code = proc.wait()
    os.close(master)
    text = out.decode().replace("\r\n", "\n")
    # Das Echo der Antwort kommt je nach Zeitpunkt vor oder nach der Frage
    text = text.replace(answer + "\n", "", 1)
    LOG.append(f"  exit {code}")
    LOG.append("  out: " + normalise(text).rstrip("\n").replace("\n", "\n       "))
    snapshot()


def inspect(path: Path) -> None:
    """Paketinhalt, unabhaengig von der Kompression."""
    LOG.append(f"  [paket {path.name}]")
    with tarfile.open(path, "r:gz") as tar:
        for m in tar.getmembers():
            data = tar.extractfile(m).read() if m.isfile() else b""
            digest = hashlib.sha256(data).hexdigest()[:16]
            kind = {tarfile.REGTYPE: "datei", tarfile.SYMTYPE: f"link {m.linkname}", tarfile.DIRTYPE: "ordner"}.get(m.type, m.type)
            LOG.append(f"    {m.name} {kind} {oct(m.mode)} {m.uid}:{m.gid} {m.uname!r}:{m.gname!r} {m.size} "
                       + ("-" if m.name == "dip.json" else digest)
                       + (f" mtime={int(m.mtime)}" if m.name != "dip.json" else ""))
        head = json.loads(tar.extractfile("dip.json").read())
        raw = tar.extractfile("dip.json").read().decode()
    same = raw == json.dumps(head, indent=2, ensure_ascii=False)
    head["created"] = "<zeit>" if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d", head["created"]) else head["created"]
    LOG.append(f"    python-format={same}")
    LOG.append("    dip.json " + json.dumps(head, ensure_ascii=False))


# ---- Testdaten ---------------------------------------------------------------


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data if isinstance(data, str) else json.dumps(data, indent=4, ensure_ascii=False))


GOOD = {
    "id": "good",
    "name": "Güt Plügin",
    "version": "1.2.0",
    "api": 1,
    "description": "Beschreibung mit ä",
    "main": "Main.qml",
    "settings": {"a": {"default": 1, "title": "Wert ä"}, "b": {"default": "ü"}, "c": {"default": [1, 2.5, None]}},
    "tiles": {"t1": {"component": "Tile.qml"}},
    "panels": {"wallpaper": {"component": "Panel.qml"}},
    "widgets": {"clock": {"component": "Widget.qml"}},
    "keybinds": {"go": {"keys": "SUPER + G", "title": "Go", "exec": "echo hallo"},
                 "ip": {"keys": "SUPER + I", "title": "Ip", "group": "G", "ipc": "x y"}},
    "files": [{"path": "~/.local/share/good/data.txt"}, {"path": "~/.local/share/good/dir"},
              {"path": "~/.local/share/good/missing.txt", "optional": True},
              {"path": "~/.local/share/good/opt.txt", "optional": True}],
}


def fresh(extra=True) -> None:
    for child in HOME.iterdir():
        shutil.rmtree(child) if child.is_dir() and not child.is_symlink() else child.unlink()
    good = PLUGINS / "good"
    write_json(good / "plugin.json", GOOD)
    for name in ("Main.qml", "Tile.qml", "Panel.qml", "Widget.qml", "sub/deep/x.txt", "__pycache__/a.pyc", ".git/config",
                 "alt.dip", ".qmlls.ini", "sub/.DS_Store", "sub-a.txt", "Ä.txt"):
        (good / name).parent.mkdir(parents=True, exist_ok=True)
        (good / name).write_text(f"inhalt {name}\n")
    (good / "run.sh").write_text("#!/bin/sh\n")
    (good / "run.sh").chmod(0o755)
    (good / "gruppe.sh").write_text("x\n")
    (good / "gruppe.sh").chmod(0o640)
    data = HOME / ".local/share/good"
    (data / "dir/inner").mkdir(parents=True)
    (data / "data.txt").write_text("daten\n")
    (data / "opt.txt").write_text("optional\n")
    (data / "dir/inner/a.txt").write_text("a\n")
    (data / "dir/__pycache__").mkdir()
    (data / "dir/__pycache__/b.pyc").write_text("b\n")
    if extra:
        write_json(PLUGINS / "comp/plugin.json", {"id": "comp", "name": "Komponente", "api": 1, "parent": "good"})
        write_json(PLUGINS / "waise/plugin.json", {"id": "waise", "name": "Waise", "api": 1, "version": "2", "parent": "gibtsnicht"})
        write_json(PLUGINS / "donor/plugin.json", {"id": "donor", "name": "An", "api": 1, "defaultEnabled": True})
        write_json(PLUGINS / "kern/plugin.json", {"id": "kern", "name": "Kern", "api": 1, "builtin": True})
        write_json(PLUGINS / "badjson/plugin.json", "{kaputt")
        (PLUGINS / "leer").mkdir()
        write_json(PLUGINS / "falsch/plugin.json", {"id": "anders", "name": "x", "api": 1})
        write_json(PLUGINS / "_vorlage/plugin.json", {"id": "_vorlage"})
        write_json(PLUGINS / ".versteckt/plugin.json", {"id": "x"})
        (PLUGINS / "eine-datei").write_text("x")
        write_json(PLUGINS / "_example/plugin.json", {"$schema": "../plugin.schema.json", "id": "_example", "name": "Vorlage", "version": "9", "api": 1, "defaultEnabled": True, "main": "Main.qml"})
        (PLUGINS / "_example/Main.qml").write_text("// vorlage\n")
        (PLUGINS / "_example/__pycache__").mkdir()
        (PLUGINS / "_example/__pycache__/x").write_text("x")
    write_json(STATE, {"format": 1, "enabled": {"donor": False, "good": True, "nullwert": None}, "settings": {"good": {"a": 5, "ä": "ö\n\"", "z": 1.5e-7}}, "unbekannt": 1})
    for path in HOME.rglob("*"):
        if not path.is_symlink():
            os.utime(path, (FIXED_TIME, FIXED_TIME))


def make_package(path: Path, plugin_files: dict, head_changes=None, extra=None, raw_members=None) -> Path:
    """Baut ein .dip von Hand, auch ein kaputtes."""
    files = {f"plugin/{k}": (v if isinstance(v, bytes) else (v if isinstance(v, str) else json.dumps(v)).encode()) for k, v in plugin_files.items()}
    files.update(extra or {})
    manifest = plugin_files.get("plugin.json", {})
    manifest = manifest if isinstance(manifest, dict) else {}
    head = {"format": "dynamic-island-plugin", "formatVersion": 1,
            "plugin": {"id": manifest.get("id"), "name": manifest.get("name"), "version": manifest.get("version", "0"), "api": 1},
            "created": "2026-01-01T00:00:00+00:00", "generator": "test", "enabled": True, "files": [],
            "checksums": {k: hashlib.sha256(v).hexdigest() for k, v in files.items()}}
    head.update(head_changes or {})
    path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(path, "w:gz") as tar:
        def add(name, data, **attrs):
            info = tarfile.TarInfo(name)
            info.size, info.mtime, info.mode = len(data), FIXED_TIME, attrs.pop("mode", 0o644)
            tar.addfile(info, io.BytesIO(data))
        if head_changes != {"_kein_kopf": 1}:
            add("dip.json", json.dumps(head).encode())
        for name, data in files.items():
            add(name, data)
        for build in raw_members or []:
            build(tar)
    return path


NEW = {"id": "neu", "name": "Neu ä", "version": "2.0.0", "api": 1}


# ---- Szenarien ---------------------------------------------------------------


def scenario_list_info(cli, _other):
    LOG.append("=== list und info")
    fresh()
    run(cli, "plugin", "list")
    run(cli, "plugin", "list", "--json")
    for pid in ("good", "comp", "donor", "gibtsnicht", "UNGUELTIG", "badjson", "leer", "falsch", "_vorlage", "../good"):
        run(cli, "plugin", "info", pid)
        run(cli, "plugin", "info", pid, "--json")
    for child in list(PLUGINS.iterdir()):
        shutil.rmtree(child) if child.is_dir() else child.unlink()
    run(cli, "plugin", "list")
    shutil.rmtree(PLUGINS)
    run(cli, "plugin", "list", "--json")


def scenario_enable(cli, _other):
    LOG.append("=== enable und disable")
    fresh()
    run(cli, "plugin", "disable", "good", "--json", tree=True)
    run(cli, "plugin", "enable", "comp", tree=True)
    run(cli, "plugin", "enable", "gibtsnicht", "--json")
    run(cli, "plugin", "disable", "badjson", "--json")
    STATE.unlink()
    run(cli, "plugin", "enable", "good", tree=True)
    STATE.write_text("{kaputt")
    run(cli, "plugin", "enable", "good", "--json", tree=True)
    run(cli, "plugin", "list", "--json")


BAD_MANIFESTS = [
    [1], "text", None,
    {}, {"id": 5}, {"id": "GROSS"}, {"id": "-x"}, {"id": "a" * 49}, {"id": "ä"},
    {"id": "x"}, {"id": "x", "name": ""}, {"id": "x", "name": 5},
    {"id": "x", "name": "n"}, {"id": "x", "name": "n", "api": True}, {"id": "x", "name": "n", "api": 1.0},
    {"id": "x", "name": "n", "api": "1"}, {"id": "x", "name": "n", "api": 2}, {"id": "x", "name": "n", "api": 0},
    {"id": "x", "name": "n", "api": -1},
    {"id": "x", "name": "n", "api": 1, "parent": "x"}, {"id": "x", "name": "n", "api": 1, "parent": "A"},
    {"id": "x", "name": "n", "api": 1, "parent": 5}, {"id": "x", "name": "n", "api": 1, "parent": None},
    {"id": "x", "name": "n", "api": 1, "main": "../a"}, {"id": "x", "name": "n", "api": 1, "main": "/a"},
    {"id": "x", "name": "n", "api": 1, "main": 5}, {"id": "x", "name": "n", "api": 1, "main": "fehlt.qml"},
    {"id": "x", "name": "n", "api": 1, "main": None},
    {"id": "x", "name": "n", "api": 1, "settings": []}, {"id": "x", "name": "n", "api": 1, "settings": {"1a": {"default": 1}}},
    {"id": "x", "name": "n", "api": 1, "settings": {"a-b": {"default": 1}}}, {"id": "x", "name": "n", "api": 1, "settings": {"a": {}}},
    {"id": "x", "name": "n", "api": 1, "settings": {"a": 1}}, {"id": "x", "name": "n", "api": 1, "settings": None},
    {"id": "x", "name": "n", "api": 1, "tiles": []}, {"id": "x", "name": "n", "api": 1, "tiles": {"A": {"component": "a"}}},
    {"id": "x", "name": "n", "api": 1, "tiles": {"a": {}}}, {"id": "x", "name": "n", "api": 1, "tiles": {"a": {"component": "../a"}}},
    {"id": "x", "name": "n", "api": 1, "tiles": {"a": 1}}, {"id": "x", "name": "n", "api": 1, "tiles": {"a": {"component": "fehlt.qml"}}},
    {"id": "x", "name": "n", "api": 1, "panels": []}, {"id": "x", "name": "n", "api": 1, "panels": {"1a": {"component": "a"}}},
    {"id": "x", "name": "n", "api": 1, "panels": {"a": {"component": 1}}},
    {"id": "x", "name": "n", "api": 1, "widgets": []}, {"id": "x", "name": "n", "api": 1, "widgets": {"1a": {"component": "a"}}},
    {"id": "x", "name": "n", "api": 1, "widgets": {"a": {"component": "a/../b"}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": []}, {"id": "x", "name": "n", "api": 1, "keybinds": {"A": {}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": 1}}, {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "  "}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K"}}}, {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K", "title": "a|b"}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K", "title": "T", "group": ""}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K", "title": "T", "group": "a|b"}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K", "title": "T"}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K", "title": "T", "ipc": "a", "exec": "b"}}},
    {"id": "x", "name": "n", "api": 1, "keybinds": {"a": {"keys": "K", "title": "T", "ipc": 5}}},
    {"id": "x", "name": "n", "api": 1, "files": {}}, {"id": "x", "name": "n", "api": 1, "files": [1]}, {"id": "x", "name": "n", "api": 1, "files": [{}]},
    {"id": "x", "name": "n", "api": 1, "files": [{"path": "/etc/passwd"}]}, {"id": "x", "name": "n", "api": 1, "files": [{"path": "~/../x"}]},
    {"id": "x", "name": "n", "api": 1, "files": [{"path": "~//etc/passwd"}]}, {"id": "x", "name": "n", "api": 1, "files": [{"path": "~/a/../../x"}]},
    {"id": "x", "name": "n", "api": 1, "files": [{"path": "~/raus/x"}]}, {"id": "x", "name": "n", "api": 1, "files": [{"path": "~/"}]},
    {"id": "x", "name": "n", "api": 1, "files": [{"path": "~/ok/x"}]},
    {"id": "x", "name": "n", "api": 1, "version": 5},
]


def scenario_validate(cli, _other):
    LOG.append("=== validate: Manifeste")
    fresh(extra=False)
    (HOME / "raus").symlink_to("/etc")
    for manifest in BAD_MANIFESTS:
        folder = HOME / "t/x"
        shutil.rmtree(folder, ignore_errors=True)
        write_json(folder / "plugin.json", json.dumps(manifest))
        LOG.append("# " + json.dumps(manifest, ensure_ascii=False)[:120])
        run(cli, "plugin", "validate", "t/x", "--json")
    LOG.append("# Ordnerangaben")
    run(cli, "plugin", "validate", str(PLUGINS / "good"), "--json")
    run(cli, "plugin", "validate", "~/.config/quickshell/dynamic-island/plugins/good")
    for path in ("gibtsnicht", "t/x/", "t/x/.", "t/x/../x", ".", "..", "~"):
        run(cli, "plugin", "validate", path, "--json")


def scenario_bad_packages(cli, _other):
    LOG.append("=== Pakete, auch boesartige")
    fresh(extra=False)
    d = HOME / "p"
    d.mkdir()
    ok = {"plugin.json": NEW}

    def member(name, kind=tarfile.REGTYPE, data=b"x", link="", mode=0o644):
        def build(tar):
            info = tarfile.TarInfo(name)
            info.type, info.linkname, info.mode = kind, link, mode
            info.size = len(data) if kind == tarfile.REGTYPE else 0
            tar.addfile(info, io.BytesIO(data) if kind == tarfile.REGTYPE else None)
        return build

    cases = {
        "gut": lambda p: make_package(p, ok),
        "ausbruch": lambda p: make_package(p, ok, raw_members=[member("plugin/../../boese")]),
        "absolut": lambda p: make_package(p, ok, raw_members=[member("/tmp/boese")]),
        "symlink": lambda p: make_package(p, ok, raw_members=[member("plugin/l", tarfile.SYMTYPE, link="/etc/passwd")]),
        "hardlink": lambda p: make_package(p, ok, raw_members=[member("plugin/l", tarfile.LNKTYPE, link="plugin/plugin.json")]),
        "fifo": lambda p: make_package(p, ok, raw_members=[member("plugin/f", tarfile.FIFOTYPE)]),
        "geraet": lambda p: make_package(p, ok, raw_members=[member("plugin/d", tarfile.CHRTYPE)]),
        "fremd": lambda p: make_package(p, ok, raw_members=[member("anderes/x")]),
        "wurzelordner": lambda p: make_package(p, ok, raw_members=[member(".", tarfile.DIRTYPE)]),
        "punktname": lambda p: make_package(p, ok, raw_members=[member("./plugin/extra.txt")]),
        "zu-viele": lambda p: make_package(p, ok, raw_members=[member(f"plugin/{i}") for i in range(5001)]),
        "summe-falsch": lambda p: make_package(p, ok, head_changes={"checksums": {"plugin/plugin.json": "0" * 64}}),
        "summe-fehlt": lambda p: make_package(p, ok, head_changes={"checksums": {}}),
        "summe-zuviel": lambda p: make_package(p, ok, head_changes={"checksums": {"plugin/plugin.json": hashlib.sha256(json.dumps(NEW).encode()).hexdigest(), "plugin/geist": "0"}}),
        "extra-datei": lambda p: make_package(p, ok, raw_members=[member("plugin/extra")]),
        "format": lambda p: make_package(p, ok, head_changes={"format": "anders"}),
        "format-neu": lambda p: make_package(p, ok, head_changes={"formatVersion": 2}),
        "ohne-kopf": lambda p: make_package(p, ok, head_changes={"_kein_kopf": 1}),
        "ohne-manifest": lambda p: make_package(p, {"a.txt": "x"}),
        "manifest-kaputt": lambda p: make_package(p, {"plugin.json": "{"}),
        "manifest-falsch": lambda p: make_package(p, {"plugin.json": {"id": "A"}}),
        "id-anders": lambda p: make_package(p, ok, head_changes={"plugin": {"id": "anders"}}),
        "datei-ausserhalb": lambda p: make_package(p, ok, head_changes={"files": [{"path": "/etc/x", "archive": "plugin"}]}),
        "datei-raus": lambda p: make_package(p, ok, head_changes={"files": [{"path": "~/../x", "archive": "plugin"}]}),
        "datei-fehlt": lambda p: make_package(p, ok, head_changes={"files": [{"path": "~/x", "archive": "files/0"}]}),
    }
    for name, build in cases.items():
        path = build(d / f"{name}.dip")
        for action in (("validate", str(path), "--json"), ("import", str(path), "--yes", "--json")):
            run(cli, "plugin", *action)
        if (PLUGINS / "neu").exists():
            shutil.rmtree(PLUGINS / "neu")
    (d / "keins.dip").write_bytes(b"kein gzip")
    run(cli, "plugin", "validate", str(d / "keins.dip"), "--json")
    run(cli, "plugin", "import", str(d / "nicht-da.dip"), "--yes", "--json")
    with open(d / "gz-ohne-tar.dip", "wb") as f:
        import gzip
        f.write(gzip.compress(b"\xffkein tar" * 100))
    run(cli, "plugin", "validate", str(d / "gz-ohne-tar.dip"), "--json")
    LOG.append("# Nichts darf ausserhalb gelandet sein")
    run(cli, "plugin", "list", "--json", tree=True)
    LOG.append(f"  /tmp/boese: {os.path.exists('/tmp/boese')}")


def scenario_export(cli, _other):
    LOG.append("=== export")
    fresh()
    out = HOME / "aus"
    out.mkdir()
    res = run(cli, "plugin", "export", "good", "-o", str(out), "--json", tree=True)
    inspect(out / "good-1.2.0.dip")
    (out / "good-1.2.0.dip").unlink()
    run(cli, "plugin", "export", "good", "-o", "aus/", "--no-settings")
    inspect(out / "good-1.2.0.dip")
    run(cli, "plugin", "export", "good", "-o", "aus/datei.dip", "--no-files")
    inspect(out / "datei.dip")
    run(cli, "plugin", "export", "good", "-o", "aus/neu/tief/", "--skip-optional", "--json")
    inspect(out / "neu/tief/good-1.2.0.dip")
    run(cli, "plugin", "export", "good", "-o", "~/aus/tilde.dip", "--json")
    inspect(out / "tilde.dip")
    run(cli, "plugin", "export", "good", "-o", "aus/e.json", "--settings-only", "--json")
    doc = json.loads((out / "e.json").read_text())
    doc["created"] = "<zeit>"
    LOG.append("  settings: " + json.dumps(doc, ensure_ascii=False))
    run(cli, "plugin", "export", "comp", "-o", "aus/", "--settings-only")
    LOG.append("  settings: " + re.sub(r'"created": "[^"]*"', '"created": ""', (out / "comp-settings.json").read_text()))
    run(cli, "plugin", "export", "comp", "--json", tree=True, code_only=True)
    (HOME / "Downloads").mkdir(exist_ok=True)
    run(cli, "plugin", "export", "comp", "--json", tree=True)
    inspect(HOME / "Downloads/comp-0.dip")
    run(cli, "plugin", "export", "waise")
    inspect(HOME / "Downloads/waise-2.dip")
    run(cli, "plugin", "export", "gibtsnicht", "--json")
    (PLUGINS / "good/link").symlink_to("/etc/passwd")
    run(cli, "plugin", "export", "good", "-o", "aus/x.dip", "--json")
    (PLUGINS / "good/link").unlink()
    data = HOME / ".local/share/good"
    (data / "dir/inner/link").symlink_to("a.txt")
    os.utime(data / "dir/inner/link", (FIXED_TIME, FIXED_TIME), follow_symlinks=False)
    run(cli, "plugin", "export", "good", "-o", "aus/mit-link.dip", "--json")
    inspect(out / "mit-link.dip")
    run(cli, "plugin", "validate", "aus/mit-link.dip", "--json")
    (data / "dir/inner/link").unlink()
    LOG.append("# grosse Datei: Hash-Index")
    (PLUGINS / "good/gross.bin").write_bytes(b"\0" * (2 << 20))
    os.utime(PLUGINS / "good/gross.bin", (FIXED_TIME, FIXED_TIME))
    run(cli, "plugin", "export", "good", "-o", "aus/gross.dip", "--json", tree=True)
    run(cli, "plugin", "export", "good", "-o", "aus/gross2.dip", "--json", tree=True)
    run(cli, "plugin", "validate", "aus/gross.dip", "--json", tree=True)


def scenario_import(cli, other):
    LOG.append("=== import")
    fresh()
    d = HOME / "p"
    d.mkdir()
    pkg = make_package(d / "neu.dip", {"plugin.json": {**NEW, "main": "M.qml", "settings": {"s": {"default": 1}},
                                                     "keybinds": {"k": {"keys": "K", "title": "T", "exec": "ls -l"}}},
                                       "M.qml": "x", "sub/run.sh": "y"},
                       head_changes={"settings": {"s": 7},
                                     "files": [{"path": "~/ziel/datei.txt", "archive": "files/0", "type": "file", "optional": False},
                                               {"path": "~/ziel/ordner", "archive": "files/1", "type": "dir", "optional": True}]},
                       extra={"files/0": b"neu\n", "files/1/a/b.txt": b"b\n"})
    run(cli, "plugin", "import", str(pkg), "--json")
    run(cli, "plugin", "import", str(pkg), tree=True)
    run(cli, "plugin", "import", str(pkg), "--yes", "--json", tree=True)
    run(cli, "plugin", "import", str(pkg), "--yes", "--json")
    run(cli, "plugin", "import", str(pkg), "--yes", "--force", "--enable", "--json", tree=True)
    shutil.rmtree(PLUGINS / "neu")
    run(cli, "plugin", "import", str(pkg), "--yes", "--files", "--no-settings", tree=True)
    (HOME / "ziel/datei.txt").write_text("anders\n")
    os.utime(HOME / "ziel/datei.txt", (FIXED_TIME, FIXED_TIME))
    run(cli, "plugin", "import", str(pkg), "--yes", "--force", "--files", "--settings", "--json", tree=True)
    run(cli, "plugin", "import", str(pkg), "--yes", "--force", "--files", "--overwrite-files", "--json", tree=True)

    LOG.append("# Versionen")
    for old, new in (("1.0.0", "1.0.1"), ("1.0.1", "1.0.0"), ("1.0.0", "1.0.0"), ("1.0", "1.0.0"), ("1.10", "1.9"), ("1.0-rc", "1.0-rc2")):
        fresh(extra=False)
        write_json(PLUGINS / "neu/plugin.json", {**NEW, "version": old})
        pkg = make_package(d / "v.dip" if d.exists() else HOME / "v.dip", {"plugin.json": {**NEW, "version": new}})
        run(cli, "plugin", "import", str(pkg), "--yes", "--json", tree=True)

    LOG.append("# Komponenten")
    fresh(extra=False)
    d.mkdir()
    pkg = make_package(d / "c.dip", {"plugin.json": {"id": "c1", "name": "C", "api": 1, "parent": "good"}})
    alone = make_package(d / "a.dip", {"plugin.json": {"id": "a1", "name": "A", "api": 1}})
    run(cli, "plugin", "import", str(pkg), "--yes", "--parent", "anders", "--json")
    run(cli, "plugin", "import", str(pkg), "--yes", "--parent", "good", "--json", tree=True)
    run(cli, "plugin", "import", str(alone), "--yes", "--parent", "good", "--json")

    LOG.append("# Einstellungs-Dateien")
    fresh()
    d.mkdir()
    settings = d / "e.json"
    settings.write_text(json.dumps({"format": "dynamic-island-plugin-settings", "plugin": {"id": "good"}, "settings": {"a": 9, "z": 1, "y": 2, "b": "ä"}}))
    run(cli, "plugin", "import", str(settings), "--json")
    run(cli, "plugin", "import", str(settings), "--yes", "--json", tree=True)
    settings.write_text("{kaputt")
    run(cli, "plugin", "import", str(settings), "--yes", "--json")
    settings.write_text(json.dumps({"format": "x"}))
    run(cli, "plugin", "import", str(settings), "--yes", "--json")
    settings.write_text(json.dumps({"format": "dynamic-island-plugin-settings", "plugin": {"id": "gibtsnicht"}}))
    run(cli, "plugin", "import", str(settings), "--yes", "--json")
    run(cli, "plugin", "import", "p/keine.json", "--yes", "--json")

    LOG.append("# Paket der anderen Fassung")
    fresh()
    d.mkdir()
    subprocess.run(other + ["plugin", "export", "good", "-o", str(d) + "/", "--json"], env=ENV, cwd=HOME, capture_output=True, check=True)
    foreign = d / "good-1.2.0.dip"
    run(cli, "plugin", "validate", str(foreign), "--json")
    shutil.rmtree(PLUGINS / "good")
    shutil.rmtree(HOME / ".local/share/good")
    run(cli, "plugin", "import", str(foreign), "--yes", "--files", "--overwrite-files", "--settings", "--json", tree=True)


def scenario_remove_new(cli, _other):
    LOG.append("=== remove und new")
    fresh()
    run(cli, "plugin", "remove", "good", "--json")
    run(cli, "plugin", "remove", "good", "--yes", "--keep-settings", "--json", tree=True)
    run(cli, "plugin", "remove", "gibtsnicht", "--yes", "--json")
    run(cli, "plugin", "remove", "kern", "--yes", "--json")
    run(cli, "plugin", "remove", "kern", "--yes", "--force", tree=True)
    run(cli, "plugin", "remove", "donor", "--yes", "--json", tree=True)
    run(cli, "plugin", "remove", "badjson", "--yes", "--json", tree=True)
    run(cli, "plugin", "new", "mein-neues-2x", "--json", tree=True)
    run(cli, "plugin", "new", "mit-name", "--name", "Mein Ä", "--author", "Jemand", tree=True)
    run(cli, "plugin", "new", "mit-name", "--json")
    run(cli, "plugin", "new", "GROSS", "--json")
    shutil.rmtree(PLUGINS / "_example")
    run(cli, "plugin", "new", "ohne-vorlage", "--json")
    LOG.append("# Rueckfragen im Terminal")
    fresh()
    run_pty(cli, "n", "plugin", "remove", "donor")
    run_pty(cli, "j", "plugin", "remove", "donor")
    run_pty(cli, "YES", "plugin", "remove", "comp")
    d = HOME / "p"
    d.mkdir()
    pkg = make_package(d / "neu.dip", {"plugin.json": NEW})
    run_pty(cli, "nein", "plugin", "import", str(pkg))
    run_pty(cli, "ja", "plugin", "import", str(pkg))


def scenario_real_plugins(cli, other):
    LOG.append("=== echte Plugins (Kopie)")
    fresh(extra=False)
    shutil.rmtree(PLUGINS)
    shutil.copytree(REAL_PLUGINS, PLUGINS)
    for path in PLUGINS.rglob("*"):
        if not path.is_symlink():
            os.utime(path, (FIXED_TIME, FIXED_TIME))
    run(cli, "plugin", "list")
    run(cli, "plugin", "list", "--json")
    out = HOME / "aus"
    out.mkdir()
    ids = sorted(p.name for p in PLUGINS.iterdir() if p.is_dir() and not p.name.startswith(("_", ".")))
    for pid in ids:
        run(cli, "plugin", "info", pid)
        run(cli, "plugin", "info", pid, "--json")
        run(cli, "plugin", "validate", str(PLUGINS / pid), "--json")
        run(cli, "plugin", "export", pid, "-o", "aus/", "--json")
        package = next(out.glob(f"{pid}-*.dip"))
        inspect(package)
        LOG.append("# dieselbe Fassung importiert es, danach die andere")
        run(cli, "plugin", "validate", str(package), "--json")
        res = subprocess.run(other + ["plugin", "validate", str(package), "--json"], env=ENV, cwd=HOME, capture_output=True, text=True)
        LOG.append(f"  andere Fassung: exit {res.returncode} {normalise(res.stdout).strip()}")
        run(cli, "plugin", "import", str(package), "--yes", "--force", "--json")
        package.unlink()
    snapshot()


def scenario_passthrough(cli, _other):
    LOG.append("=== Weiterreichen an Python")
    fresh()
    for args in ([], ["--help"], ["shell", "--help"], ["plugin"], ["plugin", "--help"], ["plugin", "list", "--help"], ["plugin", "list", "-h"],
                 ["plugin", "list", "--bogus"], ["plugin", "bogus"], ["plugin", "lis"], ["plugin", "info"], ["plugin", "list", "--js"],
                 ["plugin", "import", "x.dip", "--ye", "--json"], ["plugin", "export", "good", "--output=aus/x.dip", "--json"], ["scheme", "list", "-m"],
                 ["toggle"], ["bogus"], ["emoji", "--help"], ["wallpaper", "--help"], ["record", "--help"], ["plugin", "validate", "~root/x", "--json"]):
        run(cli, *args)


SCENARIOS = [scenario_list_info, scenario_enable, scenario_validate, scenario_bad_packages, scenario_export, scenario_import,
             scenario_remove_new, scenario_real_plugins, scenario_passthrough]


def main():
    assert_sandbox()
    out, this, other = sys.argv[1], [sys.argv[2]], [sys.argv[3]]
    for scenario in SCENARIOS:
        scenario(this, other)
    with open(out, "w") as f:
        f.write("\n".join(LOG) + "\n")


if __name__ == "__main__":
    main()
