pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.core
import qs.modules.services.config

// Feste Systemdaten fuer die Systemseite (SystemEditor): Rechner (Hostname,
// Geraet, Distribution, Kernel, Firmware, CPU, GPU, RAM, Pakete) und die
// Software-Staende (CLI, Quickshell, Qt, Hyprland). Ein einziger
// Lesevorgang, sobald jemand hinsieht (`watching` per DemandRequest, Muster
// SystemStats); die Laufzeit tickt nur bei offener Ansicht im Minutentakt.
//
// Der Stand der Shell selbst (Git) und ihr Update stehen in ShellUpdate.qml.
//
// Benutzung:  import qs.modules.services.system
Singleton {
    id: root

    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active

    property bool loaded: false

    // ---- Rechner ----
    property string distro: ""
    property string distroId: ""
    property string kernel: ""
    property string hostname: ""
    property string device: ""         // Hersteller + Modell (DMI), "" = unbekannt (VM)
    property string firmware: ""       // BIOS/UEFI-Version (+ Datum)
    property string cpuName: ""
    property string gpuName: ""
    property real memTotal: 0          // Bytes
    property int packages: 0           // pacman
    property int flatpaks: 0           // flatpak --app, 0 = keins/nicht da
    property bool hasFlatpak: false
    property real uptime: 0            // Sekunden

    // ---- Software ----
    property string hyprland: ""
    property string quickshell: ""     // "0.3.2"
    property string qt: ""             // "6.12.0"
    property string cliVersion: ""     // aus rust/cli/Cargo.toml
    property string cliKind: ""        // "Rust" oder "Python" – was ~/.local/bin/dynamic-island ist

    function formatUptime(seconds: real): string {
        const m = Math.floor(seconds / 60);
        const d = Math.floor(m / 1440);
        const h = Math.floor((m % 1440) / 60);
        const min = m % 60;
        if (d > 0)
            return I18n.tr("%1 Tg. %2 Std.").arg(d).arg(h);
        if (h > 0)
            return I18n.tr("%1 Std. %2 Min.").arg(h).arg(min);
        return I18n.tr("%1 Min.").arg(min);
    }

    function refreshUptime(): void {
        if (!uptimeProc.running)
            uptimeProc.running = true;
    }

    onWatchingChanged: {
        if (!root.watching)
            return;
        if (!root.loaded && !infoProc.running)
            infoProc.running = true;
        root.refreshUptime();
    }

    // ---- feste Daten: ein Aufruf ----
    Process {
        id: infoProc

        command: ["sh", "-c",
            '. /etc/os-release 2>/dev/null; echo "distro ${PRETTY_NAME:-$NAME}"; echo "id ${ID:-}";'
            + ' echo "kernel $(uname -r)"; echo "host $(uname -n)";'
            + ' dmi=/sys/class/dmi/id; echo "vendor $(cat $dmi/sys_vendor 2>/dev/null)"; echo "model $(cat $dmi/product_name 2>/dev/null)";'
            + ' echo "firmware $(cat $dmi/bios_version 2>/dev/null)"; echo "fwdate $(cat $dmi/bios_date 2>/dev/null)";'
            + ' echo "cpu $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2)";'
            + ' echo "gpu $(lspci -mm 2>/dev/null | grep -Ei \'"(VGA|3D|Display)\' | head -1)";'
            + ' echo "mem $(awk \'/^MemTotal:/ { print $2 }\' /proc/meminfo)";'
            + ' echo "hypr $(hyprctl version -j 2>/dev/null | grep -m1 \'"version"\' | cut -d\\" -f4)";'
            + ' echo "qs $(qs --version 2>/dev/null)";'
            + ' echo "qt $(qtpaths6 --qt-version 2>/dev/null || qmake6 -query QT_VERSION 2>/dev/null)";'
            + ' c=$(command -v dynamic-island 2>/dev/null); t=$(readlink -f "$c" 2>/dev/null);'
            + ' case "$t" in *-rs) echo "clikind Rust";; "") ;; *) echo "clikind Python";; esac;'
            + ' [ -n "$t" ] && echo "cliver $(sed -n \'s/^version = "\\(.*\\)"/\\1/p\' "$(dirname "$t")/../rust/cli/Cargo.toml" 2>/dev/null | head -1)";'
            + ' echo "pkgs $(pacman -Qq 2>/dev/null | wc -l)";'
            + ' if command -v flatpak >/dev/null; then echo "flatpak $(flatpak list --app 2>/dev/null | wc -l)"; fi']

        stdout: StdioCollector {
            onStreamFinished: {
                let fwDate = "";
                let vendor = "";
                let model = "";
                for (const line of text.split("\n")) {
                    const i = line.indexOf(" ");
                    if (i < 0)
                        continue;
                    const key = line.slice(0, i);
                    const val = line.slice(i + 1).trim();
                    switch (key) {
                    case "distro": root.distro = val; break;
                    case "id": root.distroId = val; break;
                    case "kernel": root.kernel = val; break;
                    case "host": root.hostname = val; break;
                    case "vendor": vendor = val; break;
                    case "model": model = val; break;
                    case "firmware": root.firmware = val; break;
                    case "fwdate": fwDate = val; break;
                    case "cpu":
                        root.cpuName = val
                            .replace(/\(R\)|\(TM\)|\(r\)|\(tm\)/g, "")
                            .replace(/ CPU| Processor| \d+-Core/g, "")
                            .replace(/\s+/g, " ")
                            .trim();
                        break;
                    case "gpu": {
                        // lspci -mm: Slot "Klasse" "Hersteller" "Geraet" … – der
                        // Geraetename steht als drittes Feld in Anfuehrungszeichen,
                        // die Klammer darin ist der lesbare Name (Radeon 840M …)
                        const q = val.match(/"([^"]*)"/g) ?? [];
                        let name = q.length >= 3 ? q[2].slice(1, -1) : "";
                        const br = name.match(/\[([^\]]+)\]/);
                        if (br)
                            name = br[1];
                        root.gpuName = name.trim();
                        break;
                    }
                    case "mem": root.memTotal = Number(val) * 1024 || 0; break;
                    case "hypr": root.hyprland = val; break;
                    case "qs": {
                        // "Quickshell 0.3.2 (revision …, distributed by …)"
                        const m = val.match(/(\d+(?:\.\d+)+)/);
                        root.quickshell = m ? m[1] : val;
                        break;
                    }
                    case "qt": root.qt = val; break;
                    case "clikind": root.cliKind = val; break;
                    case "cliver": root.cliVersion = val; break;
                    case "pkgs": root.packages = Number(val) || 0; break;
                    case "flatpak":
                        root.hasFlatpak = true;
                        root.flatpaks = Number(val) || 0;
                        break;
                    }
                }
                // Modell wiederholt oft den Hersteller ("HP HP OmniBook …")
                const lowModel = model.toLowerCase();
                root.device = (vendor === "" || lowModel.startsWith(vendor.toLowerCase()) ? model : `${vendor} ${model}`).replace(/\s+/g, " ").trim();
                // DMI liefert das Datum als MM/TT/JJJJ
                const d = fwDate.match(/^(\d\d)\/(\d\d)\/(\d{4})$/);
                if (root.firmware !== "" && d)
                    root.firmware += ` (${d[3]}-${d[1]}-${d[2]})`;
                root.loaded = true;
            }
        }
    }

    Process {
        id: uptimeProc

        command: ["cat", "/proc/uptime"]

        stdout: StdioCollector {
            onStreamFinished: {
                const s = Number(text.trim().split(/\s+/)[0]);
                if (isFinite(s))
                    root.uptime = s;
            }
        }
    }

    Timer {
        interval: 60 * 1000
        running: root.watching
        repeat: true
        onTriggered: root.refreshUptime()
    }
}
