import QtQuick

import qs
import qs.modules.services.config

// Knopf der Bearbeitungs-Oberflaeche (EditBar, WidgetOptions, WidgetPicker)
// im Stil des Einstellungsfensters. Mit `text`: Textknopf (Hoehe 30,
// radius 8; `primary` = Hauptaktion, `danger` = bestaetigt etwas
// Endgueltiges, `active` = gedrueckt gehalten). Mit `icon`: flacher runder
// Symbolknopf ohne Grund.
Rectangle {
    id: button

    property string text: ""
    property string icon: ""
    property bool primary: false
    property bool danger: false
    property bool active: false
    signal clicked

    readonly property bool flat: button.icon !== ""

    implicitWidth: button.flat ? 28 : label.implicitWidth + 24
    implicitHeight: button.flat ? 28 : 30
    radius: button.flat ? height / 2 : 8
    opacity: enabled ? 1 : 0.4
    // Flach + danger (Papierkorb): erst beim Hovern rot
    color: button.flat ? Colors.alpha(button.danger ? Colors.error : Colors.fgSurface, buttonHover.hovered ? (button.danger ? 0.18 : 0.1) : 0)
         : button.danger ? Colors.alpha(Colors.error, buttonHover.hovered ? 0.85 : 1)
         : button.primary ? Colors.alpha(Colors.primary, buttonHover.hovered ? 0.85 : 1)
         : Colors.alpha(Colors.fgSurface, button.active ? 0.18 : buttonHover.hovered ? 0.13 : 0.08)

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: button.flat ? button.icon : button.text
        color: button.flat ? (button.danger && buttonHover.hovered ? Colors.error : Colors.fgSurfaceVariant)
             : button.danger ? Colors.fgError : button.primary ? Colors.fgPrimary : Colors.fgSurface
        font.family: button.flat ? "Material Symbols Outlined" : Config.font
        font.pixelSize: button.flat ? 18 : 12
        font.weight: button.primary || button.danger ? Font.DemiBold : Font.Normal
    }

    HoverHandler {
        id: buttonHover

        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: button.enabled
        onTapped: button.clicked()
    }
}
