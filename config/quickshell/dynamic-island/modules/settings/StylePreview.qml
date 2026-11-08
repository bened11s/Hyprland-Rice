pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.widgets
import qs.modules.widgets.clock

// Kleine Vorschau einer Stil-Variante fuer die Chips im Einstellungsmenue
// (SettingsRow laedt sie, wenn Config.meta[..].preview gesetzt ist).
//
//     StylePreview { kind: "clock"; style: "analog" }
//
// Alles steht still: die Uhr zeigt eine feste Beispielzeit, der Visualiser
// bekommt feste Beispielpegel (`sample`, liest also kein Cava), und die
// Workspaces sind eine Nachbildung mit festen Werten (5 Slots, der zweite
// aktiv, 1 und 4 belegt) – NotchWorkspaces selbst haengt an Hyprland, und
// sein Marker ist als gebundene Inline-Komponente von aussen nicht nutzbar.
Item {
    id: root

    // "clock" | "visualizer" | "workspaces"
    property string kind: "clock"
    property string style: ""
    property color color: Colors.fgSurface
    property color accent: Colors.primary

    readonly property date sampleTime: new Date(2026, 0, 1, 10, 9)
    // 36 feste Baender wie Cava: Bass kraeftig, nach oben abfallend, mit
    // Buckeln dazwischen – leise genug, dass die Verstaerkung nicht clippt
    readonly property var sampleLevels: {
        const v = [];
        for (let i = 0; i < 36; i++) {
            const t = i / 35;
            v.push(0.01 + 0.6 * Math.exp(-4 * t) * (0.3 + 0.7 * Math.abs(Math.sin(i * 1.9 + 0.7))));
        }
        return v;
    }

    implicitWidth: 64
    implicitHeight: 28

    Loader {
        anchors.centerIn: parent
        sourceComponent: root.kind === "visualizer" ? visualizer
                       : root.kind === "workspaces" ? workspaces
                       : clock
    }

    Component {
        id: clock

        ClockFace {
            style: root.style
            date: root.sampleTime
            size: root.style === "analog" ? 22 : 17
            color: root.color
            accent: root.accent
        }
    }

    Component {
        id: visualizer

        Visualizer {
            style: root.style
            count: 9
            barWidth: 3
            spacing: 2
            height: 22
            color: root.accent
            active: true
            sample: root.sampleLevels
        }
    }

    Component {
        id: workspaces

        Row {
            spacing: root.style === "punkte" ? 5 : root.style === "zahlen" ? 6 : 4

            Repeater {
                model: 5

                // Nachbau von NotchWorkspaces.Marker mit festen Massen
                Item {
                    id: marker

                    required property int index
                    readonly property bool active: marker.index === 1
                    readonly property bool occupied: marker.index === 0 || marker.index === 3
                    readonly property bool dots: root.style === "punkte"
                    readonly property bool digits: root.style === "zahlen"
                    readonly property real fade: marker.active ? 1 : marker.occupied ? 0.6 : 0.3

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: marker.digits ? digit.implicitWidth
                                 : marker.dots ? (marker.active ? 16 : 6)
                                 : 5
                    implicitHeight: 15

                    Rectangle {
                        anchors.centerIn: parent
                        visible: !marker.digits
                        width: marker.dots ? (marker.active ? 16 : 6) : 5
                        height: marker.dots ? 6 : marker.active ? 15 : 9
                        radius: Math.min(width, height) / 2
                        color: root.accent
                        opacity: marker.fade
                    }

                    Text {
                        id: digit

                        anchors.centerIn: parent
                        visible: marker.digits
                        text: String(marker.index + 1)
                        color: root.accent
                        font.family: Config.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        opacity: Math.min(1, marker.fade + (marker.active ? 0 : 0.08))
                    }
                }
            }
        }
    }
}
