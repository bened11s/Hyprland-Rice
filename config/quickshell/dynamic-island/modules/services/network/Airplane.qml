pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// Flugmodus ueber rfkill: alle Funkgeraete (WLAN, Bluetooth) per Software
// blockieren. NetworkManager und bluez ziehen von selbst nach.
//
// Beim Ausschalten werden nur die Typen wieder freigegeben, die vorher an
// waren (nach einem Shell-Neustart mitten im Flugmodus: alle).
//
// Benutzung:  import qs.modules.services.network
Singleton {
    id: root

    readonly property Demand demand: Demand {}

    // [{ type, blocked }]
    property var devices: []
    readonly property bool available: root.devices.length > 0
    readonly property bool active: root.available && root.devices.every(d => d.blocked)
    // Typen, die beim Einschalten an waren
    property var before: []

    function toggle(): void {
        if (root.active) {
            const types = root.before.length > 0 ? root.before : ["all"];
            for (const t of types)
                Quickshell.execDetached(["rfkill", "unblock", t]);
            root.before = [];
        } else {
            root.before = [...new Set(root.devices.filter(d => !d.blocked).map(d => d.type))];
            Quickshell.execDetached(["rfkill", "block", "all"]);
        }
        settle.restart();
    }

    function refresh(): void {
        if (!readProc.running)
            readProc.running = true;
    }

    Process {
        id: readProc
        command: ["sh", "-c", "for d in /sys/class/rfkill/rfkill*; do [ -e \"$d/type\" ] && echo \"$(cat \"$d/type\") $(cat \"$d/soft\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: root.devices = text.trim().split("\n").filter(l => l !== "").map(l => {
                const [type, soft] = l.split(" ");
                return { type, blocked: soft === "1" };
            })
        }
    }

    // Aenderungen (auch von aussen) melden, solange die Kachel sichtbar ist
    Process {
        running: root.demand.active
        command: ["rfkill", "event"]
        stdout: SplitParser {
            onRead: settle.restart()
        }
    }

    Timer {
        id: settle
        interval: 150
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()
}
