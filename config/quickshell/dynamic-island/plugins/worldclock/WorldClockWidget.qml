pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config

// Weltuhr auf dem Desktop: bis zu drei Zeitzonen, Stadt links, Zeit rechts,
// davor ein kleiner Punkt fuer Tag oder Nacht. Die Offsets rechnet das Widget
// selbst (EU-, US- und Sydney-Regel fuer die Sommerzeit) – damit braucht es
// weder Intl noch einen Netzdienst.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property bool showSeconds: root.opts.sekunden ?? false
    readonly property var keys: [root.opts.zone1 ?? "tokio", root.opts.zone2 ?? "new-york", root.opts.zone3 ?? "london"]

    readonly property var zones: ({
        "tokio": { name: "Tokio", offset: t => 9 },
        "singapur": { name: "Singapur", offset: t => 8 },
        "dubai": { name: "Dubai", offset: t => 4 },
        "berlin": { name: "Berlin", offset: t => root.euDst(t) ? 2 : 1 },
        "london": { name: "London", offset: t => root.euDst(t) ? 1 : 0 },
        "new-york": { name: "New York", offset: t => root.usDst(t) ? -4 : -5 },
        "los-angeles": { name: "Los Angeles", offset: t => root.usDst(t) ? -7 : -8 },
        "sydney": { name: "Sydney", offset: t => root.sydDst(t) ? 11 : 10 }
    })

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property real labelPx: Math.max(10, root.unit * 0.8)
    readonly property real valuePx: Math.max(13, root.unit * 1.2)

    SystemClock {
        id: clock

        // Sekunden nur, wenn sie auch angezeigt werden
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    function firstSunday(y, m): int {
        return 1 + ((7 - new Date(Date.UTC(y, m, 1)).getUTCDay()) % 7);
    }

    function lastSunday(y, m): int {
        const d = new Date(Date.UTC(y, m + 1, 0));
        return d.getUTCDate() - d.getUTCDay();
    }

    // Sommerzeit in der EU: letzter Sonntag im Maerz bis letzter im Oktober,
    // jeweils 01:00 UTC.
    function euDst(t): bool {
        const y = new Date(t).getUTCFullYear();
        return t >= Date.UTC(y, 2, root.lastSunday(y, 2), 1)
            && t < Date.UTC(y, 9, root.lastSunday(y, 9), 1);
    }

    // USA: zweiter Sonntag im Maerz 07:00 UTC bis erster Sonntag im November 06:00 UTC
    function usDst(t): bool {
        const y = new Date(t).getUTCFullYear();
        return t >= Date.UTC(y, 2, root.firstSunday(y, 2) + 7, 7)
            && t < Date.UTC(y, 10, root.firstSunday(y, 10), 6);
    }

    // Sydney: erster Sonntag im Oktober 16:00 UTC bis erster Sonntag im April 16:00 UTC
    function sydDst(t): bool {
        const y = new Date(t).getUTCFullYear();
        return t >= Date.UTC(y, 9, root.firstSunday(y, 9), 16)
            || t < Date.UTC(y, 3, root.firstSunday(y, 3), 16);
    }

    function offsetOf(key, t): real {
        const z = root.zones[key];
        return z ? z.offset(t) : 0;
    }

    function cityName(key): string {
        const z = root.zones[key];
        return z ? z.name : key;
    }

    function clockOf(key): date {
        return new Date(clock.date.getTime() + root.offsetOf(key, clock.date.getTime()) * 3600000);
    }

    function timeOf(key): string {
        const d = root.clockOf(key);
        const hh = (d.getUTCHours() < 10 ? "0" : "") + d.getUTCHours();
        const mm = (d.getUTCMinutes() < 10 ? "0" : "") + d.getUTCMinutes();
        if (!root.showSeconds)
            return hh + ":" + mm;
        const ss = (d.getUTCSeconds() < 10 ? "0" : "") + d.getUTCSeconds();
        return hh + ":" + mm + ":" + ss;
    }

    // Tag, wenn es zwischen 7 und 21 Uhr ist – nur fuer den Punkt
    function isDay(key): bool {
        const h = root.clockOf(key).getUTCHours();
        return h >= 7 && h < 21;
    }

    implicitWidth: root.unit * 12
    implicitHeight: column.implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: Math.round(root.unit * 0.45)

        Repeater {
            model: root.keys

            delegate: Row {
                required property string modelData

                visible: modelData !== "keine"
                width: column.width
                height: visible ? root.unit * 1.65 : 0

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.unit * 0.32
                    height: width
                    radius: width / 2
                    color: root.isDay(modelData) ? root.accent : Colors.alpha(root.color, 0.35)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.unit * 0.7
                    text: root.cityName(modelData)
                    font.family: root.display
                    font.pixelSize: root.labelPx
                    font.letterSpacing: root.labelPx * 0.04
                    color: Colors.alpha(root.color, 0.86)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: root.timeOf(modelData)
                    font.family: root.display
                    font.pixelSize: root.valuePx
                    font.weight: Font.Medium
                    color: root.color
                }
            }
        }
    }
}
