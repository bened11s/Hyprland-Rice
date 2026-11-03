import QtQuick
import Quickshell
import Quickshell.Io

// Wetter-Dienst: holt alle 15 min ueber weather.py (open-meteo, Cache in
// ~/.cache/dynamic-island/plugins/weather) und haelt das Ergebnis fuer die
// Widgets bereit (plugin.main.data, Format im Kopf von weather.py).
//
// Ort festlegen:  qs -c dynamic-island ipc call plugins call weather ort "Köln"
//                 … call weather ort auto      (wieder aus der IP)
//                 … call weather refresh ""
QtObject {
    id: root

    required property var plugin

    // Letztes Ergebnis von `weather.py get` (null bis zum ersten Abruf)
    property var data: null
    readonly property bool ready: root.data?.ok === true
    readonly property bool loading: getProc.running
    property string lastMessage: ""

    readonly property string script: root.plugin.dir + "/weather.py"

    function refresh(force: bool): void {
        if (getProc.running)
            return;
        getProc.command = ["python3", "-I", root.script, "get"].concat(force ? ["--force"] : []);
        getProc.running = true;
    }

    function setPlace(name: string): void {
        placeProc.command = ["python3", "-I", root.script, "ort", name || "auto"];
        placeProc.running = true;
    }

    function ipc(cmd: string, arg: string): string {
        if (cmd === "ort") {
            root.setPlace(arg);
            return "ok";
        }
        if (cmd === "refresh") {
            root.refresh(true);
            return "ok";
        }
        if (cmd === "status")
            return JSON.stringify({ place: root.data?.place, updated: root.data?.updated, stale: root.data?.stale, error: root.data?.error, message: root.lastMessage });
        return "unbekannt: ort <name|auto> | refresh | status";
    }

    property Process getProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    // Fehler ohne Cache: altes Ergebnis behalten, nur Fehler merken
                    if (d.ok || !root.data)
                        root.data = d;
                    else
                        root.data = Object.assign({}, root.data, { stale: true, error: d.error });
                } catch (e) {
                    root.plugin.log(`weather.py: ${e}`);
                }
                // Fehlschlag: in 2 min noch einmal statt erst in 15
                retry.running = !(root.data?.ok) || root.data?.stale === true;
            }
        }
    }

    property Process placeProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.lastMessage = JSON.parse(text).message ?? "";
                } catch (e) {
                    root.lastMessage = text.trim();
                }
                root.plugin.log(root.lastMessage);
                root.refresh(true);
            }
        }
    }

    property Timer poll: Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    property Timer retry: Timer {
        interval: 2 * 60 * 1000
        onTriggered: root.refresh(false)
    }
}
