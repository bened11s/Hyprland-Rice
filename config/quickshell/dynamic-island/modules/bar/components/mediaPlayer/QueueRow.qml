pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

import qs
import qs.modules.services.config

// Eine Zeile der Warteschlange im ausgeklappten Medien-Menue: kleines
// rundes Cover, darueber eine Bildunterschrift ("Zuvor" / "Als Naechstes"),
// dann Titel und Interpret. Ein Klick springt dorthin.
//
// `track` ist ein Eintrag aus MediaQueue (title/artist/art/queued), `art`
// kommt dort schon als file:// oder "" (noch nicht geladen) an.
//
// Kompakt (`compact: true`, in der aufgeklappten Liste): kleineres Cover,
// keine Bildunterschrift, dafuer links die Position in der Warteschlange.
// Der "Warteschlange"-Hinweis rueckt dann neben den Titel.
Item {
    id: row

    required property var track
    property string caption: ""
    // Grundfarbe der Karte, davon setzt sich der Hover ab (siehe MediaPanel)
    property color tint: Colors.background
    property real artSize: row.compact ? 26 : 34
    property bool compact: false
    // Positionsnummer (nur kompakt), 0 = keine
    property int number: 0

    signal triggered

    readonly property string title: row.track?.title ?? ""
    readonly property string artist: row.track?.artist ?? ""
    readonly property string art: row.track?.art ?? ""
    readonly property bool queued: row.track?.queued ?? false

    Layout.fillWidth: true
    Layout.preferredHeight: row.artSize + (row.compact ? 6 : 8)
    implicitHeight: Layout.preferredHeight

    // Beim Titelwechsel blendet der Inhalt kurz ein – einmalig, kein
    // Behavior: die Zeile soll nicht auf jede Pegel- oder Hover-Aenderung
    // reagieren, nur auf den neuen Eintrag.
    onTitleChanged: swap.restart()

    NumberAnimation {
        id: swap

        target: body
        property: "opacity"
        from: 0.25
        to: 1
        duration: Appearance.fadeDuration * 1.5
        easing.type: Easing.OutCubic
    }

    Rectangle {
        anchors.fill: parent

        radius: row.compact ? 8 : 10
        color: hover.hovered ? Colors.shade(row.tint, 0.11) : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    RowLayout {
        id: body

        anchors {
            fill: parent
            leftMargin: 4
            rightMargin: 8
        }
        spacing: row.compact ? 8 : 10

        // ---- Position (nur kompakt) ----
        Text {
            visible: row.compact && row.number > 0
            Layout.preferredWidth: 16
            Layout.alignment: Qt.AlignVCenter

            font.family: Config.font
            text: row.number
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.55)
            font.pixelSize: 9
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }

        // ---- Cover ----
        // Rund maskiert wie in der Notch-Zeile (NowPlayingRow): `clip`
        // schneidet nur rechteckig.
        Rectangle {
            Layout.preferredWidth: row.artSize
            Layout.preferredHeight: row.artSize
            Layout.alignment: Qt.AlignVCenter

            radius: row.compact ? 7 : 9
            color: Colors.shade(row.tint, 0.08)

            Image {
                id: artImage

                anchors.fill: parent
                source: row.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: row.artSize * 2
                sourceSize.height: row.artSize * 2
                visible: false
            }

            Item {
                id: artMask

                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: row.compact ? 7 : 9
                    color: "black"
                }
            }

            MultiEffect {
                anchors.fill: parent
                visible: artImage.status === Image.Ready

                source: artImage
                maskEnabled: true
                maskSource: artMask
            }

            Text {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready

                text: "music_note"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: row.compact ? 12 : 15
            }
        }

        // ---- Bildunterschrift, Titel, Interpret ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            RowLayout {
                visible: !row.compact
                Layout.fillWidth: true
                spacing: 6

                Text {
                    font.family: Config.font
                    text: row.caption
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.75)
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                // Von Hand in die Warteschlange gelegt – kleiner Hinweis in
                // der Akzentfarbe, damit man es von der Playlist unterscheidet
                QueueTag {
                    visible: row.queued && !row.compact
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    font.family: Config.font
                    Layout.fillWidth: true

                    text: row.title
                    color: Colors.fgBackground
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                // Kompakt gibt es keine Bildunterschrift – der Hinweis
                // sitzt dann neben dem Titel
                QueueTag {
                    visible: row.queued && row.compact
                }
            }

            Text {
                font.family: Config.font
                Layout.fillWidth: true
                visible: text !== ""

                text: row.artist
                color: Colors.fgSurfaceVariant
                font.pixelSize: row.compact ? 8.5 : 9
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }
    }

    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: row.triggered()
    }
}
