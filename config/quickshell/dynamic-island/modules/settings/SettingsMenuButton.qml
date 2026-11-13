pragma ComponentBehavior: Bound
import QtQuick

import qs

// Runder Symbolknopf (Vorgabe ⋮), der ein SettingsMenu aufklappt.
// entries wie SettingsMenu; Liste rechtsbuendig unter dem Knopf
// (`above`: darueber).
Rectangle {
    id: button

    property string icon: "more_vert"
    property var entries: []
    property bool above: false
    // Liste sichtbar (bis das Ausblenden fertig ist), siehe SettingsDropdown
    readonly property bool menuOpen: menu.visible

    implicitWidth: 30
    implicitHeight: 30
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: menu.opened ? Colors.alpha(Colors.fgSurface, 0.14)
         : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
         : "transparent"

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Text {
        anchors.centerIn: parent
        text: button.icon
        color: Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: 18
    }

    HoverHandler {
        id: buttonHover

        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: button.enabled
        onTapped: menu.opened ? menu.close() : menu.open()
    }

    SettingsMenu {
        id: menu

        x: button.width - menu.width
        y: button.above ? -menu.height - 4 : button.height + 4
        minWidth: 180
        entries: button.entries
    }
}
