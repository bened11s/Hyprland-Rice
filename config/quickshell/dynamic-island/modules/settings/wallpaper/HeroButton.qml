import QtQuick

import qs
import qs.modules.services.config

// Grosser tonaler Knopf (Hoehe 48, voll gerundet) fuer den Wallpaper-Kopf
// (WallpaperHero.qml) und die Bibliothek (WallpaperManager.qml): Symbol und
// Text, `filled` fuer die Hauptaktion; ohne `label` ein runder Symbolknopf.
//
// Eigene Datei statt `component`: Inline-Components, die beim Hot-Reload zu
// einer bestehenden Datei dazukommen, loest Quickshell bis zum Neustart
// nicht auf ("... is not a type").
Rectangle {
    id: button

    property string icon: ""
    property string label: ""
    property bool filled: false
    signal clicked()

    readonly property color fg: button.filled ? Colors.fgPrimary : Colors.primary

    implicitWidth: button.label === "" ? 48 : buttonRow.implicitWidth + 52
    implicitHeight: 48
    radius: height / 2
    color: button.filled ? (buttonHover.hovered ? Colors.alpha(Colors.primary, 0.88) : Colors.primary)
                         : Colors.alpha(Colors.primary, buttonHover.hovered ? 0.22 : 0.14)

    Behavior on color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }

    Row {
        id: buttonRow

        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.icon !== ""
            text: button.icon
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
            color: button.fg
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.label !== ""
            text: button.label
            font.family: Config.font
            font.pixelSize: 15
            font.weight: Font.Medium
            color: button.fg
        }
    }

    HoverHandler {
        id: buttonHover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: button.clicked()
    }
}
