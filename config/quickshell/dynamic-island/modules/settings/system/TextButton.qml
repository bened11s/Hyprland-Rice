pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.widgets

// Schlichter Textknopf der Info-Seite; `filled` ist die Hauptaktion.
Rectangle {
    id: button

    required property string label
    property bool filled: false
    signal clicked()

    implicitWidth: buttonLabel.implicitWidth + 24
    implicitHeight: 30
    radius: 8
    opacity: enabled ? 1 : 0.4
    color: button.filled ? Colors.alpha(Colors.primary, buttonHover.hovered ? 0.85 : 1)
                         : Colors.alpha(Colors.fgSurface, buttonHover.hovered ? 0.14 : 0.08)

    Behavior on color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }
    Fade on opacity {}

    Text {
        id: buttonLabel

        anchors.centerIn: parent
        text: button.label
        color: button.filled ? Colors.fgPrimary : Colors.fgSurface
        font.family: Config.font
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    HoverHandler {
        id: buttonHover

        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: button.enabled
        onTapped: button.clicked()
    }
}
