#!/usr/bin/env python3
"""D-Bus-Teil der Idle-Verwaltung (modules/services/idle/Idle.qml).

Laeuft so lange wie die Shell (PDEATHSIG) und spricht zeilenweise:

stdout
  ready                     ScreenSaver-Name gehoert uns
  taken                     Name gehoert jemand anderem (hypridle?), neuer Versuch in 10 s
  inhibitors <json>         [{"app", "reason"}] aktuelle Inhibit()-Aufrufe
  sleep                     logind will gleich schlafen -> jetzt sperren
  wake                      zurueck aus dem Ruhezustand
  lock                      loginctl lock-session (o. ae.) -> sperren

stdin
  locked                    Sperre steht, Schlaf darf weiter
  sleep-lock on|off         Vor dem Ruhezustand sperren (Verzoegerung halten)

org.freedesktop.ScreenSaver: Browser und Player rufen Inhibit(), solange ein
Video laeuft. logind: eine "delay"-Sperre fuer sleep haelt den Ruhezustand
auf, bis die Shell gesperrt hat (hoechstens LOCK_WAIT Sekunden) – sonst
blitzt beim Aufwachen kurz der Desktop auf.
"""

import ctypes
import json
import os
import signal
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

NAME = "org.freedesktop.ScreenSaver"
IFACE = "org.freedesktop.ScreenSaver"
LOCK_WAIT = 3.0
RETRY = 10


def emit(line: str) -> None:
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


class ScreenSaver(dbus.service.Object):
    def __init__(self, bus, path, owner):
        super().__init__(bus, path)
        self.owner = owner

    @dbus.service.method(IFACE, in_signature="ss", out_signature="u", sender_keyword="sender")
    def Inhibit(self, app, reason, sender=None):
        return self.owner.inhibit(str(sender), str(app), str(reason))

    @dbus.service.method(IFACE, in_signature="u", out_signature="", sender_keyword="sender")
    def UnInhibit(self, cookie, sender=None):
        self.owner.uninhibit(int(cookie), str(sender))

    @dbus.service.method(IFACE, in_signature="", out_signature="b")
    def GetActive(self):
        return False

    @dbus.service.method(IFACE, in_signature="", out_signature="u")
    def GetActiveTime(self):
        return 0

    @dbus.service.method(IFACE, in_signature="", out_signature="u")
    def GetSessionIdleTime(self):
        return 0

    @dbus.service.method(IFACE, in_signature="", out_signature="")
    def SimulateUserActivity(self):
        pass


class Helper:
    def __init__(self):
        self.session = dbus.SessionBus()
        self.system = dbus.SystemBus()
        self.cookies = {}           # cookie -> (sender, app, reason)
        self.next_cookie = 1
        self.objects = []
        self.name = None
        self.sleep_lock = False
        self.delay_fd = None
        self.release_source = None

        self.session.add_signal_receiver(self.on_owner_changed, "NameOwnerChanged",
                                         "org.freedesktop.DBus", "org.freedesktop.DBus")
        self.claim()

        login = self.system.get_object("org.freedesktop.login1", "/org/freedesktop/login1")
        self.manager = dbus.Interface(login, "org.freedesktop.login1.Manager")
        self.system.add_signal_receiver(self.on_prepare_for_sleep, "PrepareForSleep",
                                        "org.freedesktop.login1.Manager",
                                        path="/org/freedesktop/login1")
        try:
            sid = os.environ.get("XDG_SESSION_ID")
            spath = self.manager.GetSession(sid) if sid else self.manager.GetSessionByPID(os.getpid())
            self.system.add_signal_receiver(lambda: emit("lock"), "Lock",
                                            "org.freedesktop.login1.Session", path=spath)
        except dbus.DBusException as e:
            print(f"idlehelper: Session nicht gefunden: {e}", file=sys.stderr)

    # ---- ScreenSaver ----
    def claim(self):
        flags = dbus.bus.NAME_FLAG_DO_NOT_QUEUE
        try:
            res = self.session.request_name(NAME, flags)
        except dbus.DBusException:
            res = None
        if res in (dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER, dbus.bus.REQUEST_NAME_REPLY_ALREADY_OWNER):
            if not self.objects:
                self.objects = [ScreenSaver(self.session, p, self)
                                for p in ("/org/freedesktop/ScreenSaver", "/ScreenSaver")]
            emit("ready")
            return False
        emit("taken")
        GLib.timeout_add_seconds(RETRY, self.claim)
        return False

    def inhibit(self, sender, app, reason):
        cookie = self.next_cookie
        self.next_cookie += 1
        self.cookies[cookie] = (sender, app, reason)
        self.report()
        return cookie

    def uninhibit(self, cookie, sender):
        entry = self.cookies.get(cookie)
        if entry and entry[0] == sender:
            del self.cookies[cookie]
            self.report()

    def on_owner_changed(self, name, old, new):
        # Programm beendet, ohne UnInhibit zu rufen
        if new == "" and name.startswith(":"):
            gone = [c for c, e in self.cookies.items() if e[0] == name]
            for c in gone:
                del self.cookies[c]
            if gone:
                self.report()

    def report(self):
        emit("inhibitors " + json.dumps([{"app": a, "reason": r} for _s, a, r in self.cookies.values()],
                                        ensure_ascii=False))

    # ---- logind ----
    def take_delay(self):
        if self.delay_fd is not None or not self.sleep_lock:
            return
        try:
            fd = self.manager.Inhibit("sleep", "dynamic-island", "Vor dem Ruhezustand sperren", "delay")
            self.delay_fd = fd.take()
        except dbus.DBusException as e:
            print(f"idlehelper: Inhibit gescheitert: {e}", file=sys.stderr)

    def release_delay(self):
        if self.release_source is not None:
            GLib.source_remove(self.release_source)
            self.release_source = None
        if self.delay_fd is not None:
            os.close(self.delay_fd)
            self.delay_fd = None
        return False

    def on_prepare_for_sleep(self, going):
        if going:
            emit("sleep")
            if self.delay_fd is not None:
                self.release_source = GLib.timeout_add(int(LOCK_WAIT * 1000), self.release_delay)
        else:
            emit("wake")
            self.take_delay()

    # ---- stdin ----
    def on_stdin(self, source, _cond):
        line = source.readline()
        if not line:
            loop.quit()
            return False
        cmd = line.strip()
        if cmd == "locked":
            self.release_delay()
        elif cmd == "sleep-lock on":
            self.sleep_lock = True
            self.take_delay()
        elif cmd == "sleep-lock off":
            self.sleep_lock = False
            self.release_delay()
        return True


def main():
    # Mit der Shell sterben (sonst haelt ein Waise den ScreenSaver-Namen)
    try:
        ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)
    except OSError:
        pass
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    DBusGMainLoop(set_as_default=True)
    helper = Helper()
    GLib.io_add_watch(GLib.IOChannel.unix_new(0), GLib.IOCondition.IN | GLib.IOCondition.HUP,
                      lambda ch, cond: helper.on_stdin(sys.stdin, cond))
    loop.run()


loop = GLib.MainLoop()

if __name__ == "__main__":
    main()
