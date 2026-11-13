import QtQuick

import qs
import qs.modules.services.config

// Kachel eines Farbschemas (ColorsPage.qml): Hintergrund des Schemas als
// Flaeche, darauf Primaer, Sekundaer und Tertiaer; Name darunter.
//
// Eigene Datei statt `component` (Hot-Reload: "... is not a type").
Item {
    id: tile

    // { label, mode, background, primary, secondary, tertiary }
    required property var entry
    required property string title
    property bool current: false
    // Ohne eigene Farben (dynamisches Schema): die laufende Palette, wenn es
    // gesetzt ist – sonst eine neutrale Flaeche mit Symbol, denn die laufenden
    // Farben waeren dann die eines anderen Schemas.
    readonly property bool live: tile.entry.background === ""
    readonly property bool blank: tile.live && !tile.current
    readonly property color bg: tile.live ? Colors.background : tile.entry.background
    readonly property color primary: tile.live ? Colors.primary : tile.entry.primary
    readonly property color secondary: tile.live ? Colors.secondary : tile.entry.secondary
    readonly property color tertiary: tile.live ? Colors.tertiary : tile.entry.tertiary

    signal clicked()

    implicitWidth: 150
    implicitHeight: 100 + 6 + name.implicitHeight

    Rectangle {
        id: card

        width: parent.width
        height: 100
        radius: 14
        // Eine Spur aufgehellt: der blanke Hintergrund dunkler Schemata
        // verschwindet sonst im Fenster (wie ThemeList.qml)
        color: tile.blank ? Colors.alpha(Colors.fgSurface, hover.hovered ? 0.1 : 0.06)
                          : Colors.shade(tile.bg, hover.hovered ? 0.1 : 0.05)
        border.width: tile.current ? 2 : 0
        border.color: Colors.primary

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Text {
            anchors.centerIn: parent
            visible: tile.blank
            text: "wallpaper"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 28
            color: Colors.fgSurfaceVariant
        }

        Row {
            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            visible: !tile.blank
            spacing: 8

            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: tile.primary
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                radius: 9
                color: tile.secondary
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                radius: 9
                color: tile.tertiary
            }
        }

        // Hell oder dunkel
        Text {
            anchors {
                top: parent.top
                right: parent.right
                margins: 8
            }
            visible: !tile.blank && !tile.current
            text: tile.entry.mode === "light" ? "light_mode" : "dark_mode"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 14
            color: Colors.alpha(tile.primary, 0.7)
        }

        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
                margins: 8
            }
            visible: tile.current
            width: 20
            height: 20
            radius: 10
            color: Colors.primary

            Text {
                anchors.centerIn: parent
                text: "check"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 14
                color: Colors.fgPrimary
            }
        }
    }

    Text {
        id: name

        anchors {
            top: card.bottom
            topMargin: 6
        }
        width: parent.width
        text: tile.title
        color: tile.current ? Colors.fgSurface : Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: tile.clicked()
    }
}
