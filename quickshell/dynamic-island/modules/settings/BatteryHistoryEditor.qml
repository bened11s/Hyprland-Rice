pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower

import qs
import qs.modules.services.config
import qs.modules.services.system
import qs.modules.widgets

// Seite "Akku > Akkuverlauf" (Config.meta editor "battery"): je Geraet der
// Ladestand ueber die Zeit plus Kennzahlen. Daten aus BatteryHistory
// (upowerd-Dateien), der Stand von jetzt live aus UPower.
//
// Das Diagramm zeigt eine Reihe, deshalb ohne Legende:
//   Flaeche + Linie       Ladestand, solange das Geraet verbunden war
//   gestrichelt           Luecke (Geraet aus oder schlief) – Verlauf unbekannt
//   getoente Baender      Laden
//   gestrichelte Linie    20 %, ab da warnt die Leiste
// Ueber dem Diagramm zeigt ein Fadenkreuz Zeit und Stand.
Column {
    id: root

    spacing: 12
    bottomPadding: 10

    // ---- Auswahl ----
    property string selectedKey: ""
    // Zeitraum in Stunden, 0 = alles, was upowerd aufgehoben hat
    property int rangeHours: 168
    readonly property var ranges: [
        { hours: 24, label: I18n.tr("24 h") },
        { hours: 72, label: I18n.tr("3 Tage") },
        { hours: 168, label: I18n.tr("7 Tage") },
        { hours: 0, label: I18n.tr("Alles") }
    ]

    // Uhr fuer "jetzt" – jede Minute weiter, damit das Diagramm mitlaeuft
    property double now: Date.now() / 1000

    // Geraete der letzten 30 Tage – die USV vom Sommer braucht keinen Chip
    readonly property var devices: BatteryHistory.devices.filter(d => d.points[d.points.length - 1].t > root.now - 30 * 86400)
    // Gewaehlt (Chip) > angefragt (Klick in der Uebersicht) > das Geraet der
    // Leiste > das zuletzt gesehene
    readonly property var device: root.devices.find(d => d.key === root.selectedKey)
        ?? root.devices.find(d => BatteryHistory.focusModel !== "" && d.aliases.includes(BatteryHistory.focusModel))
        ?? root.devices.find(d => Power.hasBattery && d.aliases.includes(Power.shown?.model ?? ""))
        ?? root.devices[0] ?? null

    Connections {
        target: BatteryHistory
        function onFocusSerialChanged(): void {
            root.selectedKey = "";
        }
    }

    // Das passende Geraet von jetzt (UPower oder Zusatzquelle), null wenn
    // es gerade nicht da ist
    function liveFor(device: var): var {
        if (!device)
            return null;
        for (const d of (UPower.devices?.values ?? []).concat(Power.extraBatteries)) {
            if (d?.isPresent && d.model !== "" && device.aliases.includes(d.model))
                return d;
        }
        return null;
    }
    readonly property var live: root.liveFor(root.device)
    readonly property var livePoint: root.live ? {
        t: root.now,
        v: Math.round(root.live.percentage * 100),
        state: root.live.state === UPowerDeviceState.Charging ? "charging"
             : root.live.state === UPowerDeviceState.FullyCharged ? "fully-charged"
             : "discharging"
    } : null

    function displayName(device: var): string {
        return root.liveFor(device)?.model || device?.name || "";
    }

    function iconFor(device: var): string {
        const live = root.liveFor(device);
        if (live)
            return Power.deviceIcon(live);
        const n = (device?.name ?? "").toLowerCase();
        return n.includes("keyboard") ? "keyboard"
             : n.includes("mouse") || n.includes("g502") || n.includes("g pro") ? "mouse"
             : n.includes("controller") || n.includes("gamepad") ? "sports_esports"
             : n.includes("ups") ? "power"
             : n.includes("headset") || n.includes("buds") || n.includes("arctis") ? "headphones"
             : n.includes("phone") || n.includes("poco") || n.includes("pixel") ? "smartphone"
             : "battery_full";
    }

    // Zeitachse
    readonly property double lastSeen: root.device ? root.device.points[root.device.points.length - 1].t : 0
    readonly property double from: root.rangeHours > 0 ? root.now - root.rangeHours * 3600
                                                      : (root.device ? root.device.points[0].t : root.now - 86400)
    readonly property double to: root.now
    readonly property var stats: BatteryHistory.stats(root.device, root.from, root.livePoint)
    readonly property bool charging: root.livePoint !== null && BatteryHistory.isCharging(root.livePoint.state, root.livePoint.v)

    // ---- Formatierung ----
    function number(v: real, digits: int): string {
        return Number(v).toLocaleString(I18n.locale, "f", digits);
    }

    function ago(t: real): string {
        const s = root.now - t;
        if (s < 90)
            return I18n.tr("gerade eben");
        if (s < 3600)
            return I18n.tr("vor %1 min").arg(Math.round(s / 60));
        if (s < 86400)
            return I18n.tr("vor %1 h").arg(Math.round(s / 3600));
        const days = Math.round(s / 86400);
        return days === 1 ? I18n.tr("vor einem Tag") : I18n.tr("vor %1 Tagen").arg(days);
    }

    function duration(hours: real): string {
        if (hours < 1)
            return I18n.tr("%1 min").arg(Math.round(hours * 60));
        if (hours < 48)
            return I18n.tr("%1 h").arg(Math.round(hours));
        return I18n.tr("%1 Tage").arg(root.number(hours / 24, 1));
    }

    function stamp(t: real): string {
        const d = new Date(t * 1000);
        const sameDay = new Date(root.now * 1000).toDateString() === d.toDateString();
        return sameDay ? d.toLocaleTimeString(I18n.locale, "HH:mm")
                       : d.toLocaleString(I18n.locale, "ddd d. MMM, HH:mm");
    }

    function stateLabel(state: string, value: real): string {
        return BatteryHistory.isCharging(state, value) ? I18n.tr("lädt")
             : state === "fully-charged" ? I18n.tr("voll")
             : I18n.tr("entlädt");
    }

    Component.onCompleted: BatteryHistory.refresh()

    Timer {
        interval: 60000
        repeat: true
        running: root.visible
        onTriggered: {
            root.now = Date.now() / 1000;
            BatteryHistory.refresh();
        }
    }

    // Leer: kein Geraet hat je einen Verlauf hinterlassen
    Text {
        visible: root.devices.length === 0
        width: root.width
        topPadding: 6
        text: BatteryHistory.loading ? "" : I18n.tr("Kein Verlauf")
        wrapMode: Text.Wrap
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 12
    }

    // ---- Geraete ----
    Flow {
        width: root.width
        spacing: 6
        visible: root.devices.length > 1

        Repeater {
            model: root.devices

            Rectangle {
                id: chip

                required property var modelData
                readonly property bool selected: chip.modelData.key === (root.device?.key ?? "")
                readonly property bool present: root.liveFor(chip.modelData) !== null

                width: chipRow.implicitWidth + 22
                height: 30
                radius: 15
                color: chip.selected ? Colors.primary
                     : chipHover.hovered ? Colors.alpha(Colors.fgSurface, 0.09)
                     : Colors.alpha(Colors.fgSurface, 0.05)

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }

                Row {
                    id: chipRow

                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.iconFor(chip.modelData)
                        color: chip.selected ? Colors.fgPrimary : Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 15
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.displayName(chip.modelData)
                        color: chip.selected ? Colors.fgPrimary : Colors.fgSurface
                        font.family: Config.font
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    // Punkt: gerade verbunden
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: chip.present
                        width: 6
                        height: 6
                        radius: 3
                        color: chip.selected ? Colors.fgPrimary : Colors.primary
                    }
                }

                HoverHandler {
                    id: chipHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.selectedKey = chip.modelData.key
                }
            }
        }
    }

    // ---- Kopf: Stand jetzt + Zeitraum ----
    Item {
        width: root.width
        height: 44
        visible: root.device !== null

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.livePoint ? `${root.livePoint.v} %`
                                     : root.device ? `${Math.round(root.device.points[root.device.points.length - 1].v)} %` : ""
                color: root.livePoint ? Colors.fgSurface : Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 30
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            BatteryGlyph {
                anchors.verticalCenter: parent.verticalCenter
                bodyWidth: 30
                bodyHeight: 16
                percent: root.livePoint?.v ?? root.device?.points[root.device.points.length - 1].v ?? 0
                charging: root.livePoint ? BatteryHistory.isCharging(root.livePoint.state, root.livePoint.v) : false
                fg: root.livePoint ? Colors.fgSurface : Colors.fgSurfaceVariant
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: root.displayName(root.device)
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Text {
                    text: root.livePoint
                        ? I18n.tr("Verbunden · %1").arg(root.stateLabel(root.livePoint.state, root.livePoint.v))
                        : I18n.tr("Nicht verbunden · zuletzt gesehen %1").arg(root.ago(root.lastSeen))
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 11
                }
            }
        }

        // Zeitraum
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: root.ranges

                Rectangle {
                    id: rangeChip

                    required property var modelData
                    readonly property bool selected: root.rangeHours === rangeChip.modelData.hours

                    width: rangeText.implicitWidth + 18
                    height: 26
                    radius: 13
                    color: rangeChip.selected ? Colors.alpha(Colors.primary, 0.18)
                         : rangeHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07) : "transparent"

                    Text {
                        id: rangeText

                        anchors.centerIn: parent
                        text: rangeChip.modelData.label
                        color: rangeChip.selected ? Colors.primary : Colors.fgSurfaceVariant
                        font.family: Config.font
                        font.pixelSize: 11
                        font.weight: rangeChip.selected ? Font.DemiBold : Font.Medium
                    }

                    HoverHandler {
                        id: rangeHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: root.rangeHours = rangeChip.modelData.hours
                    }
                }
            }
        }
    }

    // ---- Diagramm ----
    Item {
        id: chart

        width: root.width
        height: 200
        visible: root.device !== null

        // Zeichenflaeche ohne Achsenbeschriftung
        readonly property real padLeft: 36
        readonly property real padRight: 8
        readonly property real padTop: 8
        readonly property real padBottom: 22
        readonly property real plotW: chart.width - chart.padLeft - chart.padRight
        readonly property real plotH: chart.height - chart.padTop - chart.padBottom

        function xOf(t: real): real {
            return chart.padLeft + (t - root.from) / Math.max(1, root.to - root.from) * chart.plotW;
        }
        function yOf(v: real): real {
            return chart.padTop + (1 - Math.max(0, Math.min(100, v)) / 100) * chart.plotH;
        }

        // Abschnitte als Punktlisten; der letzte bekommt den Stand von jetzt
        readonly property var series: {
            const d = root.device;
            if (!d)
                return [];
            const out = d.segments.map(seg => seg.map(i => d.points[i]));
            if (root.livePoint && out.length > 0)
                out[out.length - 1] = out[out.length - 1].concat([root.livePoint]);
            return out;
        }

        // Stand zu einer Zeit: { v, state } oder null in einer Luecke
        function valueAt(t: real): var {
            for (const seg of chart.series) {
                if (seg.length === 0 || t < seg[0].t || t > seg[seg.length - 1].t)
                    continue;
                for (let i = 1; i < seg.length; i++) {
                    const a = seg[i - 1];
                    const b = seg[i];
                    if (t >= a.t && t <= b.t) {
                        const f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 1;
                        return { v: a.v + (b.v - a.v) * f, state: b.state };
                    }
                }
                return { v: seg[0].v, state: seg[0].state };
            }
            return null;
        }

        // Zeitmarken unten: Stunden bei 24 h, sonst Tage (Mitternacht)
        readonly property var ticks: {
            const span = root.to - root.from;
            const out = [];
            // Ueber den Kalender weiterzaehlen, nicht in Sekunden – sonst
            // steht nach der Zeitumstellung ein Tag doppelt da
            const d = new Date(root.from * 1000);
            if (span <= 30 * 3600) {
                d.setMinutes(0, 0, 0);
                d.setHours(d.getHours() + 1);
                for (; d.getTime() / 1000 <= root.to; d.setHours(d.getHours() + 1)) {
                    if (d.getHours() % 4 === 0)
                        out.push({ t: d.getTime() / 1000, label: d.toLocaleTimeString(I18n.locale, "HH:mm") });
                }
            } else {
                const days = span / 86400;
                const every = days <= 8 ? 1 : days <= 16 ? 2 : 7;
                d.setHours(24, 0, 0, 0);
                for (let n = 0; d.getTime() / 1000 <= root.to; d.setDate(d.getDate() + 1), n++) {
                    if (n % every === 0)
                        out.push({ t: d.getTime() / 1000, label: d.toLocaleDateString(I18n.locale, days <= 4 ? "ddd d." : "d.M.") });
                }
            }
            return out;
        }

        // Raster und Beschriftung (recessiv)
        Repeater {
            model: [0, 50, 100]

            Item {
                id: gridLine

                required property int modelData

                Rectangle {
                    x: chart.padLeft
                    y: chart.yOf(gridLine.modelData)
                    width: chart.plotW
                    height: 1
                    color: Colors.alpha(Colors.fgSurface, gridLine.modelData === 0 ? 0.14 : 0.06)
                }

                Text {
                    x: chart.padLeft - width - 8
                    y: chart.yOf(gridLine.modelData) - height / 2
                    text: `${gridLine.modelData} %`
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                }
            }
        }

        Repeater {
            model: chart.ticks

            Text {
                id: tick

                required property var modelData

                x: Math.max(chart.padLeft, Math.min(chart.width - width, chart.xOf(tick.modelData.t) - width / 2))
                y: chart.height - chart.padBottom + 6
                text: tick.modelData.label
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 10
            }
        }

        Canvas {
            id: plot

            anchors.fill: parent

            readonly property color line: Colors.primary
            readonly property color muted: Colors.alpha(Colors.fgSurface, 0.3)
            readonly property color warn: Colors.alpha(Colors.error, 0.45)

            onLineChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: chart
                function onSeriesChanged() { plot.requestPaint(); }
            }
            Connections {
                target: root
                function onFromChanged() { plot.requestPaint(); }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);

                ctx.save();
                ctx.beginPath();
                ctx.rect(chart.padLeft, 0, chart.plotW, height);
                ctx.clip();

                const base = chart.yOf(0);

                // Laden: getoente Baender hinter allem
                ctx.fillStyle = Qt.rgba(plot.line.r, plot.line.g, plot.line.b, 0.10);
                for (const seg of chart.series) {
                    for (let i = 1; i < seg.length; i++) {
                        if (BatteryHistory.isCharging(seg[i].state, seg[i].v)) {
                            const x0 = chart.xOf(seg[i - 1].t);
                            ctx.fillRect(x0, chart.padTop, Math.max(2, chart.xOf(seg[i].t) - x0), chart.plotH);
                        }
                    }
                }

                // 20-%-Grenze
                ctx.strokeStyle = plot.warn;
                ctx.lineWidth = 1;
                ctx.setLineDash([3, 4]);
                ctx.beginPath();
                ctx.moveTo(chart.padLeft, chart.yOf(20) + 0.5);
                ctx.lineTo(chart.padLeft + chart.plotW, chart.yOf(20) + 0.5);
                ctx.stroke();

                // Luecken: gestrichelt vom Ende eines Abschnitts zum Anfang
                // des naechsten – der Verlauf dazwischen ist unbekannt
                ctx.strokeStyle = plot.muted;
                ctx.lineWidth = 1.5;
                ctx.setLineDash([2, 4]);
                for (let s = 1; s < chart.series.length; s++) {
                    const a = chart.series[s - 1][chart.series[s - 1].length - 1];
                    const b = chart.series[s][0];
                    ctx.beginPath();
                    ctx.moveTo(chart.xOf(a.t), chart.yOf(a.v));
                    ctx.lineTo(chart.xOf(b.t), chart.yOf(a.v));
                    ctx.lineTo(chart.xOf(b.t), chart.yOf(b.v));
                    ctx.stroke();
                }
                ctx.setLineDash([]);

                // Flaeche + Linie je Abschnitt
                const grad = ctx.createLinearGradient(0, chart.padTop, 0, base);
                grad.addColorStop(0, Qt.rgba(plot.line.r, plot.line.g, plot.line.b, 0.28));
                grad.addColorStop(1, Qt.rgba(plot.line.r, plot.line.g, plot.line.b, 0.02));
                for (const seg of chart.series) {
                    if (seg.length === 0)
                        continue;
                    // Einzelner Punkt: kurzer Strich, damit er sichtbar bleibt
                    const pts = seg.length === 1 ? [seg[0], { t: seg[0].t + (root.to - root.from) / 200, v: seg[0].v }] : seg;

                    ctx.beginPath();
                    ctx.moveTo(chart.xOf(pts[0].t), base);
                    for (const p of pts)
                        ctx.lineTo(chart.xOf(p.t), chart.yOf(p.v));
                    ctx.lineTo(chart.xOf(pts[pts.length - 1].t), base);
                    ctx.closePath();
                    ctx.fillStyle = grad;
                    ctx.fill();

                    ctx.beginPath();
                    ctx.moveTo(chart.xOf(pts[0].t), chart.yOf(pts[0].v));
                    for (const p of pts)
                        ctx.lineTo(chart.xOf(p.t), chart.yOf(p.v));
                    ctx.strokeStyle = plot.line;
                    ctx.lineWidth = 2;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    ctx.stroke();
                }
                ctx.restore();
            }
        }

        // Stand von jetzt als Punkt am rechten Ende
        Rectangle {
            visible: root.livePoint !== null
            x: chart.xOf(root.to) - width / 2
            y: chart.yOf(root.livePoint?.v ?? 0) - height / 2
            width: 10
            height: 10
            radius: 5
            color: Colors.primary
            border.width: 2
            border.color: Colors.surface
        }

        // ---- Fadenkreuz ----
        HoverHandler {
            id: chartHover
        }

        readonly property real hoverT: root.from + (chartHover.point.position.x - chart.padLeft) / Math.max(1, chart.plotW) * (root.to - root.from)
        readonly property bool hovering: chartHover.hovered && chartHover.point.position.x >= chart.padLeft
                                         && chartHover.point.position.x <= chart.padLeft + chart.plotW
        readonly property var hoverValue: chart.hovering ? chart.valueAt(chart.hoverT) : null

        Rectangle {
            visible: chart.hovering
            x: chartHover.point.position.x
            y: chart.padTop
            width: 1
            height: chart.plotH
            color: Colors.alpha(Colors.fgSurface, 0.25)
        }

        Rectangle {
            visible: chart.hoverValue !== null
            x: chartHover.point.position.x - width / 2
            y: chart.yOf(chart.hoverValue?.v ?? 0) - height / 2
            width: 10
            height: 10
            radius: 5
            color: Colors.primary
            border.width: 2
            border.color: Colors.surface
        }

        Rectangle {
            id: tip

            visible: chart.hovering
            readonly property real wanted: chartHover.point.position.x + 12
            x: tip.wanted + width > chart.width ? chartHover.point.position.x - width - 12 : tip.wanted
            y: chart.padTop + 4
            width: tipColumn.implicitWidth + 16
            height: tipColumn.implicitHeight + 10
            radius: 8
            color: Colors.surfaceBright
            border.width: 1
            border.color: Colors.alpha(Colors.fgSurface, 0.08)

            Column {
                id: tipColumn

                anchors.centerIn: parent
                spacing: 1

                Text {
                    text: root.stamp(chart.hoverT)
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 10
                }

                Text {
                    text: chart.hoverValue
                        ? `${Math.round(chart.hoverValue.v)} % · ${root.stateLabel(chart.hoverValue.state, chart.hoverValue.v)}`
                        : I18n.tr("nicht verbunden")
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // ---- Kennzahlen ----
    Row {
        id: tiles

        visible: root.device !== null
        width: root.width
        spacing: 8

        readonly property var items: [
            {
                icon: "trending_down",
                label: I18n.tr("Verbrauch"),
                value: root.stats.rate > 0 ? I18n.tr("%1 %/h").arg(root.number(root.stats.rate, root.stats.rate < 1 ? 2 : 1)) : "–",
                hint: ""
            },
            {
                icon: "hourglass_bottom",
                label: I18n.tr("Reicht noch"),
                value: root.charging ? I18n.tr("lädt") : root.stats.remaining > 0 ? `≈ ${root.duration(root.stats.remaining)}` : "–",
                hint: !root.charging && root.stats.remaining > 0 && root.livePoint ? root.stamp(root.now + root.stats.remaining * 3600) : ""
            },
            {
                icon: "bolt",
                label: I18n.tr("Zuletzt geladen"),
                value: root.stats.lastCharged > 0 ? root.ago(root.stats.lastCharged) : "–",
                hint: root.stats.lastCharged > 0 ? root.stamp(root.stats.lastCharged) : ""
            },
            {
                icon: "swap_vert",
                label: I18n.tr("Spanne"),
                value: root.stats.min >= 0 ? `${Math.round(root.stats.min)} – ${Math.round(root.stats.max)} %` : "–",
                hint: ""
            }
        ]

        Repeater {
            model: tiles.items

            Rectangle {
                id: tile

                required property var modelData

                width: (tiles.width - tiles.spacing * 3) / 4
                height: 70
                radius: 12
                color: Colors.alpha(Colors.fgSurface, 0.04)

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 2

                    Row {
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.modelData.icon
                            color: Colors.primary
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.modelData.label
                            color: Colors.fgSurfaceVariant
                            font.family: Config.font
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        width: parent.width
                        text: tile.modelData.value
                        color: Colors.fgSurface
                        font.family: Config.font
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: tile.modelData.hint
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                        font.family: Config.font
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
