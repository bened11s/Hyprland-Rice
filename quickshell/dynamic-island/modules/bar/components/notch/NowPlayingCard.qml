pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs
import qs.modules.services.config
import qs.modules.services.media
import qs.modules.widgets

// Eine "Jetzt laeuft"-Karte (siehe NowPlayingRow): verwaschener Cover-Blend
// als Hintergrund, davor Cover, Titel/Interpret, Visualiser, Play/Pause.
// Hintergrund und Inhalt sind getrennt verschiebbar: bei der Wisch-Geste
// wandert nur der Blend (`shift`), der Inhalt bleibt stehen. Die zweite
// Karte der Geste ist dieselbe Komponente ohne Inhalt (`showContent`), damit
// ihr Blend beim Wechsel exakt an derselben Stelle landet.
//
// `track` ist ein Objekt wie aus MediaQueue ({ title, artist, art }); null
// heisst leer – nur der Blend des laufenden Titels, wenn die Queue unbekannt
// ist.
Item {
    id: card

    property var track: null
    // Nur die echte Karte nimmt Klicks an
    property bool live: false
    // Kartenfarbe, in die der Cover-Hintergrund nach rechts ausblendet
    property color fadeColor: Appearance.notchColor
    // Versatz nur des Hintergrunds (Wisch-Geste); der Inhalt bleibt stehen
    property real shift: 0
    // Cover, Titel, Visualiser, Knopf – aus fuer die reine Blend-Karte
    property bool showContent: true
    // Deckkraft des Inhalts, fuer das Ueberblenden beim Titelwechsel
    property real contentOpacity: 1
    readonly property real artSize: 36

    readonly property string artSource: card.track?.art ?? ""
    readonly property bool filled: !!card.track

    // ---- Hintergrund: Karte mit verwaschenem Cover ----
    // Das Cover, stark verwaschen ueber die ganze Zeile gezogen und nach
    // rechts in die Kartenfarbe ausgeblendet – so bleibt der Text lesbar.
    // Winzige Decodegroesse: der Weichzeichner macht ohnehin alles glatt.
    Rectangle {
        id: bg

        readonly property real strength: 0.45

        anchors.fill: parent
        transform: Translate { x: card.shift }
        radius: 16
        color: Colors.alpha(Colors.fgBackground, 0.05)

        Item {
            anchors.fill: parent
            visible: blendSource.status === Image.Ready

            Image {
                id: blendSource

                anchors.fill: parent
                source: card.filled ? card.artSource : Media.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 48
                sourceSize.height: 48
                visible: false
            }

            Rectangle {
                id: blendMask

                anchors.fill: parent
                radius: bg.radius
                color: "black"
                layer.enabled: true
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: blendSource
                blurEnabled: true
                blur: 1
                blurMax: 32
                maskEnabled: true
                maskSource: blendMask
                opacity: bg.strength
            }

            Rectangle {
                anchors.fill: parent
                radius: bg.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Colors.alpha(card.fadeColor, 0.15) }
                    GradientStop { position: 0.55; color: Colors.alpha(card.fadeColor, 0.6) }
                    GradientStop { position: 1.0; color: Colors.alpha(card.fadeColor, 0.85) }
                }
            }
        }
    }

    // ---- Inhalt: steht fest, waehrend der Hintergrund wandert ----
    Item {
        id: content

        anchors.fill: parent
        visible: card.filled && card.showContent
        opacity: card.contentOpacity

        // ---- Cover, rund maskiert ----
        Item {
            id: art

            anchors {
                left: parent.left
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            width: card.artSize
            height: card.artSize

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Colors.surfaceContainer

                Text {
                    anchors.centerIn: parent
                    visible: artImage.status !== Image.Ready
                    text: "music_note"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 16
                }
            }

            Image {
                id: artImage

                anchors.fill: parent
                source: card.artSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: card.artSize * 2
                sourceSize.height: card.artSize * 2
                visible: false
            }

            Rectangle {
                id: artMask

                anchors.fill: parent
                radius: 10
                color: "black"
                layer.enabled: true
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: artImage
                maskEnabled: true
                maskSource: artMask
                visible: artImage.status === Image.Ready
            }
        }

        // ---- Titel / Interpret ----
        Column {
            anchors {
                left: art.right
                leftMargin: 10
                right: wave.left
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 2

            Text {
                width: parent.width
                text: (card.track?.title ?? "") || Media.source
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: (card.track?.artist ?? "") || Media.source
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        // ---- Visualiser ----
        // Rechnet nur, solange der Inhalt sichtbar ist (Visualizer prueft
        // `visible`) – die reine Blend-Karte kostet also keine Cava-Pegel.
        Visualizer {
            id: wave

            anchors {
                right: playButton.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            height: 22
            count: 7
            barWidth: 3
            active: Media.playing
        }

        // ---- Play/Pause ----
        Item {
            id: playButton

            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            width: 32
            height: 32
            scale: playHover.hovered ? 1.08 : 1

            Morph on scale {}

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: playHover.hovered ? Colors.alpha(Colors.primary, 0.3) : Colors.alpha(Colors.primary, 0.18)
            }

            Text {
                anchors.centerIn: parent
                text: Media.playing ? "pause" : "play_arrow"
                color: Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 18
                font.variableAxes: ({ FILL: 1, wght: 600 })
            }

            HoverHandler {
                id: playHover

                enabled: card.live
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                enabled: card.live
                onTapped: Media.playPause()
            }
        }
    }
}
