pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

import qs.modules.services.config
import qs.modules.services.notifications
import qs.modules.services.screenshot

// Kurze Systemklaenge, eigene Synthese passend zum Rice (sounds/*.wav,
// erzeugt von gen.py: message, shutter, plug, unplug, lock, unlock),
// abgespielt mit pw-play als Benachrichtigung, damit sie in pavucontrol eine
// eigene Lautstaerke haben. Alles aus, solange sounds.enabled false ist.
//
// Eigene Klaenge: ~/.config/dynamic-island/sounds/<name>.wav ersetzt den
// eingebauten (Einstellungen > Klaenge > Eigene Klaenge, SoundsEditor.qml).
// Import/Umwandeln/Dateiauswahl macht soundmgr.py.
//
// Probehoeren (auch wenn aus):  qs -c dynamic-island ipc call sounds play message
//
// Benutzung:  import qs.modules.services.sounds   ->  Sounds.play("message")
Singleton {
    id: root

    readonly property string dir: Quickshell.shellPath("modules/services/sounds/sounds/")
    readonly property string helper: Quickshell.shellPath("modules/services/sounds/soundmgr.py")
    readonly property var names: ["message", "shutter", "plug", "unplug", "lock", "unlock", "connect", "disconnect"]

    // { name: pfad } eigene Klaenge
    property var custom: ({})
    // Klang, fuer den gerade eine Datei gewaehlt oder umgewandelt wird
    property string busyName: ""
    property string lastError: ""

    function pathFor(name: string): string {
        return root.custom[name] ?? (root.dir + name + ".wav");
    }

    function isCustom(name: string): bool {
        return root.custom[name] !== undefined;
    }

    // Dateiauswahl oeffnen, dann importieren
    function choose(name: string): void {
        if (root.busyName !== "")
            return;
        root.busyName = name;
        root.lastError = "";
        pickProc.running = true;
    }

    // Datei (Pfad oder file://-URL, z.B. per Drag and Drop) uebernehmen
    function importFile(name: string, path: string): void {
        root.busyName = name;
        root.lastError = "";
        root.run(["import", name, path]);
    }

    function reset(name: string): void {
        root.run(["reset", name]);
    }

    function play(name: string): void {
        if (Config.sounds.enabled)
            root.playNow(name);
    }

    function playNow(name: string): void {
        if (!root.names.includes(name))
            return;
        Quickshell.execDetached(["pw-play", "--volume", String(Config.sounds.volume / 100),
            "-P", "{ media.role = \"Notification\", application.name = \"dynamic-island\" }",
            root.pathFor(name)]);
    }

    // ---- soundmgr.py ----
    property var queue: []

    function run(args: var): void {
        root.queue = root.queue.concat([args]);
        if (!mgrProc.running)
            root.next();
    }

    function next(): void {
        if (root.queue.length === 0)
            return;
        mgrProc.args = root.queue[0];
        root.queue = root.queue.slice(1);
        mgrProc.command = ["python3", "-I", root.helper].concat(mgrProc.args);
        mgrProc.running = true;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            return { ok: false, error: text.trim() || "soundmgr.py" };
        }
    }

    Process {
        id: mgrProc
        property var args: []
        stdout: StdioCollector { id: mgrOut }
        onExited: {
            const r = root.parse(mgrOut.text);
            const op = mgrProc.args[0];
            if (!r.ok) {
                root.lastError = r.error ?? "";
            } else if (op === "list") {
                root.custom = r.custom ?? {};
            } else if (op === "import") {
                root.custom = Object.assign({}, root.custom, { [r.name]: r.path });
                root.playNow(r.name);
            } else if (op === "reset") {
                const next = Object.assign({}, root.custom);
                delete next[r.name];
                root.custom = next;
            }
            if (op !== "list")
                root.busyName = "";
            root.next();
        }
    }

    Process {
        id: pickProc
        command: ["python3", "-I", root.helper, "pick"]
        stdout: StdioCollector { id: pickOut }
        onExited: {
            const r = root.parse(pickOut.text);
            if (r.ok && r.path)
                root.run(["import", root.busyName, r.path]);
            else {
                root.lastError = r.ok ? "" : (r.error ?? "");
                root.busyName = "";
            }
        }
    }

    function locked(on: bool): void {
        if (Config.sounds.lock)
            root.play(on ? "lock" : "unlock");
    }

    IpcHandler {
        target: "sounds"

        function play(name: string): void {
            root.playNow(name);
        }
    }

    Connections {
        target: Notifications
        function onArrived(entry: var): void {
            if (Config.sounds.notifications)
                root.play("message");
        }
    }

    Connections {
        target: Screenshot
        function onDone(action: string, result: var): void {
            if (Config.sounds.screenshot && result.ok && (action === "copy" || action === "save"))
                root.play("shutter");
        }
    }

    // Ladekabel: nur Wechsel melden, nicht den Zustand beim Start
    property bool onBattery: UPower.onBattery
    property bool powerKnown: false
    Component.onCompleted: {
        Qt.callLater(() => root.powerKnown = true);
        root.run(["list"]);
    }
    onOnBatteryChanged: if (root.powerKnown && Config.sounds.power) root.play(root.onBattery ? "unplug" : "plug")
}
