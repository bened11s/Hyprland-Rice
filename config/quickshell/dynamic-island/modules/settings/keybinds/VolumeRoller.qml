pragma ComponentBehavior: Bound
import QtQuick

import qs

// Lautstaerke-Walze im Gehaeuse: linke Haelfte leiser, rechte lauter.
// Jede Haelfte leuchtet fuer sich (Belegung aus der Ebene). Tooltips zeichnet
// die Tastatur (Overlay, hoverSide).
Item {
    id: roller

    required property real unit
    // Belegung/Licht je Haelfte: [leiser, lauter]
    property var infos: [null, null]
    property var lights: ["transparent", "transparent"]
    property var lits: [false, false]
    property var ids: ["xf86audiolowervolume", "xf86audioraisevolume"]
    property bool pick: false
    property bool interactive: true

    signal clicked(string id)
    signal contextClicked(string id)

    // Gehoverte Haelfte fuer den Tooltip der Tastatur: -1 keine, 0 leiser, 1 lauter
    readonly property int hoverSide: leftHalf.hovered ? 0 : rightHalf.hovered ? 1 : -1

    width: roller.unit * 1.7
    height: roller.unit * 0.5
    z: leftHalf.hovered || rightHalf.hovered ? 2 : 0

    // Unterkante
    Rectangle {
        y: Math.max(1, Math.round(roller.unit * 0.04))
        width: parent.width
        height: parent.height - y
        radius: height / 2
        color: Qt.darker(Colors.surfaceBright, 1.5)
    }

    // Walze mit Rillen
    Rectangle {
        id: drum

        width: parent.width
        height: parent.height - Math.max(1, Math.round(roller.unit * 0.04))
        radius: height / 2
        color: Colors.surfaceBright
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.35)

        Row {
            anchors.centerIn: parent
            spacing: Math.max(3, roller.unit * 0.07)

            Repeater {
                model: 14

                Rectangle {
                    width: 1
                    height: drum.height - roller.unit * 0.12
                    color: Colors.alpha(Colors.background, 0.55)
                }
            }
        }

        // Licht je Haelfte (aussen rund wie die Walze)
        Rectangle {
            x: 1
            y: 1
            width: parent.width / 2 - 1
            height: parent.height - 2
            topLeftRadius: height / 2
            bottomLeftRadius: height / 2
            color: Colors.alpha(roller.lights[0], (roller.lits[0] ? 0.5 : roller.infos[0] ? 0.3 : 0) * (roller.infos[0]?.disabled ? 0.5 : 1))

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }

        Rectangle {
            x: parent.width / 2
            y: 1
            width: parent.width / 2 - 1
            height: parent.height - 2
            topRightRadius: height / 2
            bottomRightRadius: height / 2
            color: Colors.alpha(roller.lights[1], (roller.lits[1] ? 0.5 : roller.infos[1] ? 0.3 : 0) * (roller.infos[1]?.disabled ? 0.5 : 1))

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }

        // Hover-Aufhellung
        Rectangle {
            x: leftHalf.hovered ? 1 : parent.width / 2
            y: 1
            width: parent.width / 2 - 1
            height: parent.height - 2
            topLeftRadius: leftHalf.hovered ? height / 2 : 0
            bottomLeftRadius: leftHalf.hovered ? height / 2 : 0
            topRightRadius: leftHalf.hovered ? 0 : height / 2
            bottomRightRadius: leftHalf.hovered ? 0 : height / 2
            visible: roller.interactive && (leftHalf.hovered || rightHalf.hovered)
            color: Colors.alpha(Colors.fgSurface, 0.08)
        }
    }

    // Symbole an den Enden
    Text {
        anchors {
            left: parent.left
            leftMargin: roller.unit * 0.12
            verticalCenter: parent.verticalCenter
        }
        text: "remove"
        color: roller.infos[0] ? roller.lights[0] : Colors.alpha(Colors.fgSurfaceVariant, 0.5)
        font.family: "Material Symbols Outlined"
        font.pixelSize: Math.max(9, Math.round(roller.unit * 0.22))
    }

    Text {
        anchors {
            right: parent.right
            rightMargin: roller.unit * 0.12
            verticalCenter: parent.verticalCenter
        }
        text: "add"
        color: roller.infos[1] ? roller.lights[1] : Colors.alpha(Colors.fgSurfaceVariant, 0.5)
        font.family: "Material Symbols Outlined"
        font.pixelSize: Math.max(9, Math.round(roller.unit * 0.22))
    }

    Item {
        id: leftHalf

        readonly property bool hovered: lh.hovered && roller.interactive

        width: parent.width / 2
        height: parent.height

        HoverHandler {
            id: lh

            cursorShape: roller.infos[0] || roller.pick ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: roller.interactive && (roller.infos[0] !== null || roller.pick)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (point, button) => button === Qt.RightButton ? roller.contextClicked(roller.ids[0]) : roller.clicked(roller.ids[0])
        }
    }

    Item {
        id: rightHalf

        readonly property bool hovered: rh.hovered && roller.interactive

        x: parent.width / 2
        width: parent.width / 2
        height: parent.height

        HoverHandler {
            id: rh

            cursorShape: roller.infos[1] || roller.pick ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: roller.interactive && (roller.infos[1] !== null || roller.pick)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (point, button) => button === Qt.RightButton ? roller.contextClicked(roller.ids[1]) : roller.clicked(roller.ids[1])
        }
    }
}
