#!/usr/bin/env python3
"""Local MangoHud bridge. No root, network, global injection or saved benchmarks."""
import csv
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def runtime_root():
    base = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    return base / "dynamic-island-performance"


def launch(command, automatic=False):
    if not command:
        raise SystemExit("Aufruf: nox-game-performance <Spiel> [Argumente] | Steam: nox-game-performance %command%")
    if not shutil.which("mangohud"):
        if automatic:
            print("MangoHud fehlt; Launcher wird ohne FPS-Messung gestartet.", file=sys.stderr)
            os.execv(command[0], command)
            return
        raise SystemExit("MangoHud ist nicht installiert. Das Spiel wurde nicht gestartet.")
    # Do not change an already running single-instance launcher. Its next cold
    # start will inherit the telemetry environment; IPC-only calls need none.
    if automatic and launcher_running(command[0]):
        os.execv(command[0], command)
        return
    root = runtime_root()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    session = tempfile.mkdtemp(prefix="game-", dir=root)
    # Append to existing user options; only the bridge's output/visibility are fixed.
    previous = os.environ.get("MANGOHUD_CONFIG", "read_cfg")
    os.environ["MANGOHUD_CONFIG"] = previous + (
        # no_display=1 prevents OpenGL's autostart logger from ever starting in
        # MangoHud 0.8.4. Zero table columns suppress rendering, not measurement.
        f",no_display=0,table_columns=0,alpha=0,background_alpha=0,autostart_log=1,log_interval=500,log_duration=0,output_folder={session}"
    )
    os.environ["NOX_PERF_SESSION"] = session
    if automatic:
        os.environ["NOX_PERF_AUTO"] = "1"
    else:
        os.environ.pop("NOX_PERF_AUTO", None)
    # exec preserves signals, exit status, arguments and existing PRIME options.
    os.execvp("mangohud", ["mangohud", *command])


def launcher_running(command, proc=Path("/proc")):
    name = Path(command).name
    if name not in {"steam", "ModrinthApp"}:
        return False
    for path in proc.glob("[0-9]*/comm"):
        try:
            if path.parent.name != str(os.getpid()) and path.stat().st_uid == os.getuid() and path.read_text().strip() == name:
                return True
        except OSError:
            continue
    return False


def number(value, maximum=100000):
    try:
        n = float(value)
        return n if math.isfinite(n) and 0 <= n <= maximum else None
    except (ValueError, TypeError):
        return None


def read_metrics(path, now=None):
    """Bounded reads, complete records only, header names rather than column offsets."""
    now = time.time() if now is None else now
    try:
        if now - path.stat().st_mtime > 3:
            return None
        with path.open("rb") as f:
            head = f.read(4096).decode("utf-8", "replace")
            f.seek(0, 2)
            size = f.tell()
            start = max(0, size - 8192)
            f.seek(start)
            tail = f.read(8192).decode("utf-8", "replace")
        header = next((row for row in csv.reader(io.StringIO(head))
                       if "fps" in row and "frametime" in row), None)
        if not header:
            return None
        lines = tail.splitlines(keepends=True)
        if start:
            lines = lines[1:]  # first line may be partial
        for line in reversed(lines):
            if not line.endswith("\n"):
                continue
            row = next(csv.reader([line]))
            if len(row) != len(header):
                continue
            data = dict(zip(header, row))
            if number(data.get("fps")) is None or number(data.get("frametime")) is None:
                continue
            return {key: number(data.get(key)) for key in (
                "fps", "frametime", "cpu_load", "gpu_load", "cpu_temp", "gpu_temp",
                "gpu_vram_used", "ram_used", "gpu_power", "cpu_power", "gpu_core_clock"
            )}
    except (OSError, ValueError, csv.Error):
        pass
    return None


def session_for(pid, proc=Path("/proc")):
    try:
        for entry in (proc / str(pid) / "environ").read_bytes().split(b"\0"):
            if entry.startswith(b"NOX_PERF_SESSION="):
                session = Path(os.fsdecode(entry.split(b"=", 1)[1]))
                # Accept only sessions made by this bridge, never arbitrary user paths.
                if session.parent == runtime_root() and session.name.startswith("game-"):
                    return session
    except OSError:
        pass
    return None


def automatic_for(pid, proc=Path("/proc")):
    try:
        return b"NOX_PERF_AUTO=1" in (proc / str(pid) / "environ").read_bytes().split(b"\0")
    except OSError:
        return False


def sources_for(pid, session, proc=Path("/proc")):
    """An open log FD proves which process owns the FPS. Never pick 'newest log'."""
    paths = set()
    try:
        for fd in (proc / str(pid) / "fd").iterdir():
            try:
                path = Path(os.readlink(fd))
                if path.parent == session and path.suffix == ".csv" and not path.name.endswith("_summary.csv"):
                    paths.add(path)
            except OSError:
                continue
    except OSError:
        pass
    return paths


def snapshot(pid, app_class, title, proc=Path("/proc")):
    session = session_for(pid, proc) if pid > 0 else None
    automatic = automatic_for(pid, proc) if session else False
    launcher = bool(re.fullmatch(r"steam|steamwebhelper|ModrinthApp|Modrinth App|com\.modrinth\..*", app_class, re.I))
    known_game = bool(re.fullmatch(r"steam_app_\d+|gamescope|minecraft.*|net\.minecraft\..*|lwjgl.*", app_class, re.I)
                      or re.match(r"Minecraft\b", title, re.I))
    game = not launcher and bool(known_game or (session and not automatic))
    out = {"pid": pid, "game": game, "title": title, "metrics": None,
           "status": "Keine FPS-Quelle · Steam/Modrinth vollständig neu öffnen"}
    if launcher or (not game and not session):
        out["status"] = "Kein Spiel fokussiert"
        return out
    if not session:
        return out
    sources = sources_for(pid, session, proc)
    # Nested Gamescope owns the visible window, its renderer child owns the log.
    if app_class.lower() == "gamescope" and not sources:
        pending = [pid]
        seen = set()
        while pending and len(seen) < 64:
            current = pending.pop()
            if current in seen:
                continue
            seen.add(current)
            if session_for(current, proc) == session:
                sources.update(sources_for(current, session, proc))
            try:
                pending.extend(map(int, (proc / str(current) / "task" / str(current) / "children").read_text().split()))
            except (OSError, ValueError):
                pass
    live = [data for path in sources if (data := read_metrics(path)) is not None]
    # Automatically instrumented launchers may spawn helpers or browsers too.
    # Unrecognized native games count only once their own renderer yields data.
    if automatic and not known_game:
        out["game"] = bool(live)
        if not live:
            out["status"] = "Kein Spiel fokussiert"
            return out
    if len(live) == 1:
        out["metrics"] = live[0]
        out["status"] = "MangoHud · fokussierter Spielprozess"
    elif len(live) > 1:
        out["status"] = "Mehrere Renderer · FPS nicht eindeutig"
    else:
        out["status"] = "Warte auf MangoHud-Messdaten"
    return out


def active_snapshot():
    try:
        result = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True,
                                text=True, timeout=1, check=True)
        window = json.loads(result.stdout)
        out = snapshot(int(window.get("pid", 0)), window.get("class", ""), window.get("title", ""))
        out["window"] = window
        return out
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"pid": 0, "game": False, "metrics": None, "window": {}, "status": "Fensterdaten nicht verfügbar"}


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in {"launch", "auto-launch"}:
        launch(sys.argv[2:], automatic=sys.argv[1] == "auto-launch")
    else:
        args = sys.argv[1:]
        data = snapshot(int(args[0]), args[1], args[2]) if args else active_snapshot()
        print(json.dumps(data, allow_nan=False))
