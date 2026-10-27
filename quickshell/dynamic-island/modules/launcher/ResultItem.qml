pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets

import qs
import qs.modules.services.config

// Eine Zeile in der Trefferliste: Icon, Name, Beschreibung.
// Die ausgewählte Zeile bekommt Fläche und einen Balken an der linken Kante.
Rectangle {
    id: item

    required property var modelData
    required property bool selected
    property int position: 0        // Platz in der Liste, steuert den Versatz beim Einblenden

    signal activated()
    signal hovered()
    signal favoriteToggled()

    readonly property bool isCommand: modelData.kind !== "app"
    readonly property bool favoritable: modelData.kind === "app"

    implicitHeight: 44
    radius: 10

    // Beim Tippen bauen sich die Treffer gestaffelt auf
    opacity: 0
    transform: Translate {
        id: slide
        x: -14
    }

    Component.onCompleted: intro.start()

    SequentialAnimation {
        id: intro

        PauseAnimation { duration: Math.min(item.position * 18, 140) }

        ParallelAnimation {
            NumberAnimation {
                target: item
                property: "opacity"
                to: 1
                duration: 150
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: slide
                property: "x"
                to: 0
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }

    color: selected ? Colors.alpha(Colors.primary, 0.14)
         : mouse.containsMouse ? Colors.alpha(Colors.fgSurface, 0.06)
         : "transparent"

    Behavior on color {
        ColorAnimation { duration: 90 }
    }

    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 4
            verticalCenter: parent.verticalCenter
        }
        width: 3
        height: 22
        radius: 1.5
        color: Colors.primary
        opacity: item.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: item.activated()
        onEntered: item.hovered()
    }

    IconImage {
        id: icon

        anchors {
            left: parent.left
            leftMargin: 16
            verticalCenter: parent.verticalCenter
        }
        // Der Pfad als eigene String-Property, nicht ueber `source` geprueft:
        // `source` ist eine url, und `url !== ""` ist in JS immer wahr (andere
        // Typen, kein Vergleich). Dadurch galt der Eintrag stets als "hat ein
        // Icon" – die Zeile der Aktionen blieb links leer, weil die
        // Material-Symbols-Alternative darunter nie sichtbar wurde.
        readonly property string iconPath: item.isCommand || !item.modelData.icon
            ? "" : Quickshell.iconPath(item.modelData.icon, "application-x-executable")

        implicitSize: 26
        source: icon.iconPath
        visible: icon.iconPath !== ""
    }

    Text {
        anchors {
            left: parent.left
            leftMargin: 16
            verticalCenter: parent.verticalCenter
        }
        visible: !icon.visible
        text: item.modelData.icon || "bolt"
        font.family: "Material Symbols Outlined"
        font.pixelSize: 24
        color: Colors.primary
    }

    // Favoriten-Stern: nur bei Apps, sichtbar bei Hover/Auswahl oder wenn gesetzt
    Rectangle {
        id: star

        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        width: 28
        height: 28
        radius: height / 2
        visible: item.favoritable && (item.selected || mouse.containsMouse || item.modelData.favorite)
        color: starArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

        MouseArea {
            id: starArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.favoriteToggled()
        }

        Text {
            font.family: Config.font
            anchors.centerIn: parent
            text: item.modelData.favorite ? "★" : "☆"
            font.pixelSize: 15
            color: item.modelData.favorite ? Colors.primary : Colors.fgSurfaceVariant
        }
    }

    Column {
        anchors {
            left: parent.left
            leftMargin: 54
            right: star.visible ? star.left : parent.right
            rightMargin: 16
            verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
            font.family: Config.font
            width: parent.width
            text: item.modelData.name
            color: Colors.fgSurface
            font.pixelSize: 13
            font.weight: item.selected ? Font.Medium : Font.Normal
            elide: Text.ElideRight
        }

        Text {
            font.family: Config.font
            width: parent.width
            visible: text !== ""
            text: item.modelData.desc ?? ""
            color: Colors.fgSurfaceVariant
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }
}
