pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs

// Ein Icon-Knopf der Medien-Pille. Trefferflaeche und Glyph sind entkoppelt:
// das Item ist groesser als das Zeichen, damit man nicht zielen muss (dasselbe
// Muster wie bei den Workspace-Punkten).
Item {
    id: button

    required property string icon
    required property real size
    // false = Player kann das gerade nicht -> ausgegraut und nicht klickbar
    property bool active: true
    // true = runder Rahmen um das Icon (im ausgeklappten Menue), false = nackt
    // in der Leiste, wo dafuer kein Platz ist
    property bool outlined: false
    // Luft zwischen Glyph und Rahmen
    property real outlinePadding: 9

    // Damit die Pille weiss, ob der Zeiger genau hier steht
    readonly property alias hovered: hover.hovered

    signal triggered

    Layout.preferredWidth: button.outlined ? button.size + button.outlinePadding * 2 : button.size + 4
    Layout.preferredHeight: button.outlined ? button.size + button.outlinePadding * 2 : button.size
    Layout.alignment: Qt.AlignVCenter

    opacity: button.active ? 1 : 0.35

    Behavior on opacity {
        NumberAnimation { duration: 140 }
    }

    Rectangle {
        anchors.fill: parent
        visible: button.outlined

        radius: height / 2
        color: hover.hovered && button.active ? Colors.surfaceContainer : "transparent"
        border.width: 1
        border.color: hover.hovered && button.active ? Colors.primary : Colors.alpha(Colors.outline, 0.5)

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 140 }
        }
    }

    Text {
        anchors.centerIn: parent

        text: button.icon
        color: hover.hovered && button.active ? Colors.primary : Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: button.size

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    HoverHandler {
        id: hover

        enabled: button.active
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: button.active
        onTapped: button.triggered()
    }
}
