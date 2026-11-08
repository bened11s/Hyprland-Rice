pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config

// Sonnenstand auf dem Desktop: Aufgang und Untergang, ein duenner Balken
// fuer den Tageslichtverlauf und darunter die Mondphase. Alles reine
// Rechnung (NOAA-Naeherung fuer den Stand, synodischer Monat fuer den Mond)
// – kein Netz, keine Anfrage. Neu gerechnet wird nur beim Minutenwechsel.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property string place: root.opts.ort ?? "Köln"
    readonly property bool showArc: root.opts.verlauf ?? true
    readonly property bool showMoon: root.opts.mond ?? true

    // Breite, Laenge – bewusst wenige Orte statt Freitext (Optionen sind Chips)
    readonly property var spots: ({
        "Köln": [50.94, 6.96],
        "Berlin": [52.52, 13.40],
        "Hamburg": [53.55, 9.99],
        "München": [48.14, 11.58],
        "Leipzig": [51.34, 12.37],
        "Wien": [48.21, 16.37],
        "Zürich": [47.37, 8.54]
    })
    readonly property var spot: root.spots[root.place] ?? root.spots["Köln"]

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property real labelPx: Math.max(9, root.unit * 0.72)
    readonly property real valuePx: Math.max(13, root.unit * 1.15)

    // ---- Sonne ----
    readonly property var sun: root.sunTimes(clock.date)
    readonly property bool sunUp: root.sun.rise !== undefined && root.minutes >= root.sun.rise && root.minutes <= root.sun.set
    // 0 = vor Aufgang, 1 = nach Untergang
    readonly property real arc: {
        if (root.sun.rise === undefined)
            return root.sun.polarNight ? 0 : 1;
        return Math.max(0, Math.min(1, (root.minutes - root.sun.rise) / (root.sun.set - root.sun.rise)));
    }

    // ---- Mond ----
    readonly property var moon: root.moonPhase(clock.date)

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    readonly property int minutes: clock.date.getHours() * 60 + clock.date.getMinutes()

    function pad(n): string {
        return (n < 10 ? "0" : "") + n;
    }

    function hv(min): string {
        if (min === undefined || isNaN(min))
            return "--:--";
        const m = (Math.round(min) % 1440 + 1440) % 1440;
        return root.pad(Math.floor(m / 60)) + ":" + root.pad(m % 60);
    }

    function dayOfYear(d: date): int {
        return Math.floor((d - new Date(d.getFullYear(), 0, 0)) / 86400000);
    }

    // NOAA-Naeherung, gut auf +-2 Minuten; Uhrzeiten in Minuten seit
    // lokaler Mitternacht (DST kommt ueber getTimezoneOffset herein).
    function sunTimes(d: date): var {
        const lat = root.spot[0] * Math.PI / 180;
        const lon = root.spot[1];
        const n = root.dayOfYear(d);
        const decl = 23.45 * Math.PI / 180 * Math.sin(2 * Math.PI * (284 + n) / 365);
        const b = 2 * Math.PI * (n - 81) / 365;
        const eot = 9.87 * Math.sin(2 * b) - 7.53 * Math.cos(b) - 1.5 * Math.sin(b);
        const tz = -d.getTimezoneOffset() / 60;
        const noon = 720 - 4 * lon - eot + tz * 60;
        const cosHa = (Math.sin(-0.833 * Math.PI / 180) - Math.sin(lat) * Math.sin(decl))
            / (Math.cos(lat) * Math.cos(decl));
        if (cosHa >= 1)
            return { polarNight: true };
        if (cosHa <= -1)
            return { midnightSun: true };
        const ha = Math.acos(cosHa) * 180 / Math.PI;
        return { rise: noon - 4 * ha, set: noon + 4 * ha };
    }

    function moonPhase(d: date): var {
        const synodic = 29.530588853;
        const ref = Date.UTC(2000, 0, 6, 18, 14); // bekannter Neumond
        const days = (d.getTime() - ref) / 86400000;
        const age = ((days % synodic) + synodic) % synodic;
        const frac = age / synodic;
        const illum = (1 - Math.cos(2 * Math.PI * frac)) / 2;
        const names = ["Neumond", "zunehmende Sichel", "zunehmender Halbmond", "zunehmender Mond",
                       "Vollmond", "abnehmender Mond", "abnehmender Halbmond", "abnehmende Sichel"];
        return { name: names[Math.round(frac * 8) % 8], illum: illum, waxing: frac < 0.5 };
    }

    implicitWidth: root.unit * 15
    implicitHeight: column.implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: Math.round(root.unit * 0.5)

        // Aufgang / Untergang
        Row {
            width: parent.width
            spacing: root.unit * 0.6

            Repeater {
                model: [
                    { icon: "wb_twilight", label: "Aufgang", time: root.hv(root.sun.rise) },
                    { icon: "nights_stay", label: "Untergang", time: root.hv(root.sun.set) }
                ]

                delegate: Row {
                    required property var modelData

                    spacing: root.unit * 0.35

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.icon === "wb_twilight" ? root.sunUp : !root.sunUp
                        text: modelData.icon
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: root.labelPx * 1.5
                        color: root.accent
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Text {
                            text: modelData.label
                            font.family: root.display
                            font.pixelSize: root.labelPx * 0.85
                            font.letterSpacing: root.labelPx * 0.06
                            color: Colors.alpha(root.color, 0.6)
                        }

                        Text {
                            text: modelData.time
                            font.family: root.display
                            font.pixelSize: root.valuePx
                            font.weight: Font.Medium
                            color: root.color
                        }
                    }
                }
            }
        }

        // Tageslichtbalken: links Aufgang, rechts Untergang, Marke = jetzt
        Item {
            visible: root.showArc
            width: parent.width
            height: root.unit * 0.55

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.max(2, root.unit * 0.1)
                radius: height / 2
                color: Colors.alpha(root.color, 0.18)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * root.arc
                height: Math.max(2, root.unit * 0.1)
                radius: height / 2
                color: Colors.alpha(root.accent, 0.85)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(parent.width - width, Math.max(0, parent.width * root.arc - width / 2))
                width: root.unit * 0.34
                height: width
                radius: width / 2
                color: root.accent
            }
        }

        // Mondphase
        Row {
            visible: root.showMoon
            width: parent.width
            spacing: root.unit * 0.35

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.moon.waxing ? "brightness_2" : "brightness_3"
                font.family: "Material Symbols Outlined"
                font.pixelSize: root.labelPx * 1.5
                color: Colors.alpha(root.color, 0.75)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.moon.name + " · " + Math.round(root.moon.illum * 100) + " %"
                font.family: root.display
                font.pixelSize: root.labelPx
                color: Colors.alpha(root.color, 0.75)
            }
        }
    }
}
