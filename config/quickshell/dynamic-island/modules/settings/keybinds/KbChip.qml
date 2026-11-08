import QtQuick

import qs
import qs.modules.services.config

// Knopf als Pille: Symbol und/oder Text, wahlweise angewaehlt (Filter) oder
// betont (Hauptaktion, gefuellt in der Akzentfarbe).
Rectangle {
    id: chip

    property string icon: ""
    property string label: ""
    property bool checked: false
    property bool primary: false
    property bool danger: false
    property int size: 28

    signal clicked

    width: chipRow.implicitWidth + (chip.label !== "" ? 22 : 14)
    height: chip.size
    radius: height / 2
    opacity: chip.enabled ? 1 : 0.4
    color: chip.primary ? Colors.alpha(Colors.primary, chipHover.hovered ? 1 : 0.9)
         : chip.checked ? Colors.alpha(Colors.primary, chipHover.hovered ? 0.3 : 0.2)
         : Colors.alpha(chip.danger && chipHover.hovered ? Colors.error : Colors.fgSurface, chipHover.hovered ? 0.12 : 0.06)
    border.width: 1
    border.color: chip.primary ? "transparent"
                : chip.checked ? Colors.alpha(Colors.primary, 0.5)
                : Colors.alpha(Colors.outline, 0.3)

    Behavior on color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }

    Row {
        id: chipRow

        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.icon !== ""
            text: chip.icon
            color: chip.primary ? Colors.fgPrimary
                 : chip.checked ? Colors.primary
                 : chip.danger && chipHover.hovered ? Colors.error
                 : Colors.fgSurfaceVariant
            font.family: "Material Symbols Outlined"
            font.pixelSize: Math.round(chip.size * 0.55)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.label !== ""
            text: chip.label
            color: chip.primary ? Colors.fgPrimary
                 : chip.checked ? Colors.primary
                 : chip.danger && chipHover.hovered ? Colors.error
                 : Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 12
            font.weight: chip.primary || chip.checked ? Font.DemiBold : Font.Medium
        }
    }

    HoverHandler {
        id: chipHover

        enabled: chip.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: chip.enabled
        onTapped: chip.clicked()
    }
}
