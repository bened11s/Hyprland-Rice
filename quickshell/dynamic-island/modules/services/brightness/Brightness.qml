pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// Helligkeitssteuerung:
//   1. Internes Laptop-Panel ueber brightnessctl/sysfs (ein Wert fuer alles)
//   2. Ohne Backlight-Geraet alle per DDC erkannten Monitore – JEDER EINZELN.
//      `ddcutil detect` liefert je Display den I2C-Bus und den DRM-Connector
//      (card1-HDMI-A-1); ueber den Connector-Namen findet das OSD den
//      Monitor, auf dem es gerade sitzt.
//
// Zwei Schnittstellen:
//   global      value / ready / setValue(v)        – alle Monitore zusammen
//               (Settings-Karte, Helligkeitsring); `value` ist der Wert des
//               ersten Monitors
//   je Monitor  valueFor(name) / readyFor(name) / setValueFor(name, v)
//               `monitors` ist { name: { bus, value, ready } } und wird bei
//               jeder Aenderung als neues Objekt gesetzt (sonst merkt QML
//               nichts).
Singleton {
    id: root

    property real value: 1
    property bool ready: false
    property string backend: ""
    property string backlightDevice: ""
    // Busnummern nur aus ddcutil, beim Parsen auf Ziffern reduziert
    property var ddcBuses: []
    // Connector-Name -> { bus, value, ready }
    property var monitors: ({})

    // Ausstehende Schreibwerte je Bus (Prozent), gesammelt und gebuendelt
    property var pending: ({})
    property int backlightPending: 100
    property int backlightActive: -1

    readonly property int percent: Math.round(value * 100)

    // Nachlesen (fuer Aenderungen ueber die Monitor-Tasten) nur, solange
    // eine Anzeige offen ist – OSD oder Kacheln, je per DemandRequest.
    // Jeder Lauf kostet zwei ddcutil-Aufrufe ueber I2C (~0,1 s CPU).
    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active
    // Letzter abgeschlossener Lauf. Ist er frisch (< 15 s), liest das Oeffnen
    // nicht sofort nach – OSD-Hover und Kacheln oeffnen oft kurz hintereinander,
    // der 8-s-Timer unten holt Monitor-Tasten-Aenderungen trotzdem.
    property real lastQuery: 0

    onWatchingChanged: if (root.watching && Date.now() - root.lastQuery > 15000
                           && !writeProcess.running && !writeTimer.running && !settleTimer.running)
        root.startQuery()

    // ---- je Monitor ----
    function valueFor(name: string): real {
        return root.monitors[name]?.value ?? root.value;
    }

    function readyFor(name: string): bool {
        return root.monitors[name]?.ready ?? root.ready;
    }

    function setValueFor(name: string, newValue: real): void {
        const clamped = Math.max(0, Math.min(1, newValue));
        if (root.backend !== "ddc" || !root.monitors[name]) {
            root.setValue(clamped);
            return;
        }
        const next = Object.assign({}, root.monitors);
        next[name] = Object.assign({}, next[name], { value: clamped });
        root.monitors = next;
        root.queueWrite(next[name].bus, Math.round(clamped * 100));
        root.syncGlobal();
    }

    // ---- global ----
    function setValue(newValue: real): void {
        if (!root.ready)
            return;
        const clamped = Math.max(0, Math.min(1, newValue));
        root.value = clamped;
        if (root.backend === "backlight") {
            root.backlightPending = Math.round(clamped * 100);
            writeTimer.restart();
            return;
        }
        const next = {};
        for (const name in root.monitors) {
            next[name] = Object.assign({}, root.monitors[name], { value: clamped });
            root.queueWrite(next[name].bus, Math.round(clamped * 100));
        }
        root.monitors = next;
    }

    function syncGlobal(): void {
        const names = Object.keys(root.monitors);
        if (names.length === 0)
            return;
        const first = root.monitors[names[0]];
        if (first.ready) {
            root.value = first.value;
            root.ready = true;
        }
    }

    function queueWrite(bus: string, percent: int): void {
        const next = Object.assign({}, root.pending);
        next[bus] = percent;
        root.pending = next;
        writeTimer.restart();
    }

    function startQuery(): void {
        if (queryProcess.running || root.backend === "")
            return;
        if (root.backend === "backlight") {
            queryProcess.command = ["brightnessctl", "--device", root.backlightDevice,
                                    "--machine-readable", "info"];
        } else {
            // Alle Busse in einem Rutsch, je Bus eine Kopfzeile zum Zuordnen
            const script = root.ddcBuses.map(bus =>
                `echo "BUS ${bus}"; ddcutil --bus ${bus} getvcp 10 --brief 2>/dev/null`).join("; ");
            queryProcess.command = ["sh", "-c", script];
        }
        queryProcess.running = true;
    }

    function flushWrite(): void {
        if (writeProcess.running)
            return;

        if (root.backend === "backlight") {
            if (!root.ready)
                return;
            root.backlightActive = root.backlightPending;
            writeProcess.command = ["brightnessctl", "--device", root.backlightDevice,
                                    "set", root.backlightActive + "%"];
            writeProcess.running = true;
            return;
        }

        const buses = Object.keys(root.pending);
        if (buses.length === 0)
            return;
        const commands = buses.map(bus =>
            `ddcutil --bus ${bus} setvcp 10 ${root.pending[bus]} --noverify`).join(" & ");
        root.pending = ({});
        writeProcess.command = ["sh", "-c", commands + " & wait"];
        writeProcess.running = true;
    }

    // brightnessctl listet auch Tastatur-LEDs. Nur die Klasse "backlight"
    // steuert ein Display; das erste solche Geraet ist das interne Panel.
    Process {
        id: backlightDetect

        command: ["brightnessctl", "--list", "--machine-readable"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of this.text.trim().split("\n")) {
                    const fields = line.split(",");
                    if (fields.length >= 2 && fields[1] === "backlight") {
                        root.backlightDevice = fields[0];
                        break;
                    }
                }
            }
        }

        onExited: {
            if (root.backlightDevice !== "") {
                root.backend = "backlight";
                root.startQuery();
            } else {
                ddcDetect.running = true;
            }
        }
    }

    Process {
        id: ddcDetect

        command: ["ddcutil", "detect", "--brief"]

        stdout: StdioCollector {
            onStreamFinished: {
                const buses = [];
                const found = {};
                // Je Display: erst der Bus, dann der Connector (card1-HDMI-A-1)
                const pattern = /I2C bus:\s+\/dev\/i2c-(\d+)[\s\S]*?DRM connector:\s+card\d+-([A-Za-z0-9-]+)/g;
                let match;
                while ((match = pattern.exec(this.text)) !== null) {
                    const bus = match[1];
                    const name = match[2];
                    if (!buses.includes(bus))
                        buses.push(bus);
                    found[name] = { bus, value: 1, ready: false };
                }
                // Busse ohne Connector-Zeile (aeltere ddcutil-Ausgabe) trotzdem mitnehmen
                const loose = /\/dev\/i2c-(\d+)/g;
                while ((match = loose.exec(this.text)) !== null) {
                    if (!buses.includes(match[1]))
                        buses.push(match[1]);
                }
                root.ddcBuses = buses;
                root.monitors = found;
            }
        }

        onExited: {
            if (root.ddcBuses.length > 0) {
                root.backend = "ddc";
                root.startQuery();
            }
        }
    }

    Process {
        id: queryProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.lastQuery = Date.now();
                if (root.backend === "backlight") {
                    const fields = this.text.trim().split(",");
                    const percentField = fields.find(field => field.endsWith("%"));
                    const current = percentField ? parseInt(percentField) : -1;
                    if (current < 0)
                        return;
                    root.value = current / 100;
                    root.backlightPending = root.percent;
                    root.ready = true;
                    return;
                }

                // Bloecke "BUS n" + "VCP 10 C cur max"
                const next = Object.assign({}, root.monitors);
                let bus = "";
                for (const line of this.text.split("\n")) {
                    const head = line.match(/^BUS (\d+)/);
                    if (head) {
                        bus = head[1];
                        continue;
                    }
                    const vcp = line.match(/VCP 10 C (\d+) (\d+)/);
                    if (!vcp || bus === "")
                        continue;
                    const current = parseInt(vcp[1]);
                    const maximum = parseInt(vcp[2]);
                    if (maximum <= 0)
                        continue;
                    // Monitor zu diesem Bus; gibt es keinen bekannten, unter dem Bus fuehren
                    let name = Object.keys(next).find(n => next[n].bus === bus);
                    if (!name) {
                        name = "bus-" + bus;
                        next[name] = { bus, value: 1, ready: false };
                    }
                    // Waehrend ein Schreibvorgang aussteht, den Lesewert nicht
                    // drueberbuegeln – der Regler wuerde sonst springen
                    if (root.pending[bus] !== undefined || writeProcess.running)
                        continue;
                    next[name] = Object.assign({}, next[name], { value: current / maximum, ready: true });
                }
                root.monitors = next;
                root.syncGlobal();
            }
        }
    }

    Process {
        id: writeProcess

        onExited: {
            if (root.backend === "backlight") {
                if (root.backlightPending !== root.backlightActive)
                    writeTimer.restart();
                else
                    settleTimer.restart();
            } else if (Object.keys(root.pending).length > 0) {
                writeTimer.restart();
            } else {
                settleTimer.restart();
            }
        }
    }

    Timer {
        interval: 8000
        running: root.watching
        repeat: true
        onTriggered: if (!writeProcess.running && !writeTimer.running && !settleTimer.running)
            root.startQuery()
    }

    Timer {
        id: writeTimer

        interval: 180
        onTriggered: root.flushWrite()
    }

    Timer {
        id: settleTimer

        interval: 1200
        onTriggered: root.startQuery()
    }
}
