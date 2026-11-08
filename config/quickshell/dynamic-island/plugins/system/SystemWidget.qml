pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import qs
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.services.system

// Systemmonitor auf dem Desktop, in der Sprache der Notch: frei auf dem
// Wallpaper, monochrom in `color`, der Akzent nur als Fuellung. Stile:
//
//   ringe    Kreis-Anzeigen (CPU, GPU, RAM, Platte), Prozent in der Mitte,
//            Versalien-Label darunter, Temperatur bzw. Belegung klein dazu
//   balken   schmale Balken, Label links, Wert und Detail rechts
//   zeilen   rein typografisch: grosse Zahlen (Inter Display), kleine Label
//
// Daten aus SystemStats (dieselben Werte wie die Statuskarte der Leiste).
// Der Dienst pollt nur, solange ihn jemand anfordert – hier nur bei
// `active`. Die gezeigten Werte sind eine Momentaufnahme, die nur bei
// `active` nachgefuehrt wird: ist der Desktop verdeckt, aendert sich hier
// nichts, also zeichnet auch nichts neu (die Karte der Leiste koennte den
// Dienst sonst weiter treiben).
//
// Ringe aus QtQuick.Shapes (PathAngleArc), kein Canvas. Wertwechsel (alle
// 2 s) laufen kurz weich an, dauerhaft bewegt sich nichts. Der Schatten
// haengt wie bei der Uhr an einer Layer-Textur – sie zeichnet nur bei
// einem Wertwechsel neu, also einmal je Takt plus die kurze Animation.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property string style: root.opts.style ?? "ringe"
    readonly property bool showGpu: (root.opts.gpu ?? true) && SystemStats.hasGpu
    readonly property bool showTemps: root.opts.temps ?? true
    readonly property bool showDisk: root.opts.disk ?? false

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property color dim: Colors.alpha(root.color, 0.6)
    readonly property color track: Colors.alpha(root.color, 0.16)

    // Welche Anzeigen stehen – aendert sich nur mit den Optionen
    readonly property var metrics: {
        const m = ["cpu"];
        if (root.showGpu)
            m.push("gpu");
        m.push("mem");
        if (root.showDisk)
            m.push("disk");
        return m;
    }

    implicitWidth: body.width
    implicitHeight: body.height

    DemandRequest {
        demand: SystemStats.demand
        active: root.active
    }

    // ---- Momentaufnahme der Werte ----
    property real cpu: 0
    property real gpu: 0
    property real mem: 0
    property real disk: 0
    property real cpuTemp: 0
    property real gpuTemp: 0
    property string memText: ""
    property string vramText: ""
    property string diskText: ""
    property string extraTemps: ""

    // Bewusst ohne Behavior: eine weiche Wertanimation zeichnet alle 2 s den
    // Schatten-Layer ~80x neu (180-Hz-Monitor) – gemessen 2 % statt 0,13 % CPU

    function sync(): void {
        if (!root.active)
            return;
        const s = SystemStats;
        root.cpu = s.cpuUsage;
        root.gpu = s.gpuUsage;
        root.mem = s.memTotal > 0 ? s.memUsed / s.memTotal : 0;
        root.disk = s.diskTotal > 0 ? s.diskUsed / s.diskTotal : 0;
        root.cpuTemp = s.cpuTemp;
        root.gpuTemp = s.gpuTemp;
        root.memText = s.memTotal > 0 ? `${s.formatBytes(s.memUsed)} / ${s.formatBytes(s.memTotal)}` : "";
        root.vramText = s.vramTotal > 0 ? `${s.formatBytes(s.vramUsed)} VRAM` : "";
        root.diskText = s.diskTotal > 0 ? I18n.tr("%1 frei").arg(s.formatBytes(s.diskFree)) : "";
        const parts = [];
        for (const t of s.nvmeTemps)
            parts.push(`SSD ${Math.round(t)} °C`);
        if (s.waterTemp > 0)
            parts.push(I18n.tr("Wasser %1 °C").arg(Math.round(s.waterTemp)));
        root.extraTemps = parts.join("  ·  ");
    }

    // Der Dienst setzt je Takt viele Werte nacheinander – einmal gesammelt
    // nachziehen statt bei jedem einzelnen
    function schedule(): void {
        Qt.callLater(root.sync);
    }

    onActiveChanged: if (root.active) root.sync()
    Component.onCompleted: root.sync()

    Connections {
        target: SystemStats
        enabled: root.active

        function onCpuUsageChanged(): void { root.schedule(); }
        function onMemUsedChanged(): void { root.schedule(); }
        function onGpuUsageChanged(): void { root.schedule(); }
        function onVramUsedChanged(): void { root.schedule(); }
        function onDiskUsedChanged(): void { root.schedule(); }
        function onCpuTempChanged(): void { root.schedule(); }
        function onGpuTempChanged(): void { root.schedule(); }
        function onNvmeTempsChanged(): void { root.schedule(); }
        function onWaterTempChanged(): void { root.schedule(); }
    }

    // ---- Zugriff je Anzeige ----
    function valueOf(key: string): real {
        switch (key) {
        case "cpu": return root.cpu;
        case "gpu": return root.gpu;
        case "mem": return root.mem;
        case "disk": return root.disk;
        }
        return 0;
    }

    function labelOf(key: string): string {
        return ({ cpu: "CPU", gpu: "GPU", mem: "RAM", disk: I18n.tr("PLATTE") })[key] ?? key;
    }

    // Kleine Zeile unter/neben dem Wert: Temperatur bei CPU/GPU (oder VRAM,
    // wenn Temperaturen aus sind), Belegung bei RAM, Freiraum bei Platte
    function detailOf(key: string): string {
        switch (key) {
        case "cpu": return root.showTemps ? SystemStats.formatTemp(root.cpuTemp) : "";
        case "gpu": return root.showTemps ? SystemStats.formatTemp(root.gpuTemp) : root.vramText;
        case "mem": return root.memText;
        case "disk": return root.diskText;
        }
        return "";
    }

    // Dezente Warnung: nur ueber die Farbe der Detailzeile
    function warnOf(key: string): bool {
        switch (key) {
        case "cpu": return root.cpuTemp >= 80;
        case "gpu": return root.gpuTemp >= 85;
        case "mem": return root.mem >= 0.9;
        case "disk": return root.disk >= 0.95;
        }
        return false;
    }

    function percent(v: real): string {
        return `${Math.round(v * 100)}`;
    }

    // ---- Bausteine ----

    // Versalien-Zeile, optional mit Akzentpunkt (Kopfzeile wie in der Notch)
    component Caption: Row {
        id: cap

        property string text: ""
        property bool dot: false
        property real px: root.unit * 0.7
        property color tint: root.dim

        spacing: cap.px * 0.6

        Rectangle {
            visible: cap.dot
            anchors.verticalCenter: parent.verticalCenter
            width: cap.px * 0.5
            height: width
            radius: width / 2
            color: root.accent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: cap.text
            color: cap.tint
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.DemiBold
        }
    }

    // Zahl im Display-Schnitt, Ziffern gleich breit
    component Digits: Text {
        property real px: root.unit * 1.4
        property int w: Font.DemiBold

        color: root.color
        font.family: root.display
        font.pixelSize: px
        font.weight: w
        font.letterSpacing: -px * 0.03
        font.features: ({ "tnum": 1 })
    }

    // Kleine Detailzeile (Temperatur, Belegung)
    component Detail: Text {
        property bool warn: false

        color: warn ? Colors.error : root.dim
        font.family: Config.font
        font.pixelSize: root.unit * 0.7
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    // Kopfzeile: Prozessorname, sonst "System"
    component Header: Caption {
        text: SystemStats.cpuName !== "" ? SystemStats.cpuName : "System"
        dot: true
        px: root.unit * 0.7
        tint: Colors.alpha(root.color, 0.72)
    }

    // Was sonst noch Temperatur hat (SSD, Wasser)
    component Extras: Text {
        visible: root.showTemps && root.extraTemps !== ""
        text: root.extraTemps
        color: root.dim
        font.family: Config.font
        font.pixelSize: root.unit * 0.7
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    // ---- Inhalt + Schatten ----
    Item {
        id: body

        width: content.implicitWidth
        height: content.implicitHeight

        Item {
            id: content

            implicitWidth: loader.item?.implicitWidth ?? 0
            implicitHeight: loader.item?.implicitHeight ?? 0
            layer.enabled: true
            visible: false

            Loader {
                id: loader

                sourceComponent: root.style === "balken" ? bars
                               : root.style === "zeilen" ? lines
                               : rings
            }
        }

        MultiEffect {
            source: content
            anchors.fill: content
            shadowEnabled: true
            shadowColor: "#000000"
            // Etwas straffer als bei der Uhr: duenne Schrift und Ringe
            // brauchen einen engeren Schatten, um sich abzuheben
            shadowOpacity: 0.5
            shadowBlur: 0.7
            shadowVerticalOffset: Math.round(root.unit * 0.15)
            blurMax: 48
            autoPaddingEnabled: true
        }
    }

    // ---- Ringe ----
    Component {
        id: rings

        Column {
            spacing: root.unit * 1.0

            Header {
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.unit * 1.5

                Repeater {
                    model: root.metrics

                    Column {
                        id: gauge

                        required property string modelData

                        readonly property real v: root.valueOf(gauge.modelData)
                        readonly property real d: root.unit * 4.8
                        readonly property real sw: Math.max(3, root.unit * 0.42)

                        spacing: root.unit * 0.5

                        Item {
                            width: gauge.d
                            height: gauge.d

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                // Spur
                                ShapePath {
                                    strokeColor: root.track
                                    strokeWidth: gauge.sw
                                    fillColor: "transparent"

                                    PathAngleArc {
                                        centerX: gauge.d / 2
                                        centerY: gauge.d / 2
                                        radiusX: gauge.d / 2 - gauge.sw / 2
                                        radiusY: radiusX
                                        startAngle: 0
                                        sweepAngle: 360
                                    }
                                }

                                // Wert, von oben im Uhrzeigersinn
                                ShapePath {
                                    strokeColor: root.accent
                                    strokeWidth: gauge.sw
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap

                                    PathAngleArc {
                                        centerX: gauge.d / 2
                                        centerY: gauge.d / 2
                                        radiusX: gauge.d / 2 - gauge.sw / 2
                                        radiusY: radiusX
                                        startAngle: -90
                                        sweepAngle: Math.max(1, Math.min(359, gauge.v * 360))
                                    }
                                }
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 1

                                Digits {
                                    id: big

                                    text: root.percent(gauge.v)
                                    px: root.unit * 1.35
                                }

                                Text {
                                    anchors.baseline: big.baseline
                                    text: "%"
                                    color: root.dim
                                    font.family: Config.font
                                    font.pixelSize: root.unit * 0.7
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Caption {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.labelOf(gauge.modelData)
                            tint: Colors.alpha(root.color, 0.8)
                        }

                        Detail {
                            anchors.horizontalCenter: parent.horizontalCenter
                            // Platz bleibt reserviert, damit alle Ringe gleich hoch stehen
                            text: root.detailOf(gauge.modelData) || " "
                            warn: root.warnOf(gauge.modelData)
                        }
                    }
                }
            }

            Extras {
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ---- Balken ----
    Component {
        id: bars

        Column {
            id: list

            readonly property real w: root.unit * 20
            readonly property real labelW: root.unit * 4.4
            readonly property real valueW: root.unit * 2.6
            readonly property real detailW: root.unit * 5.2

            spacing: root.unit * 0.8

            Header {}

            Repeater {
                model: root.metrics

                Item {
                    id: row

                    required property string modelData

                    readonly property real v: root.valueOf(row.modelData)

                    width: list.w
                    height: root.unit * 1.3

                    Caption {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.labelOf(row.modelData)
                        tint: Colors.alpha(root.color, 0.8)
                    }

                    // Spur + Fuellung; ganze Pixel, damit die Animation nicht
                    // bei jedem Subpixel neu zeichnet
                    Rectangle {
                        id: trackBar

                        x: list.labelW
                        anchors.verticalCenter: parent.verticalCenter
                        width: list.w - list.labelW - list.valueW - list.detailW - root.unit * 1.6
                        height: Math.max(3, Math.round(root.unit * 0.3))
                        radius: height / 2
                        color: root.track

                        Rectangle {
                            width: Math.max(height, Math.round(trackBar.width * row.v))
                            height: parent.height
                            radius: height / 2
                            color: root.accent
                        }
                    }

                    Digits {
                        x: trackBar.x + trackBar.width + root.unit * 0.8
                        width: list.valueW
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.percent(row.v) + " %"
                        px: root.unit * 1.0
                    }

                    Detail {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: list.detailW
                        horizontalAlignment: Text.AlignRight
                        text: root.detailOf(row.modelData)
                        warn: root.warnOf(row.modelData)
                        elide: Text.ElideLeft
                    }
                }
            }

            Extras {
                topPadding: root.unit * 0.2
            }
        }
    }

    // ---- Zeilen: nur Typografie ----
    Component {
        id: lines

        Column {
            spacing: root.unit * 0.9

            Header {}

            Row {
                spacing: root.unit * 2.2

                Repeater {
                    model: root.metrics

                    Column {
                        id: cell

                        required property string modelData

                        readonly property real v: root.valueOf(cell.modelData)

                        spacing: root.unit * 0.25

                        Row {
                            spacing: root.unit * 0.15

                            Digits {
                                id: num

                                text: root.percent(cell.v)
                                px: root.unit * 3.0
                            }

                            Text {
                                anchors.baseline: num.baseline
                                text: "%"
                                color: root.dim
                                font.family: root.display
                                font.pixelSize: root.unit * 1.2
                                font.weight: Font.Medium
                            }
                        }

                        Caption {
                            text: root.labelOf(cell.modelData)
                            tint: Colors.alpha(root.color, 0.8)
                        }

                        Detail {
                            text: root.detailOf(cell.modelData) || " "
                            warn: root.warnOf(cell.modelData)
                        }
                    }
                }
            }

            Extras {}
        }
    }
}
