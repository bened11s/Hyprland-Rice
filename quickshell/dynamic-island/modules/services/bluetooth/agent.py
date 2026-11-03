#!/usr/bin/env python3
"""BlueZ Agent1 bridge: newline-delimited JSON on stdin/stdout."""

import json
import os
import sys
import warnings

from gi.repository import Gio, GLib

PATH = "/org/quickshell/BluetoothAgent"
XML = """<node><interface name="org.bluez.Agent1">
<method name="Release"/>
<method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
<method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
<method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
<method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
<method name="RequestAuthorization"><arg type="o" direction="in"/></method>
<method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
<method name="Cancel"/>
</interface></node>"""


def emit(event, **data):
    print(json.dumps({"event": event, **data}), flush=True)


class Agent:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.pending = None
        self.pending_kind = ""
        self.active_path = ""
        self.generation = 0
        self.buffer = b""
        self.ready = False
        self.loop = GLib.MainLoop()
        info = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
        # PyGObject's compatibility wrapper also supports older GLib versions.
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", DeprecationWarning)
            self.bus.register_object(PATH, info, self.method_call, None, None)
        Gio.bus_watch_name_on_connection(
            self.bus, "org.bluez", Gio.BusNameWatcherFlags.NONE,
            self.appeared, self.vanished,
        )
        GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, self.read_input)

    def call(self, path, interface, method, parameters=None, callback=None):
        self.bus.call("org.bluez", path, interface, method, parameters, None,
                      Gio.DBusCallFlags.NONE, 90000, None, callback, None)

    def appeared(self, *_):
        try:
            for method, args in (
                ("RegisterAgent", GLib.Variant("(os)", (PATH, "KeyboardDisplay"))),
                ("RequestDefaultAgent", GLib.Variant("(o)", (PATH,))),
            ):
                self.bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1",
                                   method, args, None, Gio.DBusCallFlags.NONE, 5000, None)
            self.ready = True
            emit("ready", ready=True)
        except GLib.Error as error:
            self.ready = False
            emit("ready", ready=False)
            emit("error", message=error.message)

    def vanished(self, *_):
        self.ready = False
        self.reject()
        self.active_path = ""
        self.generation += 1
        emit("ready", ready=False)

    def reject(self):
        if self.pending is not None:
            self.pending.return_dbus_error("org.bluez.Error.Rejected", "Rejected by user")
            self.pending = None
        self.pending_kind = ""

    def method_call(self, connection, sender, path, interface, method, parameters, invocation):
        args = parameters.unpack()
        if method in ("Release", "Cancel"):
            self.reject()
            invocation.return_value(None)
            if method == "Release":
                self.ready = False
                emit("ready", ready=False)
            emit("canceled")
            return

        device = args[0]
        if self.active_path and self.active_path != device:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Another device is pairing")
            return
        if method in ("DisplayPinCode", "DisplayPasskey"):
            code = args[1] if method == "DisplayPinCode" else f"{args[1]:06d}"
            emit("request", kind="display", path=device, passkey=code,
                 entered=args[2] if method == "DisplayPasskey" else 0)
            invocation.return_value(None)
            return

        if self.pending is not None:
            invocation.return_dbus_error("org.bluez.Error.Rejected", "Another request is pending")
            return
        self.pending = invocation
        kinds = {"RequestPinCode": "pin", "RequestPasskey": "passkey",
                 "RequestConfirmation": "confirm", "RequestAuthorization": "authorize",
                 "AuthorizeService": "authorize"}
        self.pending_kind = kinds[method]
        emit("request", kind=self.pending_kind, path=device,
             passkey=f"{args[1]:06d}" if method == "RequestConfirmation" else "",
             service=args[1] if method == "AuthorizeService" else "")

    def command(self, data):
        action = data.get("action")
        if action == "pair":
            if not self.ready or self.active_path or self.pending is not None:
                emit("error", path=data["path"], message="Bluetooth-Agent ist nicht bereit oder beschäftigt")
                return
            self.active_path = data["path"]
            self.generation += 1
            generation = self.generation
            path = self.active_path

            def paired(bus, result, *_):
                try:
                    bus.call_finish(result)
                    event, message = "paired", ""
                except GLib.Error as error:
                    event, message = "error", error.message
                if generation == self.generation:
                    self.active_path = ""
                    emit(event, path=path, message=message)

            self.call(path, "org.bluez.Device1", "Pair", callback=paired)
        elif action == "respond" and self.pending is not None:
            if not data.get("accept", True):
                self.reject()
                return
            value = str(data.get("value", ""))
            if self.pending_kind == "pin":
                if not 1 <= len(value.encode("utf-8")) <= 16 or "\x00" in value:
                    emit("input-error", kind="pin", message="PIN muss 1–16 Bytes lang sein")
                    return
                response = GLib.Variant("(s)", (value,))
            elif self.pending_kind == "passkey":
                if not value.isascii() or not value.isdigit() or not 1 <= len(value) <= 6:
                    emit("input-error", kind="passkey", message="Passkey muss aus 1–6 Ziffern bestehen")
                    return
                response = GLib.Variant("(u)", (int(value),))
            else:
                response = None
            self.pending.return_value(response)
            self.pending = None
            self.pending_kind = ""
        elif action == "cancel":
            path = self.active_path or data.get("path", "")
            self.reject()
            self.generation += 1
            self.active_path = ""
            if path:
                self.call(path, "org.bluez.Device1", "CancelPairing", callback=self.ignore_result)

    @staticmethod
    def ignore_result(bus, result, *_):
        try:
            bus.call_finish(result)
        except GLib.Error:
            pass

    def read_input(self, fd, condition):
        chunk = os.read(fd, 4096)
        if not chunk:
            self.reject()
            self.loop.quit()
            return False
        self.buffer += chunk
        while b"\n" in self.buffer:
            line, self.buffer = self.buffer.split(b"\n", 1)
            try:
                self.command(json.loads(line))
            except (ValueError, KeyError, TypeError) as error:
                emit("error", message=str(error))
        return True


if __name__ == "__main__":
    Agent().loop.run()
