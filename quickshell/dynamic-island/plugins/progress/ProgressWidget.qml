pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config

// Fortschritt auf dem Desktop: wie viel vom Tag, der Woche, dem Monat und dem
// Jahr vorbei ist. Zwei Stile – Ringe mit Prozent darunter oder schlichte
// Balken. Die Werte haengen an SystemClock (Minuten), gezeichnet wird also
// hoechstens einmal pro Minute.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property string style: root.opts.stil ?? "ringe"
    readonly property bool rings: root.style === "ringe"

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property real labelPx: Math.max(10, root.unit * 0.8)
    readonly property real phonePx: Math.max(12, root.unit * 1.05)

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    readonly property real dayFrac: {
        const d = clock.date;
        return (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400;
    }
    readonly property real weekFrac: (((clock.date.getDay() + 6) % 7) + root.dayFrac) / 7
    readonly property real monthFrac: {
        const d = clock.date;
        const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
        return (d.getDate() - 1 + root.dayFrac) / days;
    }
    readonly property real yearFrac: {
        const d = clock.date;
        const start = new Date(d.getFullYear(), 0, 0);
        const days = (new Date(d.getFullYear() + 1, 0, 0) - start) / 86400000;
        return (Math.floor((d - start) / 86400000) - 1 + root.dayFrac) / days;
    }

    // Alle vier Teile, gefiltert nach den Optionen
    readonly property var parts: {
        const all = [
            { key: "tag", label: "Tag", value: root.dayFrac, on: root.opts.tag ?? true },
            { key: "woche", label: "Woche", value: root.weekFrac, on: root.opts.woche ?? true },
            { key: "monat", label: "Monat", value: root.monthFrac, on: root.opts.monat ?? true },
            { key: "jahr", label: "Jahr", value: root.yearFrac, on: root.opts.jahr ?? true }
        ];
        return all.filter(p => p.on);
    }

    implicitWidth: root.unit * 15
    implicitHeight: root.rings ? ringRow.height : barColumn.implicitHeight

    // ---- Stil Ringe ----
    Row {
        id: ringRow

        visible: root.rings
        spacing: root.unit * 0.45

        Repeater {
            model: root.rings ? root.parts : []

            delegate: Column {
                id: ring

                required property var modelData

                width: root.unit * 3.2
                spacing: root.unit * 0.12

                Canvas {
                    id: canvas

                    readonly property real stroke: Math.max(2, root.unit * 0.26)

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(root.unit * 2.8, ring.width)
                    height: width

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const cx = width / 2;
                        const cy = height / 2;
                        const r = Math.min(cx, cy) - canvas.stroke / 2 - 1;
                        // Spur
                        ctx.beginPath();
                        ctx.lineWidth = canvas.stroke;
                        ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.18);
                        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                        ctx.stroke();
                        // Fortschritt, ab 12 Uhr im Uhrzeigersinn
                        const v = Math.max(0, Math.min(1, ring.modelData.value));
                        if (v > 0.001) {
                            ctx.beginPath();
                            ctx.strokeStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.95);
                            ctx.lineCap = "round";
                            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * v);
                            ctx.stroke();
                        }
                    }

                    Connections {
                        target: root

                        function onColorChanged() {
                            canvas.requestPaint();
                        }
                        function onAccentChanged() {
                            canvas.requestPaint();
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(ring.modelData.value * 100) + " %"
                    font.family: root.display
                    font.pixelSize: root.phonePx
                    font.weight: Font.Medium
                    color: root.color
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ring.modelData.label
                    font.family: root.display
                    font.pixelSize: root.labelPx
                    font.letterSpacing: root.labelPx * 0.05
                    color: Colors.alpha(root.color, 0.72)
                }
            }
        }
    }

    // ---- Stil Balken ----
    Column {
        id: barColumn

        visible: !root.rings
        width: parent.width
        spacing: Math.round(root.unit * 0.55)

        Repeater {
            model: root.rings ? [] : root.parts

            delegate: Item {
                required property var modelData

                width: barColumn.width
                height: barRow.height

                Row {
                    id: barRow

                    width: parent.width
                    spacing: root.unit * 0.4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 3.2
                        text: modelData.label
                        font.family: root.display
                        font.pixelSize: root.labelPx
                        color: Colors.alpha(root.color, 0.7)
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: barRow.width - root.unit * 3.2 - root.unit * 2.4
                        height: Math.max(2, root.unit * 0.22)

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: Math.max(2, root.unit * 0.12)
                            radius: height / 2
                            color: Colors.alpha(root.color, 0.18)
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * Math.max(0, Math.min(1, modelData.value))
                            height: Math.max(2, root.unit * 0.12)
                            radius: height / 2
                            color: Colors.alpha(root.accent, 0.9)
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 2
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(modelData.value * 100) + " %"
                        font.family: root.display
                        font.pixelSize: root.phonePx
                        color: root.color
                    }
                }
            }
        }
    }
}
