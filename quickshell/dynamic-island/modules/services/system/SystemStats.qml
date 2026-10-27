pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// Auslastung und Temperaturen aus /proc und /sys.
//
// Quickshell bringt dafuer nichts mit, also wird ohne kompiliertes Plugin
// direkt gelesen. Ein einziger Aufruf pro Takt
// holt alles und gibt Zeilen mit Praefix aus – dasselbe Muster wie der
// WLAN-Scan in services/network/Network.qml.
//
// Der Takt laeuft NUR, solange jemand hinsieht (`watching`, gesetzt per
// Binding aus der Karte). Zugeklappt kostet dieser Dienst nichts.
//
// Die hwmon-Nummern sind nicht stabil – deshalb wird ueber `name` gesucht
// (k10temp, amdgpu, nvme, kraken) statt Pfade festzunageln.
//
// Benutzung:  import qs.modules.services.system
Singleton {
    id: root

    // Die Oberflaeche schaltet das ein, solange die Karte offen ist
    // Anforderungen per DemandRequest (je Monitor eine), siehe core/Demand.qml
    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active
    property bool loaded: false

    // ---- CPU ----
    property real cpuUsage: 0        // 0…1
    property real cpuTemp: 0         // °C, 0 = unbekannt
    property string cpuName: ""

    // ---- Speicher ----
    property real memUsed: 0         // Bytes
    property real memTotal: 0

    // ---- Grafik ----
    property bool hasGpu: false
    property real gpuUsage: 0        // 0…1
    property real gpuTemp: 0
    property real vramUsed: 0
    property real vramTotal: 0

    // ---- Platte ----
    property real diskUsed: 0
    property real diskTotal: 0
    // Getrennt gefuehrt: "Groesse minus belegt" waere zu gross, weil ein Teil
    // fuer root reserviert ist (df zeigt deshalb weniger frei an)
    property real diskFree: 0

    // ---- weitere Temperaturen ----
    property var nvmeTemps: []       // [°C, …]
    property real waterTemp: 0       // Wasserkuehlung, 0 = keine

    // Fuer die Differenz der CPU-Zeiten zwischen zwei Takten
    property var prevCpu: null

    function formatBytes(bytes: real): string {
        if (!bytes || bytes < 0)
            return "–";
        const gb = bytes / 1024 / 1024 / 1024;
        if (gb >= 10)
            return `${Math.round(gb)} GB`;
        if (gb >= 1)
            return `${gb.toFixed(1)} GB`;
        return `${Math.round(bytes / 1024 / 1024)} MB`;
    }

    function formatTemp(celsius: real): string {
        return celsius > 0 ? `${Math.round(celsius)} °C` : "–";
    }

    function refresh(): void {
        if (!poll.running)
            poll.running = true;
    }

    // Einmalig: der Prozessorname, gekuerzt um die ueblichen Floskeln
    Process {
        id: nameProc

        running: true
        command: ["sh", "-c", "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2"]

        stdout: StdioCollector {
            onStreamFinished: root.cpuName = text.trim()
                .replace(/\(R\)|\(TM\)|\(r\)|\(tm\)/g, "")
                .replace(/ CPU| Processor| \d+-Core/g, "")
                .replace(/\s+/g, " ")
                .trim()
        }
    }

    Process {
        id: poll

        command: ["sh", "-c",
            // Temperaturen: hwmon ueber den Namen finden, nicht ueber die Nummer
            'for h in /sys/class/hwmon/hwmon*; do'
            + '   n=$(cat "$h/name" 2>/dev/null); t=$(cat "$h/temp1_input" 2>/dev/null);'
            + '   [ -n "$t" ] || continue;'
            + '   case "$n" in'
            + '     k10temp|coretemp|zenpower|acpitz) echo "T cpu $t";;'
            + '     amdgpu|nouveau|radeon) echo "T gpu $t";;'
            + '     nvme) echo "T nvme $t";;'
            + '     kraken*|nzxt*|liquidctl*) echo "T water $t";;'
            + '   esac;'
            + ' done;'
            + ' echo "S $(head -1 /proc/stat)";'
            + ' awk \'/^MemTotal:|^MemAvailable:/ { print "M", $1, $2 }\' /proc/meminfo;'
            + ' for c in /sys/class/drm/card*/device; do'
            + '   [ -f "$c/gpu_busy_percent" ] && echo "G busy $(cat "$c/gpu_busy_percent")";'
            + '   [ -f "$c/mem_info_vram_used" ] &&'
            + '     echo "G vram $(cat "$c/mem_info_vram_used") $(cat "$c/mem_info_vram_total")";'
            + ' done;'
            + ' df -B1 --output=used,size,avail / 2>/dev/null | tail -1 | sed "s/^/D /"']

        stdout: StdioCollector {
            onStreamFinished: {
                const nvme = [];
                let water = 0;
                let gpuSeen = false;
                let memTotal = 0;
                let memAvail = 0;

                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 2)
                        continue;

                    switch (f[0]) {
                    case "T": {
                        // millidegrees -> °C
                        const c = Number(f[2]) / 1000;
                        if (!isFinite(c))
                            break;
                        if (f[1] === "cpu")
                            root.cpuTemp = c;
                        else if (f[1] === "gpu") {
                            root.gpuTemp = c;
                            gpuSeen = true;
                        } else if (f[1] === "nvme")
                            nvme.push(c);
                        else if (f[1] === "water")
                            water = c;
                        break;
                    }

                    case "S": {
                        // cpu user nice system idle iowait irq softirq steal …
                        const v = f.slice(2).map(Number);
                        if (v.some(isNaN) || v.length < 5)
                            break;
                        const total = v.reduce((a, b) => a + b, 0);
                        const idle = v[3] + v[4];
                        const prev = root.prevCpu;
                        if (prev) {
                            const dTotal = total - prev.total;
                            const dIdle = idle - prev.idle;
                            if (dTotal > 0)
                                root.cpuUsage = Math.max(0, Math.min(1, 1 - dIdle / dTotal));
                        }
                        root.prevCpu = { total, idle };
                        break;
                    }

                    case "M":
                        if (f[1] === "MemTotal:")
                            memTotal = Number(f[2]) * 1024;
                        else if (f[1] === "MemAvailable:")
                            memAvail = Number(f[2]) * 1024;
                        break;

                    case "G":
                        if (f[1] === "busy") {
                            root.gpuUsage = Math.max(0, Math.min(1, Number(f[2]) / 100));
                            gpuSeen = true;
                        } else if (f[1] === "vram" && f.length >= 4) {
                            root.vramUsed = Number(f[2]);
                            root.vramTotal = Number(f[3]);
                            gpuSeen = true;
                        }
                        break;

                    case "D":
                        if (f.length >= 4) {
                            root.diskUsed = Number(f[1]);
                            root.diskTotal = Number(f[2]);
                            root.diskFree = Number(f[3]);
                        }
                        break;
                    }
                }

                // Lieber beim alten Wert bleiben als das Layout mit NaN
                // zerlegen (dieselbe Vorsicht wie in HyprGaps.qml)
                if (memTotal > 0 && !isNaN(memAvail)) {
                    root.memTotal = memTotal;
                    root.memUsed = memTotal - memAvail;
                }

                root.nvmeTemps = nvme;
                root.waterTemp = water;
                root.hasGpu = gpuSeen;
                root.loaded = true;
            }
        }
    }

    Timer {
        interval: 2000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
