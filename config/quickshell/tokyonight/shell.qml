import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Eigene Module (liegen in modules/ neben dieser Datei)
import "modules"

ShellRoot {
    id: shell

    property int cpuUsage: 0
    property string ramText: "-/-"
    property int gpuUsage: 0

    property int cpuTemp: 0
    property int gpuTemp: 0
    property string gpuVram: "-/-"
    property int cpuThrottle: 0
    property int gpuThrottle: 0
    property bool throttleActive: false
    property bool blinkOn: false

    property string currentTime: ""

    // Popups
    property bool calendarOpen: false
    property bool clipboardOpen: false

    // Wird vom MediaPlayer gesetzt: laeuft gerade ein Player mit Steuerung?
    property bool hasPlayer: false

    // =========================
    // BLINKEN BEI THROTTLING
    // =========================

    Timer {
        interval: 500
        running: throttleActive
        repeat: true

        onTriggered: {
            blinkOn = !blinkOn
        }

        onRunningChanged: {
            if (!running)
                blinkOn = false
        }
    }

    // =========================
    // UHR
    // =========================

    Timer {
        interval: 1000
        running: true
        repeat: true

        onTriggered: {
            currentTime = Qt.formatDateTime(
                new Date(),
                                            "ddd dd.MM  HH:mm"
            )
        }
    }

    // =========================
    // HARDWARE ABFRAGE
    // =========================

    Process {
        id: statsProcess

        command: [
            "bash",
            "-c",

            "read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat; " +
            "IDLE1=$((idle+iowait)); " +
            "TOTAL1=$((user+nice+system+idle+iowait+irq+softirq+steal)); " +

            "sleep 0.5; " +

            "read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat; " +
            "IDLE2=$((idle+iowait)); " +
            "TOTAL2=$((user+nice+system+idle+iowait+irq+softirq+steal)); " +

            "DIFF_IDLE=$((IDLE2-IDLE1)); " +
            "DIFF_TOTAL=$((TOTAL2-TOTAL1)); " +

            "if [ \"$DIFF_TOTAL\" -gt 0 ]; then " +
            "CPU=$((100*(DIFF_TOTAL-DIFF_IDLE)/DIFF_TOTAL)); " +
            "else CPU=0; fi; " +

            // RAM in GB (genutzt/gesamt, z.B. 4,2/15,6)
            "RAMUSEDKB=$(awk " +
            "'/MemTotal:/ {total=$2} " +
            "/MemAvailable:/ {avail=$2} " +
            "END {if(total>0) print total-avail; else print 0}' " +
            "/proc/meminfo); " +

            "RAMTOTALKB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo); " +

            "if [ -n \"$RAMUSEDKB\" ] && [ -n \"$RAMTOTALKB\" ] && [ \"$RAMTOTALKB\" -gt 0 ]; then " +
            "RAMUSEDGB=$(awk -v u=\"$RAMUSEDKB\" 'BEGIN {printf \"%.1f\", u/1024/1024}'); " +
            "RAMTOTALGB=$(awk -v t=\"$RAMTOTALKB\" 'BEGIN {printf \"%.1f\", t/1024/1024}'); " +
            "RAM=\"$(echo \"$RAMUSEDGB\" | tr '.' ',')/$(echo \"$RAMTOTALGB\" | tr '.' ',')\"; " +
            "else RAM=\"-/-\"; fi; " +

            // NVIDIA GPU: Auslastung, Temp, VRAM + Thermisches Drosseln - EIN Aufruf
            "GPU_LINE=$(nvidia-smi " +
            "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,clocks_throttle_reasons.hw_thermal_slowdown,clocks_throttle_reasons.sw_thermal_slowdown " +
            "--format=csv,noheader,nounits 2>/dev/null | head -n1); " +

            "IFS=, read GPU GPUTEMP VRAMUSED VRAMTOTAL THRMHW THRMSW <<< \"$(echo \"$GPU_LINE\" | tr -d ' ')\"; " +

            "if [ -n \"$VRAMUSED\" ] && [ -n \"$VRAMTOTAL\" ] && [ \"$VRAMTOTAL\" -gt 0 ]; then " +
            "VRAMGB=$(awk -v u=\"$VRAMUSED\" 'BEGIN {printf \"%.1f\", u/1024}'); " +
            "VRAM_TOTAL_GB=$((VRAMTOTAL/1024)); " +
            "VRAM=\"$(echo \"$VRAMGB\" | tr '.' ',')/$VRAM_TOTAL_GB\"; " +
            "else VRAM=\"-/-\"; fi; " +

            // NVIDIA Throttle: HW-Slowdown (echte Thermik) oder SW-Slowdown aktiv
            "if [ \"$THRMHW\" = \"Active\" ] || [ \"$THRMSW\" = \"Active\" ]; then " +
            "GPUTHR=1; else GPUTHR=0; fi; " +

            // CPU Temperatur
            "CPUTEMP=0; " +

            "for f in /sys/class/hwmon/hwmon*/temp*_label; do " +
            "LABEL=$(cat \"$f\" 2>/dev/null); " +

            "if echo \"$LABEL\" | grep -qiE 'Tctl|Tdie|hotspot'; then " +
            "INPUT=\"${f%_label}_input\"; " +
            "VALUE=$(cat \"$INPUT\" 2>/dev/null); " +

            "if [ -n \"$VALUE\" ]; then " +
            "CPUTEMP=$((VALUE/1000)); " +
            "break; " +
            "fi; " +

            "fi; " +
            "done; " +

            // CPU Throttle-Proxy: Tctl >= 88°C UND langsamster Boost aller Kerne
            "MAXF=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null); " +
            "CURMAX=0; " +
            "for cf in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do " +
            "v=$(cat \"$cf\" 2>/dev/null); " +
            "[ -n \"$v\" ] && [ \"$v\" -gt \"$CURMAX\" ] && CURMAX=$v; " +
            "done; " +
            "if [ \"$MAXF\" -gt 0 ] && [ \"$CURMAX\" -gt 0 ] && [ \"$CPUTEMP\" -ge 88 ] && [ $((CURMAX*100/MAXF)) -lt 80 ]; then " +
            "CPUTHR=1; else CPUTHR=0; fi; " +

            "echo \"${CPU:-0} ${RAM:-0} ${GPU:-0} ${CPUTEMP:-0} ${GPUTEMP:-0} ${VRAM:-} ${CPUTHR:-0} ${GPUTHR:-0}\""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                let output = text.trim()

                console.log("Hardware:", output)

                let values = output.split(/\s+/)

                if (values.length >= 8) {
                    let cpu = Number(values[0])
                    let ram = String(values[1])
                    let gpu = Number(values[2])
                    let cputemp = Number(values[3])
                    let gputemp = Number(values[4])
                    let vram = String(values[5])
                    let cputhr = Number(values[6])
                    let gputhr = Number(values[7])

                    if (!isNaN(cpu))
                        cpuUsage = Math.max(0, Math.min(100, cpu))

                    if (ram !== "")
                        ramText = ram

                    if (!isNaN(gpu))
                        gpuUsage = Math.max(0, Math.min(100, gpu))

                    if (!isNaN(cputemp))
                        cpuTemp = cputemp

                    if (!isNaN(gputemp))
                        gpuTemp = gputemp

                    if (vram !== "")
                        gpuVram = vram

                    if (!isNaN(cputhr))
                        cpuThrottle = cputhr ? 1 : 0

                    if (!isNaN(gputhr))
                        gpuThrottle = gputhr ? 1 : 0

                    throttleActive = cpuThrottle === 1 || gpuThrottle === 1
                }
            }
        }
    }

    // =========================
    // HARDWARE AKTUALISIEREN
    // =========================

    Timer {
        interval: 2000
        running: true
        repeat: true

        onTriggered: {
            if (!statsProcess.running)
                statsProcess.running = true
        }
    }

    // =========================
    // ERSTE ABFRAGE
    // =========================

    Timer {
        interval: 500
        running: true
        repeat: false

        onTriggered: {
            statsProcess.running = true
        }
    }

    // =========================
    // UHR INITIALISIEREN
    // =========================

    Component.onCompleted: {
        currentTime = Qt.formatDateTime(
            new Date(),
                                        "ddd dd.MM  HH:mm"
        )
    }

    // =========================
    // EIN PANEL PRO MONITOR
    // =========================

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar

            required property var modelData

            // Breite des jeweiligen Monitors. Hochkant (DVI-I-2) hat
            // nur 1200 px - dort braucht die rechte Reihe ein
            // kompakteres Layout, sonst laeuft sie ueber.
            readonly property bool narrow: modelData.width < 1400

            screen: modelData

            // HDMI-A-1 = Hauptmonitor
            // Dort KEINE Leiste
            visible: modelData.name !== "HDMI-A-1"

            anchors {
                bottom: true
                left: true
                right: true
            }

            implicitHeight: 40

            // Transluzent + Blur hinter der Leiste (ext-background-effect-v1):
            // KWin 6.7+ unterstuetzt das Protokoll, Quickshell 0.3.1 hat den
            // BackgroundEffect-Typ. Transparent = Blur sieht man.
            color: "#b316161e"

            // KEINE Exklusivzone: Fenster/Apps laufen unter der Leiste durch
            // und werden hinter ihr geblurrt. (Auto wuerde unten Platz
            // reservieren -> Apps stoppen an der Leistenkante.)
            exclusionMode: ExclusionMode.Ignore

            BackgroundEffect.blurRegion: Region {
                item: bar.contentItem
            }

            // =========================
            // UHR (klickbar -> Kalender)
            // =========================

            Rectangle {
                id: clockButton

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 6

                width: clockText.implicitWidth + 24
                height: parent.height - 8
                radius: 5

                color: clockHover.hovered
                    ? "#1f2335"
                    : (shell.calendarOpen ? "#1f2335" : "transparent")

                Behavior on color {
                    ColorAnimation { duration: 90 }
                }

                Text {
                    id: clockText

                    anchors.centerIn: parent

                    text: currentTime

                    color: throttleActive && blinkOn ? "#f7768e" : "#c0caf5"

                    font.pixelSize: 13
                    font.family: "JetBrains Mono"
                }

                HoverHandler {
                    id: clockHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: {
                        shell.clipboardOpen = false
                        shell.calendarOpen = !shell.calendarOpen
                    }
                }
            }

            // =========================
            // CLIPBOARD-TRIGGER
            // =========================

            Rectangle {
                anchors.left: clockButton.right
                anchors.verticalCenter: parent.verticalCenter

                width: 26
                height: parent.height - 8
                radius: 5

                color: clipHover.hovered
                    ? "#1f2335"
                    : (shell.clipboardOpen ? "#1f2335" : "transparent")

                Behavior on color {
                    ColorAnimation { duration: 90 }
                }

                Text {
                    anchors.centerIn: parent

                    text: "⎘"
                    color: shell.clipboardOpen ? "#7aa2f7" : "#565f89"

                    font.pixelSize: 15
                    font.family: "JetBrains Mono"
                }

                HoverHandler {
                    id: clipHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: {
                        shell.calendarOpen = false
                        shell.clipboardOpen = !shell.clipboardOpen
                    }
                }
            }

            // ============================================================
            // SYSTEM-TRAY
            // ============================================================

            SystemTray {
                id: tray

                anchors.left: parent.left
                anchors.leftMargin: 200
                anchors.verticalCenter: parent.verticalCenter

                width: Math.min(300, Math.max(0, parent.width * 0.22))
                height: parent.height - 8
            }

            // =========================
            // THERMAL THROTTLING
            // =========================

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                text: cpuThrottle === 1 && gpuThrottle === 1
                      ? "Thermal Throttling · CPU+GPU"
                      : cpuThrottle === 1 ? "Thermal Throttling · CPU" : "Thermal Throttling · GPU"

                color: blinkOn ? "#f7768e" : "#e0af68"

                visible: throttleActive

                font.bold: true
                font.pixelSize: 13
                font.family: "JetBrains Mono"
            }

            // ============================================================
            // AUDIO-VISUALIZER (PipeWire-Peaks, kein cava)
            // ============================================================
            // RECHTE SEITE: Hardware -> Visualizer -> | -> Media-Player
            // Eine einzige Row, damit die Anker nicht zirkulaer sind.
            // ============================================================

            Row {
                id: rightSide

                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter

                spacing: 18

                // --- Hardware (unveraendert) ---

                Text {
                    text: "CPU: " + shell.cpuUsage + "% " + shell.cpuTemp + "°C"

                    color: "#7aa2f7"

                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                }

                Text {
                    text: "RAM: " + shell.ramText + " GB"

                    color: "#bb9af7"

                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                }

                Text {
                    text: "GPU: " + shell.gpuUsage + "% " + shell.gpuTemp + "°C"

                    color: "#9ece6a"

                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                }

                Text {
                    text: "VRAM: " + shell.gpuVram + " GB"

                    color: "#7dcfff"

                    font.pixelSize: 12
                    font.family: "JetBrains Mono"
                }

                // --- Visualizer (PipeWire-Peaks, kein cava) ---
                // Breite anpassen, sonst laeuft die Balkenreihe ueber

                Visualizer {
                    width: bar.narrow ? 76 : 120
                    height: 22
                }

                // Unsichtbarer Trennraum: Visualizer und Media-Widget
                // duerfen optisch nicht zusammenwaechsen
                Item {
                    width: bar.narrow ? 6 : 16
                    height: 1
                }

                // --- Media-Player: transparent in die Leiste eingearbeitet ---
                // Erscheint nur, wenn ein Player existiert; schlaeft mit
                // Breite 0, damit die Reihe keine Leere hinterlaesst.
                // narrow = Hochkant-Monitor mit nur 1200 px.

                MediaPlayer {
                    id: mediaModule

                    width: shell.hasPlayer ? (bar.narrow ? 248 : 320) : 0
                    height: prefHeight

                    opacity: shell.hasPlayer ? 1 : 0
                    visible: opacity > 0

                    onPlayerChanged: (active) => {
                        shell.hasPlayer = active
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                    Behavior on width {
                        NumberAnimation { duration: 150 }
                    }
                }
            }

            // ============================================================
            // POPUPS
            // ============================================================

            // Overlay-Ebene ueber der Leiste, damit Klicks durch gehen
            Item {
                id: overlay

                anchors.fill: parent

                // Kalender
                Calendar {
                    id: calendarModule

                    anchors.fill: parent

                    open: shell.calendarOpen

                    onCloseRequested: shell.calendarOpen = false
                }

                // Zwischenablage
                Clipboard {
                    id: clipboardModule

                    anchors.fill: parent

                    open: shell.clipboardOpen

                    onCloseRequested: shell.clipboardOpen = false
                }
            }
        }
    }
}
