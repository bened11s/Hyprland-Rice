"""Gemeinsamer Teil der Vergleichstests: private Busse, Testobjekt, Protokoll.

Jedes Szenario schreibt ein Protokoll. Die alte und die neue Version muessen
dasselbe Protokoll liefern (siehe run.sh). Laeuft nur in der Sandbox.
"""

import json
import os
import queue
import select
import signal
import subprocess
import tempfile
import threading
import time

from gi.repository import Gio, GLib

BUS_FLAGS = Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
QUIET = 0.3


def assert_sandbox() -> None:
    """Bricht ab, wenn der echte Desktop erreichbar waere."""
    for path in ("/run/dbus/system_bus_socket", f"/run/user/{os.getuid()}/bus", f"/run/user/{os.getuid()}/hypr"):
        if os.path.exists(path):
            raise SystemExit(f"Nicht in der Sandbox: {path} ist erreichbar")
    for var in ("DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY"):
        if os.environ.get(var):
            raise SystemExit(f"Nicht in der Sandbox: {var} ist gesetzt")


class Loop:
    """GLib-Hauptschleife im Hintergrund, sie bedient die Testdienste."""

    def __init__(self):
        self.loop = GLib.MainLoop()
        threading.Thread(target=self.loop.run, daemon=True).start()


LOOP = None


class Bus:
    def __init__(self, label: str):
        self.dir = tempfile.mkdtemp(prefix=f"bus-{label}-")
        self.address = f"unix:path={self.dir}/socket"
        self.proc = subprocess.Popen(["dbus-daemon", "--session", "--nofork", f"--address={self.address}"],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(200):
            if os.path.exists(f"{self.dir}/socket"):
                return
            time.sleep(0.01)
        raise RuntimeError("dbus-daemon startet nicht")

    def connect(self) -> Gio.DBusConnection:
        conn = Gio.DBusConnection.new_for_address_sync(self.address, BUS_FLAGS, None, None)
        conn.set_exit_on_close(False)
        return conn

    def stop(self) -> None:
        self.proc.terminate()
        self.proc.wait()


def bus_call(conn, method, args):
    return conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", method,
                          args, None, Gio.DBusCallFlags.NONE, 5000, None).unpack()


def own_name(conn, name: str) -> int:
    return bus_call(conn, "RequestName", GLib.Variant("(su)", (name, 4)))[0]


def release_name(conn, name: str) -> None:
    bus_call(conn, "ReleaseName", GLib.Variant("(s)", (name,)))


def has_owner(conn, name: str) -> bool:
    return bus_call(conn, "NameHasOwner", GLib.Variant("(s)", (name,)))[0]


def describe_error(error: GLib.Error) -> str:
    name = Gio.DBusError.get_remote_error(error) or "?"
    Gio.DBusError.strip_remote_error(error)
    return f"{name} | {error.message}"


class Scenario:
    """Ein Testlauf: sammelt Ereignisse und schreibt sie ins Protokoll.

    Was innerhalb eines Schritts passiert, wird sortiert: Stdout und Bus sind
    getrennte Kanaele, ihre Reihenfolge ist nicht festgelegt. Die Reihenfolge
    der Stdout-Zeilen untereinander bleibt erhalten (`seq`).
    """

    def __init__(self, name: str, log: list, command: list):
        self.name = name
        self.log = log
        self.command = command
        self.events = queue.Queue()
        self.seq = 0
        self.sut = None
        self.t0 = time.monotonic()
        log.append(f"=== {name}")

    def event(self, text: str) -> None:
        self.events.put(text)

    def note(self, text: str) -> None:
        self.settle()
        self.log.append(f"# {text}")

    def settle(self, quiet: float = QUIET) -> None:
        batch = []
        while True:
            try:
                batch.append(self.events.get(timeout=quiet))
            except queue.Empty:
                break
        self.log.extend(sorted(batch, key=lambda e: e if not e.startswith("<") else "<"))

    def wait(self, needle: str, timeout: float) -> None:
        """Wartet, bis ein Ereignis mit `needle` kam (fuer langsame Schritte)."""
        batch = []
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                item = self.events.get(timeout=0.1)
            except queue.Empty:
                continue
            batch.append(item)
            if needle in item:
                break
        else:
            batch.append(f"!! Zeitueberschreitung beim Warten auf {needle}")
        self.log.extend(sorted(batch, key=lambda e: e if not e.startswith("<") else "<"))
        self.settle()

    # ---- Testobjekt ----
    def start(self, env: dict, wrap: list | None = None) -> None:
        full = {k: v for k, v in os.environ.items() if k != "XDG_SESSION_ID"}
        full.update(env)
        self.sut = subprocess.Popen((wrap or []) + self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, env=full, bufsize=0)
        threading.Thread(target=self._read_out, args=(self.sut.stdout,), daemon=True).start()
        threading.Thread(target=self._read_err, args=(self.sut.stderr,), daemon=True).start()

    def _read_out(self, pipe) -> None:
        for raw in iter(pipe.readline, b""):
            line = raw.decode().rstrip("\n")
            self.event("< " + normalise(line))

    def _read_err(self, pipe) -> None:
        for raw in iter(pipe.readline, b""):
            # Nur die eigenen, stabilen Meldungen vergleichen, keine Tracebacks
            line = raw.decode().rstrip("\n")
            with open(os.environ.get("COMPARE_STDERR", os.devnull), "a") as f:
                f.write(f"[{self.name}] {line}\n")
            if line.startswith("idlehelper:"):
                self.event("stderr " + ":".join(line.split(":")[:2]))

    def send(self, text: str | bytes) -> None:
        self.settle()
        data = text.encode() if isinstance(text, str) else text
        self.log.append(f"> {data!r}")
        self.sut.stdin.write(data)
        self.sut.stdin.flush()

    def send_json(self, obj) -> None:
        self.send(json.dumps(obj, ensure_ascii=False) + "\n")

    def close_stdin(self) -> None:
        self.settle()
        self.log.append("> EOF")
        self.sut.stdin.close()

    def signal(self, sig: int) -> None:
        self.settle()
        self.log.append(f"> Signal {signal.Signals(sig).name}")
        self.sut.send_signal(sig)

    def wait_exit(self, timeout: float = 5.0, compare_code: bool = True) -> None:
        try:
            code = self.sut.wait(timeout)
            self.event(f"exit {code if compare_code else 'nonzero' if code else 0}")
        except subprocess.TimeoutExpired:
            self.event("!! laeuft noch")
            self.sut.kill()
            self.sut.wait()
        self.settle()

    def finish(self) -> None:
        if self.sut and self.sut.poll() is None:
            self.sut.kill()
            self.sut.wait()
        self.settle()


def normalise(line: str) -> str:
    """JSON auf eine Form bringen, Feldreihenfolge bleibt. Die Shell parst es."""
    prefix, sep, rest = line.partition(" ")
    if prefix == "inhibitors" and sep:
        return "inhibitors " + json.dumps(json.loads(rest), ensure_ascii=False)
    if line.startswith("{"):
        return json.dumps(json.loads(line), ensure_ascii=False)
    return line


def watch_close(scenario: Scenario, fd: int, label: str, since) -> None:
    """Meldet, wann das andere Ende eines Dateideskriptors geschlossen wurde."""

    def run():
        select.select([fd], [], [])
        ms = (time.monotonic() - since()) * 1000
        # Grobe Stufen: sofort oder nach der Wartezeit
        bucket = "sofort" if ms < 1000 else "nach ~3 s" if 2500 < ms < 3700 else f"nach {ms:.0f} ms"
        scenario.event(f"{label} geschlossen, {bucket}")
        os.close(fd)

    threading.Thread(target=run, daemon=True).start()


def start_loop() -> None:
    global LOOP
    if LOOP is None:
        LOOP = Loop()
