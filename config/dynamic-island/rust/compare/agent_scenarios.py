#!/usr/bin/env python3
"""Vergleichstest des Bluetooth-Agents. Aufruf: agent_scenarios.py <protokoll> <befehl...>"""

import os
import re
import sys

from gi.repository import Gio, GLib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Bus, Scenario, assert_sandbox, describe_error, own_name, release_name, start_loop

AGENT_PATH = "/org/quickshell/BluetoothAgent"
AGENT_IFACE = "org.bluez.Agent1"
DEV_A = "/org/bluez/hci0/dev_AA"
DEV_B = "/org/bluez/hci0/dev_BB"
XML = """<node>
<interface name="org.bluez.AgentManager1">
<method name="RegisterAgent"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="RequestDefaultAgent"><arg type="o" direction="in"/></method>
</interface>
<interface name="org.bluez.Device1">
<method name="Pair"/>
<method name="CancelPairing"/>
</interface>
</node>"""


class FakeBluez:
    def __init__(self, s: Scenario, bus: Bus, register_error=None):
        self.s = s
        self.conn = bus.connect()
        self.agent = None
        self.pending_pair = None
        self.register_error = register_error
        info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.conn.register_object("/org/bluez", info.interfaces[0], self.manager, None, None)
        for dev in (DEV_A, DEV_B):
            self.conn.register_object(dev, info.interfaces[1], self.device, None, None)

    def appear(self):
        self.s.settle()
        self.s.log.append("> BlueZ erscheint")
        own_name(self.conn, "org.bluez")

    def vanish(self):
        self.s.settle()
        self.s.log.append("> BlueZ verschwindet")
        release_name(self.conn, "org.bluez")

    def manager(self, _conn, sender, _path, _iface, method, params, inv):
        self.s.event(f"bluez {method}{params.unpack()}")
        self.agent = sender
        if self.register_error and method == "RegisterAgent":
            inv.return_dbus_error(*self.register_error)
        else:
            inv.return_value(None)

    def device(self, _conn, _sender, path, _iface, method, _params, inv):
        self.s.event(f"bluez {path} {method}")
        if method == "Pair":
            self.pending_pair = inv
        else:
            inv.return_value(None)

    def finish_pair(self, error=None):
        self.s.settle()
        self.s.log.append(f"> Pair endet: {error or 'ok'}")
        inv, self.pending_pair = self.pending_pair, None
        if error:
            inv.return_dbus_error(*error)
        else:
            inv.return_value(None)

    def call(self, method, signature=None, *args):
        """Ruft den Agent wie BlueZ: Die Antwort kommt spaeter als Ereignis."""
        self.s.settle()
        self.s.log.append(f"bluez ruft {method}{args}")
        params = GLib.Variant(signature, args) if signature else None

        def done(conn, result, _data):
            try:
                self.s.event(f"Antwort {method} = {conn.call_finish(result).unpack()}")
            except GLib.Error as e:
                self.s.event(f"Antwort {method} ! {describe_error(e)}")

        self.conn.call(self.agent, AGENT_PATH, AGENT_IFACE, method, params, None, Gio.DBusCallFlags.NONE, 5000, None,
                       done, None)


def with_bus(fn, appear=True, **fake_args):
    def run(log, command):
        system = Bus("system")
        s = Scenario(fn.__name__, log, command)
        try:
            bluez = FakeBluez(s, system, **fake_args)
            if appear:
                bluez.appear()
            s.start({"DBUS_SYSTEM_BUS_ADDRESS": system.address, "DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/gibtsnicht"})
            s.settle(1.0)
            fn(s, bluez)
        finally:
            s.finish()
            system.stop()

    run.__name__ = fn.__name__
    return run


def lifecycle(s, bluez):
    s.note("Ohne BlueZ gestartet")
    bluez.appear()
    s.settle(0.6)
    bluez.vanish()
    s.settle(0.6)
    bluez.appear()
    s.settle(0.6)
    s.close_stdin()
    s.wait_exit()


def register_fails(s, bluez):
    s.send_json({"action": "pair", "path": DEV_A})
    s.close_stdin()
    s.wait_exit()


def requests(s, bluez):
    s.note("Bestaetigen")
    bluez.call("RequestConfirmation", "(ou)", DEV_A, 123)
    bluez.call("RequestPinCode", "(o)", DEV_A)
    s.send_json({"action": "respond", "accept": True})
    bluez.call("RequestConfirmation", "(ou)", DEV_A, 999999)
    s.send_json({"action": "respond", "accept": False})
    for falsy in (0, "", None, []):
        bluez.call("RequestAuthorization", "(o)", DEV_A)
        s.send_json({"action": "respond", "accept": falsy})
    bluez.call("RequestAuthorization", "(o)", DEV_A)
    s.send_json({"action": "respond"})
    bluez.call("AuthorizeService", "(os)", DEV_A, "0000110b-0000-1000-8000-00805f9b34fb")
    s.send_json({"action": "respond", "accept": 1})
    s.send_json({"action": "respond", "accept": True})

    s.note("PIN")
    bluez.call("RequestPinCode", "(o)", DEV_A)
    for bad in ("", "x" * 17, "ä" * 9, "a\u0000b"):
        s.send_json({"action": "respond", "value": bad})
    s.send_json({"action": "respond"})
    s.send_json({"action": "respond", "value": "ä" * 8})
    bluez.call("RequestPinCode", "(o)", DEV_A)
    s.send_json({"action": "respond", "value": 1234})
    bluez.call("RequestPinCode", "(o)", DEV_A)
    s.send_json({"action": "respond", "accept": False, "value": "1"})

    s.note("Passkey")
    bluez.call("RequestPasskey", "(o)", DEV_A)
    for bad in ("", "abc", "1234567", "٣", "-1", " 12", "1.5"):
        s.send_json({"action": "respond", "value": bad})
    s.send_json({"action": "respond", "value": "012345"})

    s.note("Anzeigen antwortet sofort und blockiert nichts")
    bluez.call("DisplayPinCode", "(os)", DEV_A, "0000")
    bluez.call("DisplayPasskey", "(ouq)", DEV_A, 42, 3)
    bluez.call("RequestConfirmation", "(ou)", DEV_A, 7)
    bluez.call("DisplayPasskey", "(ouq)", DEV_B, 1234567, 0)
    s.send_json({"action": "respond", "accept": True})

    s.note("Cancel und Release")
    bluez.call("Cancel")
    bluez.call("RequestPinCode", "(o)", DEV_A)
    bluez.call("Cancel")
    s.send_json({"action": "respond", "value": "1"})
    bluez.call("RequestPinCode", "(o)", DEV_A)
    bluez.call("Release")
    s.send_json({"action": "pair", "path": DEV_A})
    s.close_stdin()
    s.wait_exit()


def pairing(s, bluez):
    s.note("Erfolg")
    s.send_json({"action": "pair", "path": DEV_A})
    bluez.call("RequestConfirmation", "(ou)", DEV_B, 1)
    bluez.call("DisplayPasskey", "(ouq)", DEV_B, 1, 0)
    bluez.call("RequestConfirmation", "(ou)", DEV_A, 1)
    s.send_json({"action": "pair", "path": DEV_B})
    s.send_json({"action": "respond", "accept": True})
    s.send_json({"action": "pair", "path": DEV_B})
    bluez.finish_pair()

    s.note("Fehler")
    s.send_json({"action": "pair", "path": DEV_A})
    bluez.finish_pair(("org.bluez.Error.AuthenticationFailed", "Authentication Failed"))
    s.send_json({"action": "pair", "path": DEV_A})
    bluez.finish_pair(("org.bluez.Error.Failed", ""))

    s.note("Unbekanntes Geraet")
    s.send_json({"action": "pair", "path": "/org/bluez/hci0/dev_XX"})

    s.note("Abbruch: spaetes Ergebnis wird nicht mehr gemeldet")
    s.send_json({"action": "pair", "path": DEV_A})
    bluez.call("RequestPinCode", "(o)", DEV_A)
    s.send_json({"action": "cancel", "path": DEV_B})
    bluez.finish_pair(("org.bluez.Error.AuthenticationCanceled", "Canceled"))
    s.send_json({"action": "cancel", "path": DEV_B})
    s.send_json({"action": "cancel"})

    s.note("Cancel von BlueZ laesst das aktive Geraet stehen")
    s.send_json({"action": "pair", "path": DEV_A})
    bluez.call("Cancel")
    s.send_json({"action": "pair", "path": DEV_B})
    bluez.finish_pair()

    s.note("BlueZ verschwindet waehrend der Kopplung")
    s.send_json({"action": "pair", "path": DEV_A})
    bluez.call("RequestPinCode", "(o)", DEV_A)
    pending = bluez.pending_pair
    bluez.vanish()
    s.settle(0.6)
    bluez.pending_pair = pending
    bluez.finish_pair()
    bluez.appear()
    s.settle(0.6)
    s.send_json({"action": "pair", "path": DEV_B})
    bluez.finish_pair()
    s.close_stdin()
    s.wait_exit()


def bad_input(s, bluez):
    s.send(b"kein json\n")
    s.send(b"\n")
    s.send(b"\xff\xfe\n")
    s.send_json({"action": "pair"})
    s.send_json({"action": "gibtsnicht"})
    s.send_json({})
    s.send_json({"action": "respond", "value": "ohne Anfrage"})
    s.note("Mehrere Zeilen auf einmal, eine zerteilt")
    s.send(b'{"action":"pair","path":"/org/bluez/hci0/dev_AA"}\n{"action":"cancel"}\n{"action":')
    s.send(b'"cancel"}\n')
    s.note("Offene Anfrage und halbe Zeile beim Beenden")
    bluez.call("RequestPinCode", "(o)", DEV_A)
    s.send(b'{"action":"pair","path":"x"}')
    s.close_stdin()
    s.wait_exit()


def terminated(s, bluez):
    import signal

    s.signal(signal.SIGTERM)
    s.wait_exit(compare_code=False)


SCENARIOS = [
    with_bus(lifecycle, appear=False),
    with_bus(register_fails, register_error=("org.bluez.Error.AlreadyExists", "Already Exists")),
    with_bus(requests),
    with_bus(pairing),
    with_bus(bad_input),
    with_bus(terminated),
]


def main():
    assert_sandbox()
    start_loop()
    out, command = sys.argv[1], sys.argv[2:]
    log: list[str] = []
    for scenario in SCENARIOS:
        scenario(log, command)
    text = "\n".join(log) + "\n"
    # Eindeutige Busnamen wechseln von Lauf zu Lauf
    text = re.sub(r":\d+\.\d+", ":X.Y", text)
    # Der Text des JSON-Parsers ist je Sprache anders, die Shell schickt nur gueltiges JSON
    text = re.sub(r'(< \{"event": "error", "message": ")(?!\'path\'|GDBus)[^"]*', r"\1<JSON-Fehler>", text)
    with open(out, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
