#!/usr/bin/env python3
"""Vergleichstest des Idle-Helfers. Aufruf: idle_scenarios.py <protokoll> <befehl...>"""

import json
import os
import signal
import subprocess
import sys
import threading
import time

from gi.repository import Gio, GLib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Bus, Scenario, assert_sandbox, describe_error, has_owner, own_name, release_name, start_loop, watch_close

NAME = "org.freedesktop.ScreenSaver"
IFACE = "org.freedesktop.ScreenSaver"
SESSION = "/org/freedesktop/login1/session/c1"
LOGIND_XML = """<node>
<interface name="org.freedesktop.login1.Manager">
<method name="GetSession"><arg type="s" direction="in"/><arg type="o" direction="out"/></method>
<method name="GetSessionByPID"><arg type="u" direction="in"/><arg type="o" direction="out"/></method>
<method name="Inhibit"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="h" direction="out"/></method>
<signal name="PrepareForSleep"><arg type="b"/></signal>
</interface>
<interface name="org.freedesktop.login1.Session"><signal name="Lock"/></interface>
</node>"""


class FakeLogind:
    def __init__(self, s: Scenario, bus: Bus, session_ok=True, inhibit_ok=True):
        self.s = s
        self.conn = bus.connect()
        self.session_ok = session_ok
        self.inhibit_ok = inhibit_ok
        self.since = time.monotonic()
        info = Gio.DBusNodeInfo.new_for_xml(LOGIND_XML)
        self.conn.register_object("/org/freedesktop/login1", info.interfaces[0], self.call, None, None)
        own_name(self.conn, "org.freedesktop.login1")

    def call(self, _conn, _sender, _path, _iface, method, params, inv):
        args = params.unpack()
        if method in ("GetSession", "GetSessionByPID"):
            shown = "<pid>" if method == "GetSessionByPID" else args[0]
            self.s.event(f"logind {method}({shown})")
            if self.session_ok:
                inv.return_value(GLib.Variant("(o)", (SESSION,)))
            else:
                inv.return_dbus_error("org.freedesktop.login1.NoSuchSession", "Keine Session")
        elif method == "Inhibit":
            self.s.event(f"logind Inhibit{args}")
            if not self.inhibit_ok:
                inv.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "Nein")
                return
            rd, wr = os.pipe()
            fds = Gio.UnixFDList.new()
            fds.append(wr)
            os.close(wr)
            watch_close(self.s, rd, "Delay-Sperre", lambda: self.since)
            inv.return_value_with_unix_fd_list(GLib.Variant("(h)", (0,)), fds)

    def prepare_for_sleep(self, going: bool):
        self.s.settle()
        self.s.log.append(f"> PrepareForSleep({going})")
        self.since = time.monotonic()
        self.conn.emit_signal(None, "/org/freedesktop/login1", "org.freedesktop.login1.Manager",
                              "PrepareForSleep", GLib.Variant("(b)", (going,)))

    def lock(self, path=SESSION):
        self.s.settle()
        self.s.log.append(f"> Session.Lock({path})")
        self.conn.emit_signal(None, path, "org.freedesktop.login1.Session", "Lock", None)


class Client:
    def __init__(self, s: Scenario, bus: Bus, label: str):
        self.s = s
        self.label = label
        self.conn = bus.connect()

    def call(self, method, args=None, path="/org/freedesktop/ScreenSaver", iface=IFACE, only_fails=False):
        self.s.settle()
        shown = args.unpack() if args else ()
        self.s.log.append(f"{self.label}: {path} {method}{shown}")
        try:
            res = self.conn.call_sync(NAME, path, iface, method, args, None, Gio.DBusCallFlags.NONE, 5000, None)
            self.s.log.append(f"{self.label}: = {res.unpack()}")
        except GLib.Error as e:
            # Python liefert hier Tracebacks und eigene Fehlernamen, die Shell wertet das nicht aus
            self.s.log.append(f"{self.label}: ! Fehler" if only_fails else f"{self.label}: ! {describe_error(e)}")

    def close(self):
        self.s.settle()
        self.s.log.append(f"{self.label}: Verbindung zu")
        self.conn.close_sync(None)


def env(session, system, sid="c1"):
    out = {"DBUS_SESSION_BUS_ADDRESS": session.address, "DBUS_SYSTEM_BUS_ADDRESS": system.address}
    if sid is not None:
        out["XDG_SESSION_ID"] = sid
    return out


def with_buses(fn):
    def run(log, command):
        session, system = Bus("session"), Bus("system")
        s = Scenario(fn.__name__, log, command)
        try:
            fn(s, session, system)
        finally:
            s.finish()
            session.stop()
            system.stop()

    return run


@with_buses
def screensaver_interface(s, session, system):
    login = FakeLogind(s, system)
    s.start(env(session, system))
    s.wait("ready", 5)
    a, b, c = Client(s, session, "A"), Client(s, session, "B"), Client(s, session, "C")
    for path in ("/org/freedesktop/ScreenSaver", "/ScreenSaver"):
        for method in ("GetActive", "GetActiveTime", "GetSessionIdleTime", "SimulateUserActivity"):
            a.call(method, path=path)
    a.call("Inhibit", GLib.Variant("(ss)", ("Firefox", "Video läuft")))
    b.call("Inhibit", GLib.Variant("(ss)", ('m"p\\v', "Zeile\nzwei ü 🎵")), path="/ScreenSaver")
    a.call("Inhibit", GLib.Variant("(ss)", ("", "")))
    b.call("UnInhibit", GLib.Variant("(u)", (1,)))
    a.call("UnInhibit", GLib.Variant("(u)", (1,)))
    a.call("UnInhibit", GLib.Variant("(u)", (999,)))
    b.close()
    s.note("Programm ohne Eintrag beendet sich: keine Meldung")
    c.close()
    a.close()
    s.settle()
    d = Client(s, session, "D")
    d.call("Inhibit", GLib.Variant("(ss)", ("neu", "Cookie zaehlt weiter")))
    d.call("Inhibit", GLib.Variant("(s)", ("zu wenig",)), only_fails=True)
    d.call("GibtsNicht", only_fails=True)
    s.send("quatsch\n")
    s.send("  locked  \n")
    login.lock()
    login.lock("/org/freedesktop/login1/session/andere")
    s.close_stdin()
    s.wait_exit()


@with_buses
def sleep_lock(s, session, system):
    login = FakeLogind(s, system)
    s.start(env(session, system))
    s.wait("ready", 5)
    s.note("Ohne sleep-lock: nur melden")
    login.prepare_for_sleep(True)
    login.prepare_for_sleep(False)
    s.send("sleep-lock on\n")
    s.send("sleep-lock on\n")
    s.note("Shell meldet rechtzeitig: locked")
    login.since = time.monotonic()
    login.prepare_for_sleep(True)
    s.send("locked\n")
    s.send("locked\n")
    login.since = time.monotonic()
    login.prepare_for_sleep(False)
    s.note("Shell meldet nichts: Sperre faellt nach der Wartezeit")
    login.prepare_for_sleep(True)
    s.wait("Delay-Sperre geschlossen", 6)
    login.prepare_for_sleep(False)
    s.note("Abschalten waehrend des Wartens, Wartezeit laeuft ins Leere")
    login.prepare_for_sleep(True)
    login.since = time.monotonic()
    s.send("sleep-lock off\n")
    time.sleep(3.5)
    s.settle()
    login.prepare_for_sleep(False)
    s.note("Wieder an, Beenden gibt die Sperre frei")
    login.since = time.monotonic()
    s.send("sleep-lock on\n")
    login.since = time.monotonic()
    s.close_stdin()
    s.wait_exit()


@with_buses
def inhibit_refused(s, session, system):
    FakeLogind(s, system, inhibit_ok=False)
    s.start(env(session, system))
    s.wait("ready", 5)
    s.send("sleep-lock on\n")
    s.send("locked\n")
    s.signal(signal.SIGTERM)
    s.wait_exit()


@with_buses
def name_taken(s, session, system):
    FakeLogind(s, system)
    holder = session.connect()
    own_name(holder, NAME)
    s.start(env(session, system))
    s.wait("taken", 5)
    s.note("Name wird frei, neuer Versuch nach 10 s")
    release_name(holder, NAME)
    t0 = time.monotonic()
    s.wait("ready", 13)
    s.log.append("Wartezeit passt" if 8.5 < time.monotonic() - t0 < 11.5 else "!! Wartezeit falsch")
    c = Client(s, session, "C")
    c.call("Inhibit", GLib.Variant("(ss)", ("x", "y")))
    s.close_stdin()
    s.wait_exit()


@with_buses
def session_lookup_fails(s, session, system):
    login = FakeLogind(s, system, session_ok=False)
    s.start(env(session, system))
    s.wait("ready", 5)
    login.lock()
    login.prepare_for_sleep(True)
    s.close_stdin()
    s.wait_exit()


@with_buses
def session_by_pid(s, session, system):
    login = FakeLogind(s, system)
    s.start(env(session, system, sid=None))
    s.wait("ready", 5)
    login.lock()
    s.close_stdin()
    s.wait_exit()


@with_buses
def empty_session_id(s, session, system):
    FakeLogind(s, system)
    s.start(env(session, system, sid=""))
    s.wait("ready", 5)
    s.close_stdin()
    s.wait_exit()


@with_buses
def no_logind(s, session, system):
    s.start(env(session, system))
    s.settle(1.5)
    s.wait_exit(compare_code=False)


@with_buses
def no_system_bus(s, session, system):
    e = env(session, system)
    e["DBUS_SYSTEM_BUS_ADDRESS"] = "unix:path=/tmp/gibtsnicht"
    s.start(e)
    s.settle(1.0)
    s.wait_exit(compare_code=False)


@with_buses
def sigterm(s, session, system):
    FakeLogind(s, system)
    s.start(env(session, system))
    s.wait("ready", 5)
    s.send("sleep-lock on\n")
    s.signal(signal.SIGTERM)
    s.wait_exit()
    probe = session.connect()
    time.sleep(0.2)
    s.log.append(f"Name noch belegt: {has_owner(probe, NAME)}")


@with_buses
def dies_with_parent(s, session, system):
    """PDEATHSIG: Stirbt die Shell, darf kein Waise den Namen halten."""
    FakeLogind(s, system)
    parent = ("import subprocess,sys,time\n"
              "p=subprocess.Popen(sys.argv[1:])\n"
              "time.sleep(60)\n")
    s.start(env(session, system), wrap=["python3", "-c", parent])
    s.wait("ready", 5)
    probe = session.connect()
    s.log.append(f"Name belegt: {has_owner(probe, NAME)}")
    s.sut.kill()
    s.sut.wait()
    s.log.append("> Eltern-Prozess getoetet")
    for _ in range(40):
        if not has_owner(probe, NAME):
            break
        time.sleep(0.05)
    s.log.append(f"Name noch belegt: {has_owner(probe, NAME)}")
    s.sut = None


SCENARIOS = [screensaver_interface, sleep_lock, inhibit_refused, name_taken, session_lookup_fails, session_by_pid,
             empty_session_id, no_logind, no_system_bus, sigterm, dies_with_parent]


def main():
    assert_sandbox()
    start_loop()
    out, command = sys.argv[1], sys.argv[2:]
    log: list[str] = []
    for scenario in SCENARIOS:
        scenario(log, command)
    with open(out, "w") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
