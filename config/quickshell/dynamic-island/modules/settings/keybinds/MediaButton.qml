pragma ComponentBehavior: Bound
import QtQuick

import qs

// Runder Medienknopf im Gehaeuse (oben rechts): flache Kappe mit Kontur und
// Unterkante, gleiche Beleuchtung wie die Tasten, Symbol statt Legende.
// Tooltips zeichnet die Tastatur (Overlay).
Item {
    id: btn

    // { id, icon, title } aus KeyLayout.MEDIA
    required property var spec
    required property real unit
    property var info: null
    property color light: "transparent"
    property bool lit: false
    property bool pick: false
    property bool interactive: true

    signal clicked
    signal contextClicked

    readonly property bool occupied: btn.info !== null
    readonly property bool target: btn.pick && !btn.occupied && btn.interactive
    readonly property bool hovered: hover.hovered && btn.interactive
    readonly property bool disabled: btn.occupied && btn.info.disabled === true
    readonly property bool glowing: btn.lit || btn.occupied
    readonly property real strength: btn.lit ? 1 : btn.occupied ? (btn.disabled ? 0.4 : 0.55) : 0
    readonly property real depth: Math.max(1, Math.round(btn.unit * 0.04))
    readonly property color capBase: btn.hovered ? Qt.lighter(Colors.surfaceBright, 1.1) : Colors.surfaceBright

    width: btn.unit * 0.56
    height: width
    z: btn.hovered ? 2 : 0

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: width / 2
        color: Colors.alpha(btn.light, 0.22)
        visible: btn.lit
    }

    Rectangle {
        y: btn.depth
        width: parent.width
        height: parent.height - btn.depth
        radius: width / 2
        color: Qt.darker(Colors.surfaceBright, 1.5)
    }

    Rectangle {
        width: parent.width
        height: parent.height - btn.depth
        radius: width / 2
        color: btn.glowing ? Qt.tint(btn.capBase, Colors.alpha(btn.light, 0.28 * btn.strength)) : btn.capBase
        border.width: 1
        border.color: btn.target ? Colors.alpha(Colors.primary, btn.hovered ? 0.9 : 0.5)
                    : btn.glowing ? Colors.alpha(btn.light, 0.35 + 0.55 * btn.strength)
                    : Colors.alpha(Colors.outline, 0.35)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
        Behavior on border.color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Text {
            anchors.centerIn: parent
            text: btn.spec.icon
            color: btn.glowing ? (btn.lit ? Qt.lighter(btn.light, 1.1) : btn.light) : Colors.alpha(Colors.fgSurfaceVariant, 0.75)
            opacity: btn.disabled ? 0.7 : 1
            font.family: "Material Symbols Outlined"
            font.pixelSize: Math.max(10, Math.round(btn.unit * 0.3))

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }
    }

    HoverHandler {
        id: hover

        enabled: btn.interactive
        cursorShape: btn.occupied || btn.target ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: btn.interactive && (btn.occupied || btn.target)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (button === Qt.RightButton)
                btn.contextClicked();
            else
                btn.clicked();
        }
    }
}
