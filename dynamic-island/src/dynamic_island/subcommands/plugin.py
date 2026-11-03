"""Plugins der dynamic-island-Shell verwalten: auflisten, an/aus, Import/Export.

Ein Plugin ist ein Ordner ``<shell>/plugins/<id>/`` mit ``plugin.json``
(Format: quickshell/dynamic-island/plugins/README.md). Die Shell findet neue
Ordner selbst (FolderListModel) und liest ``plugins.json`` per Watcher neu –
die CLI muss ihr also nichts mitteilen.

Austauschformate:

``<id>-<version>.dip``  Plugin-Paket, tar.gz::

    dip.json            Paketkopf (format "dynamic-island-plugin", formatVersion 1)
    plugin/...          der Plugin-Ordner
    files/<n>[/...]     externe Dateien aus manifest.files (optional)

``<id>-settings.json``  nur Einstellungswerte (format "dynamic-island-plugin-settings")
"""

import json
import os
import re
import shutil
import socket
import sys
import tarfile
import tempfile
import time
from argparse import Namespace
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any

from dynamic_island.utils.paths import c_cache_dir, c_config_dir, compute_hash, config_dir

API_VERSION = 1
PACKAGE_FORMAT = "dynamic-island-plugin"
SETTINGS_FORMAT = "dynamic-island-plugin-settings"
FORMAT_VERSION = 1

plugins_dir = Path(os.getenv("DYNAMIC_ISLAND_PLUGINS_DIR", config_dir / "quickshell/dynamic-island/plugins"))
state_path = Path(os.getenv("DYNAMIC_ISLAND_PLUGINS_FILE", c_config_dir / "plugins.json"))
backups_dir = c_cache_dir / "plugin-backups"

ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")
KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
# Nicht ins Paket: Editor-/Laufzeitreste
SKIP_NAMES = {"__pycache__", ".qmlls.ini", ".git", ".DS_Store"}
MAX_MEMBERS = 5000
MAX_BYTES = 512 * 1024 * 1024


class PluginError(Exception):
    pass


# ---- Zustand und Manifeste ---------------------------------------------------


def read_state() -> dict[str, Any]:
    try:
        data = json.loads(state_path.read_text())
    except FileNotFoundError:
        data = {}
    except json.JSONDecodeError as e:
        raise PluginError(f"{state_path} ist kein gueltiges JSON: {e}")
    return {"format": 1, "enabled": data.get("enabled", {}), "settings": data.get("settings", {})}


def write_state(state: dict[str, Any]) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=state_path.parent, prefix=".plugins-")
    with os.fdopen(fd, "w") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.chmod(tmp, 0o644)  # mkstemp legt 0600 an; wie shell.json lesbar lassen
    os.replace(tmp, state_path)


def check_manifest(m: Any, folder: str | None = None) -> str:
    """Gleiche Regeln wie PluginHost.check() in der Shell. Leer = in Ordnung."""
    if not isinstance(m, dict):
        return "Manifest ist kein Objekt"
    pid = m.get("id")
    if not isinstance(pid, str) or not ID_RE.match(pid):
        return "id: nur a-z, 0-9 und -, hoechstens 48 Zeichen"
    if folder is not None and pid != folder:
        return f'id "{pid}" passt nicht zum Ordnernamen "{folder}"'
    if not isinstance(m.get("name"), str) or not m["name"]:
        return "name fehlt"
    api = m.get("api")
    if not isinstance(api, int) or isinstance(api, bool):
        return "api fehlt (Zahl)"
    if api > API_VERSION:
        return f"braucht Plugin-API {api}, diese Shell kann {API_VERSION}"
    parent = m.get("parent")
    if parent is not None and (not isinstance(parent, str) or not ID_RE.match(parent) or parent == pid):
        return "parent: id eines anderen Plugins erwartet"
    main = m.get("main")
    if main is not None and (not isinstance(main, str) or ".." in main or main.startswith("/")):
        return "main: relativer Pfad im Plugin-Ordner erwartet"
    settings = m.get("settings", {})
    if not isinstance(settings, dict):
        return "settings muss ein Objekt sein"
    for key, spec in settings.items():
        if not KEY_RE.match(key):
            return f"settings.{key}: ungueltiger Schluessel"
        if not isinstance(spec, dict) or "default" not in spec:
            return f'settings.{key}: "default" fehlt'
    tiles = m.get("tiles", {})
    if not isinstance(tiles, dict):
        return "tiles muss ein Objekt sein"
    for tid, tile in tiles.items():
        comp = tile.get("component") if isinstance(tile, dict) else None
        if not re.match(r"^[a-z0-9][a-z0-9-]*$", tid) or not isinstance(comp, str) or ".." in comp:
            return f"tiles.{tid}: id oder component ungueltig"
    panels = m.get("panels", {})
    if not isinstance(panels, dict):
        return "panels muss ein Objekt sein"
    for name, panel in panels.items():
        comp = panel.get("component") if isinstance(panel, dict) else None
        if not re.match(r"^[a-z][a-z0-9-]*$", name) or not isinstance(comp, str) or ".." in comp:
            return f"panels.{name}: Ansicht oder component ungueltig"
    widgets = m.get("widgets", {})
    if not isinstance(widgets, dict):
        return "widgets muss ein Objekt sein"
    for wtype, widget in widgets.items():
        comp = widget.get("component") if isinstance(widget, dict) else None
        if not re.match(r"^[a-z][a-z0-9-]*$", wtype) or not isinstance(comp, str) or ".." in comp:
            return f"widgets.{wtype}: Typ oder component ungueltig"
    keybinds = m.get("keybinds", {})
    if not isinstance(keybinds, dict):
        return "keybinds muss ein Objekt sein"
    for bid, bind in keybinds.items():
        if not re.match(r"^[a-z0-9][a-z0-9-]*$", bid) or not isinstance(bind, dict):
            return f"keybinds.{bid}: id ungueltig"
        if not isinstance(bind.get("keys"), str) or not bind["keys"].strip():
            return f"keybinds.{bid}: keys fehlt"
        title = bind.get("title")
        if not isinstance(title, str) or not title or "|" in title:
            return f"keybinds.{bid}: title fehlt oder enthaelt |"
        group = bind.get("group")
        if group is not None and (not isinstance(group, str) or not group or "|" in group):
            return f"keybinds.{bid}: group darf kein | enthalten"
        if isinstance(bind.get("ipc"), str) == isinstance(bind.get("exec"), str):
            return f"keybinds.{bid}: genau eins von ipc oder exec"
    files = m.get("files", [])
    if not isinstance(files, list):
        return "files muss eine Liste sein"
    for entry in files:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            return "files: Eintraege brauchen path"
        try:
            home_path(entry["path"])
        except PluginError as e:
            return f"files: {e}"
    return ""


def home_path(spec: str) -> Path:
    """~/... aufloesen; alles ausserhalb von $HOME ist verboten."""
    if not spec.startswith("~/"):
        raise PluginError(f'"{spec}" muss mit ~/ beginnen')
    home = Path.home().resolve()
    target = (home / spec[2:]).resolve()
    if target != home and home not in target.parents:
        raise PluginError(f'"{spec}" zeigt aus dem Home-Ordner heraus')
    return target


def load_manifest(folder: Path) -> tuple[dict[str, Any] | None, str]:
    try:
        m = json.loads((folder / "plugin.json").read_text())
    except FileNotFoundError:
        return None, "plugin.json fehlt"
    except json.JSONDecodeError as e:
        return None, f"plugin.json ist kein gueltiges JSON: {e}"
    problem = check_manifest(m, folder.name)
    return (None, problem) if problem else (m, "")


def installed() -> list[tuple[str, dict[str, Any] | None, str]]:
    if not plugins_dir.is_dir():
        return []
    out = []
    for folder in sorted(plugins_dir.iterdir()):
        if folder.is_dir() and not folder.name.startswith(("_", ".")):
            m, problem = load_manifest(folder)
            out.append((folder.name, m, problem))
    return out


def is_enabled(state: dict[str, Any], pid: str, manifest: dict[str, Any] | None) -> bool:
    on = state["enabled"].get(pid)
    return bool(manifest and manifest.get("defaultEnabled")) if on is None else bool(on)


def require(pid: str) -> tuple[Path, dict[str, Any]]:
    folder = plugins_dir / pid
    if not ID_RE.match(pid) or not folder.is_dir():
        raise PluginError(f'Plugin "{pid}" gibt es nicht')
    m, problem = load_manifest(folder)
    if m is None:
        raise PluginError(f"{pid}: {problem}")
    return folder, m


def version_tuple(v: str) -> tuple:
    return tuple(int(p) if p.isdigit() else p for p in re.split(r"[.+-]", str(v)))


def backup(path: Path, label: str) -> Path:
    """Verschiebt path in den Sicherungsordner; gibt den neuen Ort zurueck."""
    backups_dir.mkdir(parents=True, exist_ok=True)
    target = backups_dir / f"{label}-{time.strftime('%Y%m%d-%H%M%S')}"
    n = 1
    while target.exists():
        target = target.with_name(f"{target.name}-{n}")
        n += 1
    shutil.move(str(path), target)
    return target


# ---- Ausgabe -----------------------------------------------------------------


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        try:
            result = self.execute()
        except PluginError as e:
            self.emit({"ok": False, "message": str(e)})
            sys.exit(1)
        if result is not None:
            self.emit(result)

    def emit(self, result: dict[str, Any]) -> None:
        if getattr(self.args, "json", False):
            print(json.dumps(result, ensure_ascii=False))
        elif not result.get("ok", True):
            print(f"Fehler: {result['message']}", file=sys.stderr)
        elif result.get("message"):
            print(result["message"])

    def execute(self) -> dict[str, Any] | None:
        raise NotImplementedError

    def confirm(self, question: str) -> bool:
        if getattr(self.args, "yes", False):
            return True
        if not sys.stdin.isatty():
            raise PluginError("Nicht interaktiv: mit --yes bestaetigen")
        return input(f"{question} [j/N] ").strip().lower() in ("j", "ja", "y", "yes")


# ---- list / info / enable / disable / validate -------------------------------


class List(Command):
    def execute(self) -> dict[str, Any] | None:
        state = read_state()
        rows = []
        for pid, m, problem in installed():
            rows.append(
                {
                    "id": pid,
                    "name": m["name"] if m else pid,
                    "version": m.get("version", "?") if m else "?",
                    "enabled": is_enabled(state, pid, m),
                    "valid": m is not None,
                    "problem": problem,
                    "parent": (m or {}).get("parent", ""),
                }
            )
        if self.args.json:
            return {"ok": True, "message": f"{len(rows)} Plugins", "plugins": rows}
        if not rows:
            print(f"Keine Plugins in {plugins_dir}")
        # Komponenten (Manifest `parent`) eingerueckt unter ihrem Plugin;
        # fehlt das Eltern-Plugin, stehen sie oben mit Hinweis
        ids = {r["id"] for r in rows if r["valid"] and not r["parent"]}

        def show(r: dict[str, Any], indent: str) -> None:
            mark = "✗" if not r["valid"] else ("●" if r["enabled"] else "○")
            extra = f"  ({r['problem']})" if r["problem"] else ""
            if r["parent"] and r["parent"] not in ids:
                extra += f"  (gehoert zu {r['parent']}, fehlt)"
            print(f"{indent}{mark} {r['id']:<{20 - len(indent)}} {r['version']:<10} {r['name']}{extra}")

        for r in rows:
            if r["parent"] in ids:
                continue
            show(r, "")
            for c in rows:
                if c["parent"] == r["id"] and r["id"] in ids:
                    show(c, "  └ ")
        return None


class Info(Command):
    def execute(self) -> dict[str, Any] | None:
        folder, m = require(self.args.id)
        state = read_state()
        info = {
            "ok": True,
            "message": "",
            "id": m["id"],
            "manifest": m,
            "enabled": is_enabled(state, m["id"], m),
            "settings": state["settings"].get(m["id"], {}),
            "dir": str(folder),
        }
        if self.args.json:
            return info
        print(f"{m['name']} ({m['id']}) {m.get('version', '?')}  –  {'an' if info['enabled'] else 'aus'}")
        if m.get("description"):
            print(f"  {m['description']}")
        print(f"  Ordner: {folder}")
        for key, spec in m.get("settings", {}).items():
            value = info["settings"].get(key, spec["default"])
            print(f"  {key} = {json.dumps(value)}   ({spec.get('title', '')})")
        for entry in m.get("files", []):
            exists = home_path(entry["path"]).exists()
            print(f"  Datei {entry['path']}{'' if exists else '  (fehlt)'}")
        return None


class Enable(Command):
    on = True

    def execute(self) -> dict[str, Any] | None:
        _, m = require(self.args.id)
        state = read_state()
        state["enabled"][m["id"]] = self.on
        write_state(state)
        return {"ok": True, "message": f"{m['name']}: {'an' if self.on else 'aus'}", "id": m["id"], "enabled": self.on}


class Disable(Enable):
    on = False


class Validate(Command):
    def execute(self) -> dict[str, Any] | None:
        path = Path(self.args.path).expanduser()
        if path.is_dir():
            m, problem = load_manifest(path)
            if m is None:
                raise PluginError(problem)
            components = [t["component"] for t in m.get("tiles", {}).values()]
            components += [p["component"] for p in m.get("panels", {}).values()]
            for rel in [m.get("main")] + components:
                if rel and not (path / rel).is_file():
                    raise PluginError(f"{rel} fehlt im Plugin-Ordner")
            return {"ok": True, "message": f"{m['id']} {m.get('version', '?')}: in Ordnung", "id": m["id"]}
        with Package.open(path) as pkg:
            head = pkg.head
            return {
                "ok": True,
                "message": f"{head['plugin']['id']} {head['plugin'].get('version', '?')}: Paket in Ordnung",
                "id": head["plugin"]["id"],
            }


# ---- Export -----------------------------------------------------------------


class Export(Command):
    def execute(self) -> dict[str, Any] | None:
        folder, m = require(self.args.id)
        pid, version = m["id"], m.get("version", "0")
        state = read_state()
        settings = state["settings"].get(pid)

        if self.args.settings_only:
            out = self.target(f"{pid}-settings.json")
            doc = {
                "format": SETTINGS_FORMAT,
                "formatVersion": FORMAT_VERSION,
                "plugin": {"id": pid, "version": version},
                "created": datetime.now().astimezone().isoformat(timespec="seconds"),
                "settings": settings or {},
            }
            out.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            return {"ok": True, "message": f"Einstellungen exportiert: {out}", "path": str(out)}

        out = self.target(f"{pid}-{version}.dip")
        head: dict[str, Any] = {
            "format": PACKAGE_FORMAT,
            "formatVersion": FORMAT_VERSION,
            "plugin": {"id": pid, "name": m["name"], "version": version, "api": m["api"]},
            "created": datetime.now().astimezone().isoformat(timespec="seconds"),
            "generator": f"dynamic-island plugin export ({socket.gethostname()})",
            "enabled": is_enabled(state, pid, m),
            "files": [],
            "checksums": {},
        }
        if not self.args.no_settings and settings:
            head["settings"] = settings

        # Erst alles einsammeln (Name im Archiv -> Quelle), dann schreiben
        members: list[tuple[str, Path]] = []
        for src in sorted(folder.rglob("*")):
            rel = src.relative_to(folder)
            if any(part in SKIP_NAMES for part in rel.parts) or src.suffix == ".dip":
                continue
            if src.is_symlink():
                raise PluginError(f"Symlink im Plugin-Ordner wird nicht exportiert: {rel}")
            if src.is_file():
                members.append((f"plugin/{rel.as_posix()}", src))

        skipped = []
        if not self.args.no_files:
            for n, entry in enumerate(m.get("files", [])):
                path = home_path(entry["path"])
                optional = bool(entry.get("optional"))
                if not path.exists() or (optional and self.args.skip_optional):
                    skipped.append(entry["path"])
                    continue
                arc = f"files/{n}"
                kind = "dir" if path.is_dir() else "file"
                head["files"].append({"path": entry["path"], "archive": arc, "type": kind, "optional": optional})
                if kind == "file":
                    members.append((arc, path))
                else:
                    for src in sorted(path.rglob("*")):
                        if src.is_file() and not any(p in SKIP_NAMES for p in src.relative_to(path).parts):
                            members.append((f"{arc}/{src.relative_to(path).as_posix()}", src))

        for arc, src in members:
            head["checksums"][arc] = compute_hash(src)

        out.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=out.parent, prefix=".dip-")
        os.close(fd)
        try:
            with tarfile.open(tmp, "w:gz") as tar:
                data = json.dumps(head, indent=2, ensure_ascii=False).encode()
                info = tarfile.TarInfo("dip.json")
                info.size, info.mtime, info.mode = len(data), int(time.time()), 0o644
                tar.addfile(info, _bytes_io(data))
                for arc, src in members:
                    info = tar.gettarinfo(str(src), arc)
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mode = 0o755 if os.access(src, os.X_OK) else 0o644
                    with open(src, "rb") as f:
                        tar.addfile(info, f)
            os.replace(tmp, out)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise

        size = out.stat().st_size
        msg = f"Exportiert: {out} ({_human(size)}, {len(members)} Dateien)"
        if skipped:
            msg += f"; nicht dabei: {', '.join(skipped)}"
        return {"ok": True, "message": msg, "path": str(out), "size": size, "skipped": skipped}

    def target(self, default_name: str) -> Path:
        if self.args.output:
            out = Path(self.args.output).expanduser()
            return out / default_name if out.is_dir() or self.args.output.endswith("/") else out
        return Path.home() / "Downloads" / default_name


def _bytes_io(data: bytes):
    import io

    return io.BytesIO(data)


def _human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n} B"


# ---- Import -----------------------------------------------------------------


class Package:
    """Geprueftes .dip-Paket, entpackt in ein Temp-Verzeichnis."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.tmp = Path(tempfile.mkdtemp(prefix="dip-"))
        self.head: dict[str, Any] = {}
        self.manifest: dict[str, Any] = {}

    @classmethod
    def open(cls, path: Path) -> "Package":
        pkg = cls(path)
        try:
            pkg.unpack()
        except BaseException:
            pkg.close()
            raise
        return pkg

    def __enter__(self) -> "Package":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def close(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    @property
    def plugin_dir(self) -> Path:
        return self.tmp / "plugin"

    def unpack(self) -> None:
        if not self.path.is_file():
            raise PluginError(f"{self.path} gibt es nicht")
        try:
            tar = tarfile.open(self.path, "r:gz")
        except (tarfile.TarError, OSError) as e:
            raise PluginError(f"Kein .dip-Paket (tar.gz erwartet): {e}")
        with tar:
            members = tar.getmembers()
            if len(members) > MAX_MEMBERS:
                raise PluginError("Paket hat zu viele Dateien")
            total = 0
            for member in members:
                name = PurePosixPath(member.name)
                # "tar -C dir ." schreibt einen Eintrag "." fuer die Wurzel
                if member.isdir() and not name.parts:
                    continue
                if name.is_absolute() or ".." in name.parts or str(name) != os.path.normpath(member.name):
                    raise PluginError(f"Unsicherer Pfad im Paket: {member.name}")
                if not (member.isfile() or member.isdir()):
                    raise PluginError(f"Nur Dateien und Ordner erlaubt, nicht: {member.name}")
                if name.parts[0] not in ("dip.json", "plugin", "files"):
                    raise PluginError(f"Unerwarteter Eintrag im Paket: {member.name}")
                total += member.size
            if total > MAX_BYTES:
                raise PluginError("Paket ist entpackt groesser als 512 MB")
            tar.extractall(self.tmp, filter="data")

        try:
            self.head = json.loads((self.tmp / "dip.json").read_text())
        except (FileNotFoundError, json.JSONDecodeError) as e:
            raise PluginError(f"dip.json fehlt oder ist kaputt: {e}")
        if self.head.get("format") != PACKAGE_FORMAT:
            raise PluginError("dip.json: unbekanntes format")
        if self.head.get("formatVersion", 0) > FORMAT_VERSION:
            raise PluginError(f"Paketformat {self.head.get('formatVersion')} ist neuer als diese CLI ({FORMAT_VERSION})")

        # Pruefsummen: jede Datei muss drinstehen und stimmen
        sums = self.head.get("checksums", {})
        for f in self.tmp.rglob("*"):
            arc = f.relative_to(self.tmp).as_posix()
            if f.is_file() and arc != "dip.json":
                if arc not in sums:
                    raise PluginError(f"{arc} fehlt in den Pruefsummen")
                if compute_hash(f) != sums[arc]:
                    raise PluginError(f"Pruefsumme stimmt nicht: {arc}")
        for arc in sums:
            if not (self.tmp / arc).is_file():
                raise PluginError(f"{arc} fehlt im Paket")

        try:
            self.manifest = json.loads((self.plugin_dir / "plugin.json").read_text())
        except (FileNotFoundError, json.JSONDecodeError) as e:
            raise PluginError(f"plugin/plugin.json fehlt oder ist kaputt: {e}")
        problem = check_manifest(self.manifest)
        if problem:
            raise PluginError(f"Manifest: {problem}")
        if self.head.get("plugin", {}).get("id") != self.manifest["id"]:
            raise PluginError("dip.json und plugin.json nennen verschiedene ids")
        for entry in self.head.get("files", []):
            home_path(entry.get("path", ""))
            if not (self.tmp / entry.get("archive", "-")).exists():
                raise PluginError(f"Datei fuer {entry.get('path')} fehlt im Paket")


class Import(Command):
    def execute(self) -> dict[str, Any] | None:
        path = Path(self.args.file).expanduser()
        if path.suffix == ".json":
            return self.import_settings(path)

        with Package.open(path) as pkg:
            m = pkg.manifest
            pid, version = m["id"], m.get("version", "0")
            # Import aus dem Untermenue eines Plugins: nur dessen Komponenten
            want = self.args.parent
            if want and m.get("parent") != want:
                raise PluginError(
                    f'{m["name"]} ist keine Komponente von "{want}"'
                    + (f' (gehoert zu "{m["parent"]}")' if m.get("parent") else " (eigenstaendiges Plugin)")
                    + " – oben in der Plugin-Verwaltung importieren"
                )
            target = plugins_dir / pid
            old, _ = load_manifest(target) if target.is_dir() else (None, "")
            old_version = old.get("version", "0") if old else None

            if target.exists() and not self.args.force and old_version is not None:
                if version_tuple(old_version) >= version_tuple(version):
                    raise PluginError(
                        f"{m['name']} {old_version} ist schon installiert (Paket: {version}); --force ueberschreibt"
                    )

            files = pkg.head.get("files", [])
            lines = [f"{m['name']} ({pid}) {version}" + (f", ersetzt {old_version}" if old_version else "")]
            if m.get("main") or m.get("tiles"):
                lines.append("  Enthaelt QML-Code, der in der Shell laeuft – nur aus vertrauenswuerdiger Quelle!")
            commands = [b["exec"] for b in m.get("keybinds", {}).values() if "exec" in b]
            if commands:
                lines.append("  Tastenkuerzel mit Shell-Befehlen (laufen erst, wenn das Plugin an ist):")
                lines += [f"    {c}" for c in commands]
            if files:
                verb = "werden installiert" if self.args.files else "liegen bei (mit --files installieren)"
                lines.append(f"  {len(files)} externe Dateien {verb}:")
                lines += [f"    {f['path']}" for f in files]
            if not self.args.json:
                print("\n".join(lines))
            if not self.confirm("Importieren?"):
                return {"ok": False, "message": "Abgebrochen"}

            # Austauschen: altes Plugin in die Sicherung, neues an seinen Platz
            plugins_dir.mkdir(parents=True, exist_ok=True)
            staged = Path(tempfile.mkdtemp(prefix=f".{pid}-", dir=plugins_dir))
            shutil.rmtree(staged)
            shutil.copytree(pkg.plugin_dir, staged)
            saved = backup(target, f"plugin-{pid}") if target.exists() else None
            os.replace(staged, target)

            installed_files, kept = self.install_files(pkg, files) if self.args.files else ([], [])

            state = read_state()
            first = pid not in state["enabled"]
            if self.args.enable:
                state["enabled"][pid] = True
            elif first:
                # Fremder Code laeuft nie ungefragt: neu importiert = aus
                state["enabled"][pid] = False
            settings = pkg.head.get("settings")
            applied = False
            if settings and not self.args.no_settings and (self.args.settings or pid not in state["settings"]):
                state["settings"][pid] = settings
                applied = True
            write_state(state)

        msg = f"{m['name']} {version} importiert" + (" und eingeschaltet" if state["enabled"][pid] else " (aus)")
        if applied:
            msg += ", Einstellungen uebernommen"
        if installed_files:
            msg += f", {len(installed_files)} Datei(en) installiert"
        if kept:
            msg += f", {len(kept)} abweichende Dateien behalten (--overwrite-files ersetzt sie)"
        return {
            "ok": True,
            "message": msg,
            "id": pid,
            "version": version,
            "enabled": state["enabled"][pid],
            "settingsApplied": applied,
            "files": installed_files,
            "keptFiles": kept,
            "backup": str(saved) if saved else None,
        }

    def install_files(self, pkg: Package, files: list[dict[str, Any]]) -> tuple[list[str], list[str]]:
        done, kept = [], []
        for entry in files:
            src = pkg.tmp / entry["archive"]
            dest = home_path(entry["path"])
            for s, d in _pairs(src, dest):
                if d.exists() and d.is_file() and compute_hash(d) == compute_hash(s):
                    continue
                if d.exists() or d.is_symlink():
                    if not self.args.overwrite_files:
                        kept.append(str(d))
                        continue
                    backup(d, f"file-{d.name}")
                d.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(s, d)
                done.append(str(d))
        return done, kept

    def import_settings(self, path: Path) -> dict[str, Any]:
        try:
            doc = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            raise PluginError(f"{path}: {e}")
        if doc.get("format") != SETTINGS_FORMAT:
            raise PluginError(f'{path}: kein Einstellungs-Export (format "{SETTINGS_FORMAT}" erwartet)')
        pid = doc.get("plugin", {}).get("id", "")
        _, m = require(pid)
        spec = m.get("settings", {})
        values = {k: v for k, v in doc.get("settings", {}).items() if k in spec}
        dropped = sorted(set(doc.get("settings", {})) - set(values))
        if not self.confirm(f"Einstellungen fuer {m['name']} ersetzen?"):
            return {"ok": False, "message": "Abgebrochen"}
        state = read_state()
        state["settings"][pid] = values
        write_state(state)
        msg = f"Einstellungen fuer {m['name']} uebernommen ({len(values)} Werte)"
        if dropped:
            msg += f"; unbekannt und ignoriert: {', '.join(dropped)}"
        return {"ok": True, "message": msg, "id": pid, "settingsApplied": True}


def _pairs(src: Path, dest: Path):
    if src.is_file():
        yield src, dest
        return
    for s in sorted(src.rglob("*")):
        if s.is_file():
            yield s, dest / s.relative_to(src)


# ---- remove / new ------------------------------------------------------------


class Remove(Command):
    def execute(self) -> dict[str, Any] | None:
        pid = self.args.id
        folder = plugins_dir / pid
        if not ID_RE.match(pid) or not folder.is_dir():
            raise PluginError(f'Plugin "{pid}" gibt es nicht')
        m, _ = load_manifest(folder)
        if m and m.get("builtin") and not self.args.force:
            raise PluginError(f"{m['name']} gehoert zur Shell (builtin) – nur ausschalten, oder --force")
        if not self.confirm(f"{pid} entfernen (der Ordner wandert in {backups_dir})?"):
            return {"ok": False, "message": "Abgebrochen"}
        saved = backup(folder, f"plugin-{pid}")
        if not self.args.keep_settings:
            state = read_state()
            state["enabled"].pop(pid, None)
            state["settings"].pop(pid, None)
            write_state(state)
        return {"ok": True, "message": f"{pid} entfernt, Sicherung: {saved}", "id": pid, "backup": str(saved)}


class New(Command):
    def execute(self) -> dict[str, Any] | None:
        pid = self.args.id
        if not ID_RE.match(pid):
            raise PluginError("id: nur a-z, 0-9 und -, hoechstens 48 Zeichen")
        template = plugins_dir / "_example"
        target = plugins_dir / pid
        if target.exists():
            raise PluginError(f"{target} gibt es schon")
        if not template.is_dir():
            raise PluginError(f"Vorlage {template} fehlt")
        name = self.args.name or pid.replace("-", " ").title()
        shutil.copytree(template, target, ignore=shutil.ignore_patterns(*SKIP_NAMES))
        manifest_path = target / "plugin.json"
        m = json.loads(manifest_path.read_text())
        m.update({"id": pid, "name": name, "version": "0.1.0", "defaultEnabled": False})
        if self.args.author:
            m["author"] = self.args.author
        manifest_path.write_text(json.dumps(m, indent=4, ensure_ascii=False) + "\n")
        return {
            "ok": True,
            "message": f"Neues Plugin angelegt: {target} (aus; einschalten: dynamic-island plugin enable {pid})",
            "id": pid,
            "dir": str(target),
        }

