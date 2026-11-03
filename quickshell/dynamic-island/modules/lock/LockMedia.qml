pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs
import qs.modules.widgets
import qs.modules.services.config
import qs.modules.services.media

// Laeuft Musik, liegt unten eine Karte mit Cover, Titel und den drei
// Knoepfen – bedienbar, ohne zu entsperren. Der Grund nimmt die Farbe des
// Covers an (Media.artColor), wie die Medien-Karte der Leiste.
Item {
    id: card

    readonly property color tint: Media.artColor.a > 0 ? Colors.mix(Colors.background, Media.artColor, 0.32)
                                                       : Colors.background

    implicitWidth: 440
    implicitHeight: 84

    Surface {
        anchors.fill: parent
        maxRadius: 26
        baseColor: Colors.alpha(card.tint, 0.78)

        Behavior on baseColor { ColorAnimation { duration: Appearance.morphDuration } }

        Item {
            id: cover

            anchors {
                left: parent.left
                leftMargin: 14
                verticalCenter: parent.verticalCenter
            }
            width: 56
            height: 56

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: Colors.alpha(Colors.fgBackground, 0.08)
            }

            Image {
                id: art

                anchors.fill: parent
                source: Media.art
                sourceSize: Qt.size(112, 112)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }

            Rectangle {
                id: artMask

                anchors.fill: parent
                radius: 14
                layer.enabled: true
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: art
                maskEnabled: true
                maskSource: artMask
                visible: art.status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "music_note"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 26
            }
        }

        Column {
            anchors {
                left: cover.right
                leftMargin: 14
                right: buttons.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 2

            Text {
                width: parent.width
                text: Media.title || Media.source
                elide: Text.ElideRight
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: Media.artist
                elide: Text.ElideRight
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 13
            }
        }

        Row {
            id: buttons

            anchors {
                right: parent.right
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 2

            MediaKey {
                icon: "skip_previous"
                enabled: Media.canPrevious
                onClicked: Media.previous()
            }

            MediaKey {
                icon: Media.playing ? "pause" : "play_arrow"
                filled: true
                enabled: Media.canToggle
                onClicked: Media.playPause()
            }

            MediaKey {
                icon: "skip_next"
                enabled: Media.canNext
                onClicked: Media.next()
            }
        }
    }

    component MediaKey: Item {
        id: key

        property string icon
        property bool filled: false
        signal clicked

        width: key.filled ? 46 : 38
        height: 46
        opacity: key.enabled ? 1 : 0.35

        Rectangle {
            anchors.centerIn: parent
            width: key.filled ? 44 : 38
            height: width
            radius: width / 2
            color: key.filled ? Colors.primary
                 : Colors.alpha(Colors.fgBackground, mouse.containsMouse ? 0.1 : 0)
            scale: mouse.pressed ? 0.9 : 1

            Behavior on scale { NumberAnimation { duration: 90 } }
            Behavior on color { ColorAnimation { duration: Appearance.fadeDuration } }
        }

        Text {
            anchors.centerIn: parent
            text: key.icon
            color: key.filled ? Colors.fgPrimary : Colors.fgBackground
            font.family: "Material Symbols Outlined"
            font.pixelSize: key.filled ? 26 : 24
            font.variableAxes: { "FILL": 1 }
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: key.clicked()
        }
    }
}
