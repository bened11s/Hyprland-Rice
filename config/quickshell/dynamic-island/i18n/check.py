#!/usr/bin/env python3
"""Prueft i18n/en.js gegen die Texte im Code.

    python i18n/check.py            fehlende Uebersetzungen (I18n.tr("…") ohne Eintrag)
    python i18n/check.py --unused   dazu Eintraege, die kein Literal im Code mehr nutzt

Erfasst nur Literale direkt in I18n.tr(...). Texte, die ueber eine Variable
kommen (Config.meta, plugin.json, Keybind-Beschreibungen), meldet die Shell
selbst im Log ("i18n: keine Uebersetzung fuer …"), sobald sie angezeigt werden.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CALL = re.compile(r'I18n\.tr\(\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')\s*\)')


def unquote(lit: str) -> str:
    if lit[0] == "'":
        lit = '"' + lit[1:-1].replace('\\\'', "'").replace('"', '\\"') + '"'
    return json.loads(lit)


def load_dict() -> dict:
    src = (ROOT / "i18n" / "en.js").read_text()
    body = src[src.index("{"):src.rindex("}") + 1]
    # JS-Objekt -> JSON: Kommentare und haengende Kommas raus
    body = re.sub(r"^\s*//.*$", "", body, flags=re.M)
    body = re.sub(r",(\s*})", r"\1", body)
    return json.loads(body)


def main() -> int:
    strings = load_dict()
    used: dict[str, str] = {}
    for f in sorted(ROOT.rglob("*.qml")):
        if f.name == "I18n.qml":
            continue
        for m in CALL.finditer(f.read_text()):
            used.setdefault(unquote(m.group(1)), str(f.relative_to(ROOT)))

    missing = {k: v for k, v in used.items() if k not in strings}
    for k, f in sorted(missing.items(), key=lambda kv: kv[1]):
        print(f"fehlt   {f}: {k!r}")
    if "--unused" in sys.argv:
        for k in sorted(set(strings) - set(used)):
            print(f"unbenutzt (oder indirekt): {k!r}")
    print(f"{len(used)} Texte im Code, {len(strings)} Uebersetzungen, {len(missing)} fehlen")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
