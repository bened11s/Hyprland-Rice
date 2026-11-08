#!/usr/bin/env python3
"""Ordner-Looks fuer fastfetch bearbeiten (Editor des Terminal-Plugins).

Eigenstaendig, laeuft per `python3 -I`. Jede Operation schreibt genau eine
JSON-Zeile auf stdout: {"ok": true, ...} oder {"ok": false, "error": "..."}.

  list                          alle Looks mit Titel, Palette, Karten, Rohmodus
  get ID                        look.json eines Looks (ohne look.json: frisch
                                aus den .jsonc importiert, nicht gespeichert)
  save ID [--force]             look.json (--json oder stdin) speichern und config/
                                compact/mini.jsonc daraus erzeugen
  import ID                     look.json aus den vorhandenen .jsonc anlegen
                                (Originale nach .orig/)
  preview SIZE [--raw ID]       look.json (--json/stdin, auch ungespeichert) mit
                                fastfetch rendern -> Zeilen mit Farbsegmenten;
                                --raw: stattdessen die Datei SIZE.jsonc von ID
                                ("scheme" = Schema-Variante aus dem Theme)
  check ID                      alle Groessen rendern, Budget-Ueberlauf melden
  new ID --from LOOK [--title T] neuen Look als Kopie anlegen
  delete ID                     Look-Ordner in den Papierkorb (nicht miku)
  cards ID                      Logo-Karten des Looks
  card-make ID BILD [FARBE]     Karte 600x800 aus einem Bild (Rahmen: FARBE,
                                "@name" aus der Palette oder #rrggbb)
  card-remove ID NAME           Karte in den Papierkorb
  raw-get ID SIZE               Datei SIZE.jsonc als Text
  raw-set ID SIZE               Text (--text/stdin) als eigene Datei speichern
                                (Groesse wird nicht mehr erzeugt)
  raw-off ID SIZE [--adopt]     Groesse wieder erzeugen; --adopt uebernimmt
                                vorher die eigene Datei in look.json
  palette BILD [N]              Farbvorschlaege aus einem Bild: Rollen + N Farben
  scheme-palette                Farben des aktuellen Schemas

Look-IDs sind Ordnernamen unter ~/.config/fastfetch (klein, wie der
Wallpaper-Ordner); "miku" ist der Wurzel-Look (Karten in Pictures/tactical).

look.json:
  title     Anzeigename
  palette   {name: "#rrggbb"}
  base      fastfetch-Konfiguration ohne modules (Groesse "config")
  sizes     {config|compact|mini: {patch: {...}, raw: bool}}
  rows      [{m: Modul oder "break", sizes: {SIZE: false | Patch | {"=": Wert}}}]
  generated {SIZE: sha256 der zuletzt erzeugten Datei}

Farben stehen in Texten als Markup statt als ANSI-Escape:
  <@name> Palettenfarbe, <#rrggbb> feste Farbe, <b> fett, <i> kursiv,
  <d> blass, <u> unterstrichen, </> zuruecksetzen, mehrere mit Leerzeichen
  (<b @primary>), << ist ein woertliches "<". In Farbfeldern (display.color,
  bar.color, keyColor …) steht nur der Inhalt ("@primary", "b @accent").
Patches mischen sich rekursiv in Objekte; null loescht einen Schluessel,
Listen und andere Werte ersetzen.
"""

import copy
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

HOME = Path.home()
FASTFETCH = Path(os.environ.get("DYNAMIC_ISLAND_FASTFETCH_DIR") or HOME / ".config/fastfetch")
STATE = Path(os.environ.get("DYNAMIC_ISLAND_STATE_DIR") or HOME / ".local/state/dynamic-island")

SIZES = ("config", "compact", "mini")
# Budgets aus fish/functions/fastfetch.fish (Text neben der Karte)
BUDGET = {"config": (64, 23), "compact": (50, 19), "mini": (32, 7)}
ROLE_NAMES = {
    ("display", "color", "keys"): "primary",
    ("display", "color", "separator"): "accent",
    ("display", "bar", "color", "elapsed"): "highlight",
    ("display", "bar", "color", "total"): "muted",
}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,31}$")


class Fail(Exception):
    pass


# ---- JSONC ----

def strip_jsonc(text: str) -> str:
    """// und /* */ ausserhalb von Strings entfernen, Kommas vor ] und } auch."""
    out, i, n = [], 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[\]}])", r"\1", "".join(out))


def load_jsonc(path: Path):
    try:
        return json.loads(strip_jsonc(path.read_text()))
    except json.JSONDecodeError as e:
        raise Fail(f"{path.name}: kein gueltiges JSONC ({e.msg}, Zeile {e.lineno})")


# ---- Farben / Markup ----

ESC_RE = re.compile(r"\x1b\[([0-9;]*)m")
PARAMS_RE = re.compile(r"^(\d+;)*(38|48);2;\d+;\d+;\d+(;\d+)*$")
TAG_RE = re.compile(r"<<|<([^<>]*)>")
PART_RE = re.compile(r"^(/|b|d|i|u|\d+|(bg)?@[A-Za-z][A-Za-z0-9_-]*|(bg)?#[0-9a-fA-F]{6})$")
SIMPLE = {0: "/", 1: "b", 2: "d", 3: "i", 4: "u"}


def hexc(rgb) -> str:
    return "#%02x%02x%02x" % tuple(rgb)


def rgb_of(h: str):
    h = h.lstrip("#")
    return [int(h[k:k + 2], 16) for k in (0, 2, 4)]


def params_to_parts(params: str, names: dict) -> list[str]:
    """"1;38;2;r;g;b" -> ["b", "@primary"]; names: "#hex" -> Palettenname."""
    if params == "":
        return []
    nums = [int(x) if x else 0 for x in params.split(";")]
    parts, k = [], 0
    while k < len(nums):
        v = nums[k]
        if v in (38, 48) and k + 4 < len(nums) and nums[k + 1] == 2:
            h = hexc(nums[k + 2:k + 5])
            ref = "@" + names[h] if h in names else h
            parts.append(("bg" if v == 48 else "") + ref)
            k += 5
        else:
            parts.append(SIMPLE.get(v, str(v)))
            k += 1
    return parts


def parts_to_params(parts: list[str], palette: dict) -> str:
    out = []
    for p in parts:
        bg = p.startswith("bg") and len(p) > 2 and p[2] in "@#"
        q = p[2:] if bg else p
        if q.startswith("@"):
            if q[1:] not in palette:
                raise Fail(f"unbekannte Palettenfarbe: {q}")
            q = palette[q[1:]]
        if q.startswith("#"):
            out.append(("48" if bg else "38") + ";2;" + ";".join(map(str, rgb_of(q))))
        elif q in ("/", "b", "d", "i", "u"):
            out.append(str({"/": 0, "b": 1, "d": 2, "i": 3, "u": 4}[q]))
        elif q.isdigit():
            out.append(q)
        else:
            raise Fail(f"unbekanntes Markup: <{p}>")
    return ";".join(out)


def to_markup(s: str, names: dict) -> str:
    res, pos = [], 0
    for m in ESC_RE.finditer(s):
        res.append(s[pos:m.start()].replace("<", "<<"))
        res.append("<" + " ".join(params_to_parts(m.group(1), names)) + ">")
        pos = m.end()
    res.append(s[pos:].replace("<", "<<"))
    return "".join(res)


def from_markup(s: str, palette: dict) -> str:
    def sub(m):
        if m.group(0) == "<<":
            return "<"
        inner = m.group(1).split()
        if not all(PART_RE.match(p) for p in inner):
            raise Fail(f"unbekanntes Markup: {m.group(0)}")
        return "\x1b[" + parts_to_params(inner, palette) + "m"
    return TAG_RE.sub(sub, s)


def is_color_path(path: tuple) -> bool:
    return any("color" in str(p).lower() for p in path)


def walk_strings(v, fn, path=()):
    if isinstance(v, dict):
        return {k: walk_strings(x, fn, path + (k,)) for k, x in v.items()}
    if isinstance(v, list):
        return [walk_strings(x, fn, path + (i,)) for i, x in enumerate(v)]
    if isinstance(v, str):
        return fn(v, path)
    return v


def encode(v, names: dict):
    """fastfetch-Werte -> look.json-Form (Markup, Palettennamen)."""
    def fn(s, path):
        if is_color_path(path) and PARAMS_RE.match(s):
            return " ".join(params_to_parts(s, names))
        return to_markup(s, names)
    return walk_strings(v, fn)


def decode(v, palette: dict):
    """look.json-Form -> fastfetch-Werte."""
    def fn(s, path):
        if is_color_path(path) and s and all(PART_RE.match(p) for p in s.split()) \
                and any(p.lstrip("bg")[:1] in "@#" for p in s.split()):
            return parts_to_params(s.split(), palette)
        return from_markup(s, palette)
    return walk_strings(v, fn)


def collect_colors(v, counts: dict, roles: dict, path=()):
    if isinstance(v, dict):
        for k, x in v.items():
            collect_colors(x, counts, roles, path + (k,))
    elif isinstance(v, list):
        for i, x in enumerate(v):
            collect_colors(x, counts, roles, path + (i,))
    elif isinstance(v, str):
        found = []
        for m in ESC_RE.finditer(v):
            found.append(m.group(1))
        if is_color_path(path) and PARAMS_RE.match(v):
            found.append(v)
            if path in ROLE_NAMES:
                for h in triplets(v):
                    roles.setdefault(ROLE_NAMES[path], h)
        for params in found:
            for h in triplets(params):
                counts[h] = counts.get(h, 0) + 1


def triplets(params: str):
    nums = [int(x) if x else 0 for x in params.split(";")]
    k = 0
    while k < len(nums):
        if nums[k] in (38, 48) and k + 4 < len(nums) and nums[k + 1] == 2:
            yield hexc(nums[k + 2:k + 5])
            k += 5
        else:
            k += 1


# ---- Patches ----

def merge(base, patch):
    if not isinstance(base, dict) or not isinstance(patch, dict):
        return copy.deepcopy(patch)
    out = copy.deepcopy(base)
    for k, v in patch.items():
        if v is None:
            out.pop(k, None)
        elif isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def diff(base, target):
    """Patch, mit dem merge(base, patch) == target (beides Objekte)."""
    p = {}
    for k in base:
        if k not in target:
            p[k] = None
    for k, v in target.items():
        if k not in base:
            p[k] = copy.deepcopy(v)
        elif isinstance(v, dict) and isinstance(base[k], dict):
            d = diff(base[k], v)
            if d:
                p[k] = d
        elif v != base[k] or type(v) is not type(base[k]):
            p[k] = copy.deepcopy(v)
    return p


def row_value(row: dict, size: str):
    """Modul der Zeile in SIZE, oder None wenn sie dort fehlt."""
    s = (row.get("sizes") or {}).get(size)
    if s is False:
        return None
    m = row["m"]
    if s is None:
        return copy.deepcopy(m)
    if isinstance(s, dict) and "=" in s:
        return copy.deepcopy(s["="])
    if isinstance(m, dict) and isinstance(s, dict):
        return merge(m, s)
    raise Fail("ungueltiger Zeilen-Patch")


def row_patch(m, v):
    if v == m:
        return None
    if isinstance(m, dict) and isinstance(v, dict) and "=" not in v:
        return diff(m, v)
    return {"=": v}


# ---- Pfade ----

def look_dir(lid: str) -> Path:
    if lid == "miku":
        return FASTFETCH
    if not ID_RE.match(lid) or lid in ("pictures", ".orig"):
        raise Fail(f"ungueltige Look-ID: {lid}")
    return FASTFETCH / lid


def cards_dir(lid: str) -> Path:
    return FASTFETCH / "Pictures/tactical" if lid == "miku" else look_dir(lid) / "Pictures"


def look_ids() -> list[str]:
    ids = ["miku"] if (FASTFETCH / "config.jsonc").is_file() else []
    if FASTFETCH.is_dir():
        for d in sorted(FASTFETCH.iterdir(), key=lambda p: p.name.lower()):
            if d.is_dir() and d.name != "Pictures" and not d.name.startswith(".") \
                    and ((d / "config.jsonc").is_file() or (d / "look.json").is_file()):
                ids.append(d.name)
    return ids


def default_title(lid: str) -> str:
    if lid == "miku":
        return "Vocaloid"
    return " ".join(w.capitalize() for w in lid.replace("_", "-").split("-"))


# ---- Import ----

def signature(m) -> str:
    """Zum Ausrichten: Modultyp, bei custom dazu das erste sichtbare Zeichen
    (Kopfzeile, Abschnitt, Linie und Statuszeile beginnen verschieden)."""
    if isinstance(m, str):
        return m
    t = str(m.get("type", "?"))
    if t == "custom":
        text = TAG_RE.sub("", str(m.get("format", ""))).strip()
        t += ":" + text[:1]
    return t


def import_files(lid: str, title: str | None = None) -> dict:
    d = look_dir(lid)
    raw = {}
    for size in SIZES:
        p = d / f"{size}.jsonc"
        if p.is_file():
            raw[size] = load_jsonc(p)
    if "config" not in raw:
        raise Fail(f"{lid}: config.jsonc fehlt")
    for size in SIZES:
        raw.setdefault(size, copy.deepcopy(raw["config"]))

    counts, roles = {}, {}
    for size in SIZES:
        collect_colors(raw[size], counts, roles)
    palette, names = {}, {}
    for role in ("primary", "accent", "highlight", "muted"):
        h = roles.get(role)
        if h and h not in names:
            names[h] = role
            palette[role] = h
    extra = 1
    for h, _ in sorted(counts.items(), key=lambda kv: -kv[1]):
        if h not in names:
            name = "extra" if extra == 1 else f"extra{extra}"
            extra += 1
            names[h] = name
            palette[name] = h

    enc = {s: encode(raw[s], names) for s in SIZES}
    mods = {s: enc[s].pop("modules", []) for s in SIZES}
    base = enc["config"]

    # Zeilen ueber die Groessen ausrichten: jede Groesse behaelt ihre Reihenfolge
    rows = [{"m": m, "vals": {"config": m}} for m in mods["config"]]
    for size in ("compact", "mini"):
        seq = mods[size]
        sm = difflib.SequenceMatcher(None, [signature(r["m"]) for r in rows],
                                     [signature(m) for m in seq], autojunk=False)
        merged = []
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == "equal":
                for k in range(i2 - i1):
                    rows[i1 + k]["vals"][size] = seq[j1 + k]
                merged.extend(rows[i1:i2])
            else:
                merged.extend(rows[i1:i2])
                merged.extend({"m": m, "vals": {size: m}} for m in seq[j1:j2])
        rows = merged

    out_rows = []
    for r in rows:
        sizes = {}
        for size in SIZES:
            if size not in r["vals"]:
                sizes[size] = False
            else:
                p = row_patch(r["m"], r["vals"][size])
                if p is not None:
                    sizes[size] = p
        row = {"m": r["m"]}
        if sizes:
            row["sizes"] = sizes
        out_rows.append(row)

    look = {
        "version": 1,
        "title": title or default_title(lid),
        "palette": palette,
        "base": base,
        "sizes": {s: ({"patch": diff(base, enc[s])} if s != "config" and diff(base, enc[s]) else {}) for s in SIZES},
        "rows": out_rows,
    }
    return look


# ---- Erzeugen ----

def validate(look: dict):
    if not isinstance(look, dict) or look.get("version") != 1:
        raise Fail("look.json: version 1 erwartet")
    pal = look.get("palette")
    if not isinstance(pal, dict):
        raise Fail("look.json: palette fehlt")
    for k, v in pal.items():
        if not NAME_RE.match(k) or not re.match(r"^#[0-9a-fA-F]{6}$", str(v)):
            raise Fail(f"Palette: ungueltiger Eintrag {k}={v}")
    if not isinstance(look.get("base"), dict) or not isinstance(look.get("rows"), list):
        raise Fail("look.json: base/rows fehlen")
    for r in look["rows"]:
        if not isinstance(r, dict) or not isinstance(r.get("m"), (dict, str)):
            raise Fail("look.json: Zeile ohne m")


def build(look: dict, size: str) -> dict:
    """fastfetch-Konfiguration (als Objekt) fuer eine Groesse."""
    validate(look)
    sz = (look.get("sizes") or {}).get(size) or {}
    conf = merge(look["base"], sz.get("patch") or {})
    conf.pop("modules", None)
    conf["modules"] = [v for v in (row_value(r, size) for r in look["rows"]) if v is not None]
    return decode(conf, look["palette"])


def dump(conf: dict, header: str) -> str:
    """Wie die handgeschriebenen Dateien: Bloecke eingerueckt, Module einzeilig."""
    head = {k: v for k, v in conf.items() if k != "modules"}
    mods = '    "modules": [\n' + ",\n".join("        " + json.dumps(m, ensure_ascii=False)
                                           for m in conf["modules"]) + "\n    ]"
    if not head:
        return header + "{\n" + mods + "\n}\n"
    return header + json.dumps(head, indent=4, ensure_ascii=False)[:-2] + ",\n" + mods + "\n}\n"


def header_for(look: dict, size: str) -> str:
    return (f"// {look.get('title', '')} · {size} – erzeugt aus look.json (Terminal-Looks-Editor).\n"
            f"// Aenderungen hier gehen beim naechsten Speichern verloren; eigene Datei: im Editor \"Eigene Datei\".\n")


def sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def write_atomic(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def backup_originals(d: Path):
    orig = d / ".orig"
    if orig.exists():
        return
    orig.mkdir()
    for size in SIZES:
        p = d / f"{size}.jsonc"
        if p.is_file():
            shutil.copy2(p, orig / p.name)


def render_files(lid: str, look: dict, force: bool = False) -> list[str]:
    d = look_dir(lid)
    gen = dict(look.get("generated") or {})
    conflicts = []
    texts = {}
    for size in SIZES:
        if ((look.get("sizes") or {}).get(size) or {}).get("raw"):
            continue
        p = d / f"{size}.jsonc"
        if p.is_file() and not force and gen.get(size) and sha(p.read_text()) != gen[size]:
            conflicts.append(size)
        texts[size] = dump(build(look, size), header_for(look, size))
    if conflicts:
        raise Fail("von Hand geaendert seit dem letzten Speichern: " + ", ".join(f"{s}.jsonc" for s in conflicts)
                   + " (als eigene Datei uebernehmen oder mit --force ueberschreiben)")
    for size, text in texts.items():
        write_atomic(d / f"{size}.jsonc", text)
        gen[size] = sha(text)
    look["generated"] = gen
    return list(texts)


def read_look(lid: str) -> tuple[dict, bool]:
    p = look_dir(lid) / "look.json"
    if p.is_file():
        try:
            return json.loads(p.read_text()), True
        except json.JSONDecodeError as e:
            raise Fail(f"look.json kaputt: {e}")
    return import_files(lid), False


def write_look(lid: str, look: dict):
    write_atomic(look_dir(lid) / "look.json", json.dumps(look, indent=2, ensure_ascii=False) + "\n")


def save(lid: str, look: dict, force: bool = False) -> dict:
    validate(look)
    d = look_dir(lid)
    if not (d / "look.json").is_file():
        backup_originals(d) if d.is_dir() else d.mkdir(parents=True)
        # Erstes Speichern: die Handarbeit wird bewusst ersetzt
        force = True
    written = render_files(lid, look, force)
    write_look(lid, look)
    return {"written": written, "generated": look["generated"]}


# ---- Vorschau ----

def cell_width(s: str) -> int:
    w = 0
    for ch in s:
        if unicodedata.combining(ch) or unicodedata.category(ch) in ("Mn", "Me", "Cf"):
            continue
        w += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return w


SGR_ANY = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")


def ansi_lines(text: str) -> list[list[dict]]:
    """ANSI-Ausgabe -> Zeilen aus Segmenten {t, fg, bg, b, i, d, u}."""
    lines = []
    st = {"fg": "", "bg": "", "b": False, "i": False, "d": False, "u": False}
    for raw in text.split("\n"):
        segs, pos = [], 0

        def push(t):
            if t:
                seg = {"t": t, **{k: v for k, v in st.items() if v}}
                if segs and {k: v for k, v in segs[-1].items() if k != "t"} == {k: v for k, v in seg.items() if k != "t"}:
                    segs[-1]["t"] += t
                else:
                    segs.append(seg)

        for m in SGR_ANY.finditer(raw):
            push(raw[pos:m.start()])
            pos = m.end()
            if m.group(2) != "m":
                continue
            nums = [int(x) if x.isdigit() else 0 for x in (m.group(1) or "0").split(";")]
            k = 0
            while k < len(nums):
                v = nums[k]
                if v == 0:
                    st.update(fg="", bg="", b=False, i=False, d=False, u=False)
                elif v == 1: st["b"] = True
                elif v == 2: st["d"] = True
                elif v == 3: st["i"] = True
                elif v == 4: st["u"] = True
                elif v == 22: st["b"] = st["d"] = False
                elif v == 23: st["i"] = False
                elif v == 24: st["u"] = False
                elif v == 39: st["fg"] = ""
                elif v == 49: st["bg"] = ""
                elif v in (38, 48) and k + 4 < len(nums) and nums[k + 1] == 2:
                    st["fg" if v == 38 else "bg"] = hexc(nums[k + 2:k + 5])
                    k += 4
                elif v in (38, 48) and k + 2 < len(nums) and nums[k + 1] == 5:
                    st["fg" if v == 38 else "bg"] = xterm256(nums[k + 2])
                    k += 2
                elif 30 <= v <= 37 or 90 <= v <= 97:
                    st["fg"] = ANSI16[(v - 30) if v < 90 else (v - 82)]
                elif 40 <= v <= 47 or 100 <= v <= 107:
                    st["bg"] = ANSI16[(v - 40) if v < 100 else (v - 92)]
                k += 1
        push(raw[pos:])
        lines.append(segs)
    while lines and not lines[-1]:
        lines.pop()
    return lines


ANSI16 = ["#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
          "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff"]


def xterm256(n: int) -> str:
    if n < 16:
        return ANSI16[n]
    if n < 232:
        n -= 16
        lv = [0, 95, 135, 175, 215, 255]
        return hexc([lv[n // 36], lv[(n // 6) % 6], lv[n % 6]])
    g = 8 + (n - 232) * 10
    return hexc([g, g, g])


def run_fastfetch(conf: dict) -> str:
    with tempfile.NamedTemporaryFile("w", suffix=".jsonc", delete=False) as f:
        f.write(json.dumps(conf, ensure_ascii=False))
        path = f.name
    try:
        r = subprocess.run(["fastfetch", "-c", path, "--logo", "none", "--pipe", "false"],
                           capture_output=True, text=True, timeout=15,
                           env={**os.environ, "COLUMNS": "400"})
    except FileNotFoundError:
        raise Fail("fastfetch nicht gefunden")
    except subprocess.TimeoutExpired:
        raise Fail("fastfetch antwortet nicht")
    finally:
        os.unlink(path)
    if r.returncode != 0 and not r.stdout:
        raise Fail("fastfetch: " + (r.stderr.strip().splitlines() or ["Fehler"])[-1])
    return r.stdout


def preview_conf(conf: dict, size: str) -> dict:
    conf = dict(conf)
    conf["logo"] = {"type": "none"}
    lines = ansi_lines(run_fastfetch(conf))
    cols, rows = BUDGET[size]
    widths = [sum(cell_width(s["t"]) for s in l) for l in lines]
    width = max(widths, default=0)
    return {"size": size, "lines": lines, "width": width, "height": len(lines),
            "budget": {"cols": cols, "rows": rows},
            "overflow": [i for i, w in enumerate(widths) if w > cols],
            "tooTall": len(lines) > rows}


def preview_raw(lid: str, size: str) -> dict:
    """Datei so, wie das Terminal sie liest; "scheme" = die aus dem
    Farbschema gerenderten Vorlagen (templates/fastfetch*.jsonc)."""
    if lid == "scheme":
        p = STATE / "theme" / ("fastfetch.jsonc" if size == "config" else f"fastfetch-{size}.jsonc")
        if not p.is_file():
            raise Fail("Schema-fastfetch fehlt (noch kein Theme gerendert)")
        return preview_conf(load_jsonc(p), size)
    p = look_dir(lid) / f"{size}.jsonc"
    if not p.is_file():
        raise Fail(f"{lid}: {size}.jsonc fehlt")
    return preview_conf(load_jsonc(p), size)


# ---- Karten ----

def card_list(lid: str) -> list[dict]:
    d = cards_dir(lid)
    return [{"name": p.name, "path": str(p)} for p in sorted(d.glob("*.png"), key=lambda p: p.name.lower())] \
        if d.is_dir() else []


def resolve_color(spec: str, palette: dict) -> str:
    if spec.startswith("@"):
        if spec[1:] not in palette:
            raise Fail(f"unbekannte Palettenfarbe: {spec}")
        return palette[spec[1:]]
    if re.match(r"^#?[0-9a-fA-F]{6}$", spec):
        return "#" + spec.lstrip("#")
    raise Fail(f"ungueltige Farbe: {spec}")


def card_make(lid: str, image: str, color: str) -> dict:
    src = Path(image).expanduser()
    if not src.is_file():
        raise Fail(f"Bild fehlt: {image}")
    look, _ = read_look(lid)
    col = resolve_color(color or ("@primary" if "primary" in look["palette"] else "#ffffff"), look["palette"])
    d = cards_dir(lid)
    d.mkdir(parents=True, exist_ok=True)
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", src.stem).strip("-") or "karte"
    out, n = d / f"{stem}.png", 2
    while out.exists():
        out, n = d / f"{stem}-{n}.png", n + 1
    tmp = out.with_name(out.name + ".tmp.png")
    # wie fish/functions/__fastfetch_card.fish
    r = subprocess.run(["magick", str(src), "-resize", "600x800^", "-gravity", "center", "-extent", "600x800",
                        "(", "-size", "600x800", "xc:none", "-fill", "white", "-draw", "roundrectangle 0,0 599,799 30,30", ")",
                        "-compose", "DstIn", "-composite", "-compose", "over",
                        "-fill", "none", "-stroke", col, "-strokewidth", "5", "-draw", "roundrectangle 3,3 596,796 28,28",
                        str(tmp)], capture_output=True, text=True, timeout=60)
    if r.returncode != 0 or not tmp.is_file():
        tmp.unlink(missing_ok=True)
        raise Fail("magick: " + (r.stderr.strip().splitlines() or ["Fehler"])[-1])
    os.replace(tmp, out)
    return {"name": out.name, "path": str(out)}


def trash(path: Path):
    r = subprocess.run(["gio", "trash", str(path)], capture_output=True, text=True)
    if r.returncode != 0:
        raise Fail("Papierkorb: " + (r.stderr.strip() or "Fehler"))


# ---- Paletten-Vorschlaege ----

def palette_from_image(image: str, n: int) -> dict:
    """Farbvorschlaege: Rollen (primary/accent/highlight/muted) plus Liste.
    Kraeftige, helle Farben werden bevorzugt – Wallpaper sind oft dunkel,
    der Text muss auf dem Terminal-Hintergrund lesbar bleiben."""
    import colorsys
    src = Path(image).expanduser()
    if not src.is_file():
        raise Fail(f"Bild fehlt: {image}")
    r = subprocess.run(["magick", str(src), "-resize", "200x200", "-colors", "24",
                        "-format", "%c", "histogram:info:-"], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise Fail("magick: " + (r.stderr.strip().splitlines() or ["Fehler"])[-1])
    cols = []
    for line in r.stdout.splitlines():
        m = re.search(r"^\s*(\d+):.*?#([0-9A-Fa-f]{6})", line)
        if m:
            h = "#" + m.group(2).lower()
            hh, ss, vv = colorsys.rgb_to_hsv(*(x / 255 for x in rgb_of(h)))
            cols.append({"hex": h, "n": int(m.group(1)), "h": hh, "s": ss, "v": vv})
    if not cols:
        raise Fail("keine Farben gefunden")
    total = sum(c["n"] for c in cols)

    def lift(c, v_min):
        """Zu dunkle Farben aufhellen, Farbton bleibt."""
        v = max(c["v"], v_min)
        return hexc([round(x * 255) for x in colorsys.hsv_to_rgb(c["h"], c["s"], v)])

    def vivid(c):
        return (c["n"] / total) ** 0.35 * c["s"] ** 1.5 * (0.3 + c["v"])

    ranked = sorted(cols, key=vivid, reverse=True)
    roles = {}
    primary = ranked[0]
    roles["primary"] = lift(primary, 0.85)

    def hue_dist(a, b):
        d = abs(a["h"] - b["h"])
        return min(d, 1 - d)
    others = [c for c in ranked[1:] if c["s"] > 0.25]
    accent = max(others, key=lambda c: vivid(c) * (0.2 + hue_dist(c, primary)), default=None)
    if accent:
        roles["accent"] = lift(accent, 0.8)
        rest = [c for c in others if c is not accent]
        third = max(rest, key=lambda c: vivid(c) * (0.2 + min(hue_dist(c, primary), hue_dist(c, accent))), default=None)
        if third:
            roles["highlight"] = lift(third, 0.85)
    greys = sorted(cols, key=lambda c: (c["s"], -c["n"]))
    g = greys[0]
    v = min(max(g["v"], 0.5), 0.7)
    roles["muted"] = hexc([round(x * 255) for x in colorsys.hsv_to_rgb(g["h"], min(g["s"], 0.15), v)])
    seen, out = set(), []
    for c in list(roles.values()) + [lift(c, 0.6) for c in ranked]:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return {"roles": roles, "colors": out[:max(n, len(roles))]}


def scheme_palette() -> dict:
    try:
        data = json.loads((STATE / "scheme.json").read_text())
    except (OSError, json.JSONDecodeError):
        raise Fail("scheme.json fehlt")
    c = data.get("colours") or {}
    out = {}
    for name, key in (("primary", "primary"), ("accent", "tertiary"), ("highlight", "secondary"), ("muted", "outline")):
        if re.match(r"^[0-9a-fA-F]{6}$", str(c.get(key, ""))):
            out[name] = "#" + c[key].lower()
    return out


# ---- Operationen ----

def op_list():
    out = []
    for lid in look_ids():
        d = look_dir(lid)
        managed = (d / "look.json").is_file()
        try:
            look, _ = read_look(lid)
            pal, title = look["palette"], look.get("title") or default_title(lid)
            raw = [s for s in SIZES if ((look.get("sizes") or {}).get(s) or {}).get("raw")]
            err = ""
        except Fail as e:
            pal, title, raw, err = {}, default_title(lid), [], str(e)
        cards = card_list(lid)
        out.append({"id": lid, "title": title, "dir": str(d), "managed": managed, "palette": pal,
                    "raw": raw, "cards": len(cards), "card": cards[0]["path"] if cards else "", "error": err})
    return {"looks": out}


VALUE_OPTS = ("--from", "--title", "--json", "--text", "--raw")


def main(argv):
    if not argv:
        raise Fail("Operation fehlt")
    op, rest = argv[0], argv[1:]
    pos, opts, flags = [], {}, set()
    k = 0
    while k < len(rest):
        a = rest[k]
        if a in VALUE_OPTS:
            if k + 1 >= len(rest):
                raise Fail(f"{a}: Wert fehlt")
            opts[a] = rest[k + 1]
            k += 2
        elif a.startswith("--"):
            flags.add(a)
            k += 1
        else:
            pos.append(a)
            k += 1

    def opt(name):
        return opts.get(name)

    def text_in(name: str) -> str:
        """Eingabe aus --json/--text, sonst stdin (aus QML: Argument)."""
        return opts[name] if name in opts else sys.stdin.read()

    def json_in():
        try:
            return json.loads(text_in("--json"))
        except json.JSONDecodeError as e:
            raise Fail(f"Eingabe ist kein JSON: {e.msg}")

    def need(n):
        if len(pos) < n:
            raise Fail(f"{op}: zu wenige Argumente")

    def size_arg(k):
        need(k + 1)
        if pos[k] not in SIZES:
            raise Fail(f"unbekannte Groesse: {pos[k]}")
        return pos[k]

    if op == "list":
        return op_list()
    if op == "get":
        need(1)
        look, managed = read_look(pos[0])
        return {"look": look, "managed": managed}
    if op == "save":
        need(1)
        return save(pos[0], json_in(), "--force" in flags)
    if op == "import":
        need(1)
        look_dir(pos[0])
        look = import_files(pos[0])
        return save(pos[0], look, True)
    if op == "preview":
        size = size_arg(0)
        if opt("--raw"):
            return preview_raw(opt("--raw"), size)
        return preview_conf(build(json_in(), size), size)
    if op == "check":
        need(1)
        look, _ = read_look(pos[0])
        res = {}
        for size in SIZES:
            raw = ((look.get("sizes") or {}).get(size) or {}).get("raw")
            p = preview_raw(pos[0], size) if raw else preview_conf(build(look, size), size)
            res[size] = {k: p[k] for k in ("width", "height", "budget", "overflow", "tooTall")}
        return {"sizes": res}
    if op == "new":
        need(1)
        lid, src = pos[0], opt("--from") or "miku"
        d = look_dir(lid)
        if lid == "miku" or d.exists():
            raise Fail(f"Look gibt es schon: {lid}")
        look = copy.deepcopy(read_look(src)[0])
        look["title"] = opt("--title") or default_title(lid)
        look.pop("generated", None)
        d.mkdir(parents=True)
        (d / "Pictures").mkdir()
        for size in SIZES:
            if ((look.get("sizes") or {}).get(size) or {}).get("raw"):
                shutil.copy2(look_dir(src) / f"{size}.jsonc", d / f"{size}.jsonc")
        render_files(lid, look, True)
        write_look(lid, look)
        return {"id": lid}
    if op == "delete":
        need(1)
        if pos[0] == "miku":
            raise Fail("der Vocaloid-Look laesst sich nicht loeschen")
        d = look_dir(pos[0])
        if not d.is_dir():
            raise Fail(f"Look fehlt: {pos[0]}")
        trash(d)
        return {}
    if op == "cards":
        need(1)
        look_dir(pos[0])
        return {"cards": card_list(pos[0])}
    if op == "card-make":
        need(2)
        return card_make(pos[0], pos[1], pos[2] if len(pos) > 2 else "")
    if op == "card-remove":
        need(2)
        name = pos[1]
        if "/" in name or name.startswith("."):
            raise Fail(f"ungueltiger Name: {name}")
        p = cards_dir(pos[0]) / name
        if not p.is_file():
            raise Fail(f"Karte fehlt: {name}")
        trash(p)
        return {}
    if op == "raw-get":
        size = size_arg(1)
        p = look_dir(pos[0]) / f"{size}.jsonc"
        return {"text": p.read_text() if p.is_file() else ""}
    if op == "raw-set":
        size = size_arg(1)
        text = text_in("--text")
        try:
            conf = json.loads(strip_jsonc(text))
        except json.JSONDecodeError as e:
            raise Fail(f"kein gueltiges JSONC ({e.msg}, Zeile {e.lineno})")
        if not isinstance(conf, dict):
            raise Fail("JSONC muss ein Objekt sein")
        lid = pos[0]
        look, managed = read_look(lid)
        if not managed:
            backup_originals(look_dir(lid))
        look.setdefault("sizes", {}).setdefault(size, {})["raw"] = True
        write_atomic(look_dir(lid) / f"{size}.jsonc", text if text.endswith("\n") else text + "\n")
        (look.get("generated") or {}).pop(size, None)
        if not managed:
            render_files(lid, look, True)
        write_look(lid, look)
        return {"preview": preview_conf(conf, size)}
    if op == "raw-off":
        size = size_arg(1)
        lid = pos[0]
        look, _ = read_look(lid)
        if "--adopt" in flags:
            fresh = import_files(lid, look.get("title"))
            fresh["sizes"] = {s: dict(fresh["sizes"].get(s) or {}, **({"raw": True} if s != size and
                              ((look.get("sizes") or {}).get(s) or {}).get("raw") else {})) for s in SIZES}
            look = fresh
        else:
            ((look.get("sizes") or {}).get(size) or {}).pop("raw", None)
        (look.get("generated") or {}).pop(size, None)
        render_files(lid, look, True)
        write_look(lid, look)
        return {"look": look}
    if op == "palette":
        need(1)
        return palette_from_image(pos[0], int(pos[1]) if len(pos) > 1 else 8)
    if op == "scheme-palette":
        return {"palette": scheme_palette()}
    raise Fail(f"unbekannte Operation: {op}")


if __name__ == "__main__":
    try:
        res = main(sys.argv[1:])
        print(json.dumps({"ok": True, **res}, ensure_ascii=False))
    except Fail as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
    except Exception as e:  # noqa: BLE001 – eine JSON-Zeile auch bei Fehlern
        print(json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}, ensure_ascii=False))
