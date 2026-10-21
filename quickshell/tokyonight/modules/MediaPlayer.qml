// Media-Player: eingebettet in die Leiste.
//
// KEIN eigenes Fenster, KEIN Rahmen - das Widget liegt direkt auf der
// (jetzt deckenden) Leiste, hebt sich beim Hovern nur leicht ab. Höhe/Breite werden ueber Layout.* geregelt,
// damit die Leiste nichts davon merkt.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    // An die Leiste melden, ob gerade ein Player existiert
    signal playerChanged(bool active)

    readonly property int prefWidth: 320
    readonly property int prefHeight: 30

    // ============================================================
    // FORMATIERUNG
    // ============================================================

    function formatTime(seconds) {
        if (!seconds || seconds < 0)
            return "0:00"

        let total = Math.floor(seconds)

        let h = Math.floor(total / 3600)
        let m = Math.floor((total % 3600) / 60)
        let s = total % 60

        let mm = h > 0 ? String(m).padStart(2, "0") : String(m)

        return (h > 0 ? h + ":" : "") + mm + ":" + String(s).padStart(2, "0")
    }

    // play/pause als EIN Glyph, das den Zustand zeigt
    function playGlyph(player) {
        return player && player.isPlaying ? "⏸" : "▶"
    }

    // ============================================================
    // AKTIVER SPIELER
    // ============================================================

    // WICHTIG: Mpris.players ist ein UntypedObjectModel, KEIN Array.
    // ".length" waere undefined -> die echte Liste ist ".values".
    // Das Modell braucht ca. 1 s, bis sich ein Player gemeldet hat.
    readonly property var allPlayers: Mpris.players.values

    readonly property var currentPlayer: {
        let all = root.allPlayers

        if (!all || all.length === 0)
            return null

        for (let i = 0; i < all.length; i++) {
            if (all[i].isPlaying)
                return all[i]
        }

        return all[0]
    }

    readonly property bool active: currentPlayer !== null

    onActiveChanged: playerChanged(active)

    // Die position aktualisiert sich laut Doku NICHT von selbst.
    // Ohne dieses Signal steht der Fortschrittsbalken still.
    Timer {
        interval: 1000
        repeat: true

        running: root.currentPlayer !== null
                 && root.currentPlayer.isPlaying
                 && root.currentPlayer.positionSupported

        onTriggered: root.currentPlayer.positionChanged()
    }

    // ============================================================
    // INHALT - zwei Zeilen: [Cover | Titel/Artist | Buttons | Zeit]
    //            darunter der schmale Fortschrittsbalken
    // ============================================================

    // Leichte Abhebung ueber dem Leistenhintergrund beim Hovern
    Rectangle {
        id: bg

        anchors.fill: parent
        radius: 5

        color: mouseArea.containsMouse ? "#1f2335" : "transparent"

        Behavior on color {
            ColorAnimation { duration: 90 }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 2

        // --- Zeile 1: Cover, Titel, Steuerung, Zeit ---

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 25
            spacing: 8

            // Cover
            Rectangle {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                radius: 4

                // Ohne eigenen Hintergrund - die Leiste darunter ist deckend
                color: "transparent"
                clip: true

                Image {
                    id: coverImage

                    anchors.fill: parent

                    source: root.currentPlayer
                        && root.currentPlayer.trackArtUrl !== ""
                        ? root.currentPlayer.trackArtUrl
                        : ""

                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }

                Text {
                    anchors.centerIn: parent

                    visible: coverImage.status !== Image.Ready

                    text: "♪"
                    color: "#3b4261"
                    font.pixelSize: 13
                }
            }

            // Titel / Artist
            Column {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    width: parent.width

                    text: root.currentPlayer
                        && root.currentPlayer.trackTitle !== ""
                        ? root.currentPlayer.trackTitle
                        : "Nichts wiedergegeben"

                    color: "#c0caf5"
                    elide: Text.ElideRight

                    font.pixelSize: 11
                    font.family: "JetBrains Mono"
                    font.bold: true
                }

                Text {
                    width: parent.width

                    text: root.currentPlayer
                        && root.currentPlayer.trackArtist !== ""
                        ? root.currentPlayer.trackArtist
                        : root.currentPlayer
                            ? root.currentPlayer.identity
                            : "—"

                    color: "#565f89"
                    elide: Text.ElideRight

                    font.pixelSize: 9
                    font.family: "JetBrains Mono"
                }
            }

            // Steuerung
            component ControlButton: Text {
                id: btn

                required property string glyph
                required property bool canDo
                required property var onTrigger

                text: glyph

                color: !canDo
                    ? "#3b4261"
                    : (hover.hovered ? "#7aa2f7" : "#a9b1d6")

                opacity: canDo ? 1 : 0.4

                font.pixelSize: 12
                font.family: "JetBrains Mono"

                HoverHandler {
                    id: hover
                    cursorShape: canDo
                        ? Qt.PointingHandCursor
                        : Qt.ArrowCursor
                }

                TapHandler {
                    enabled: btn.canDo
                    onTapped: btn.onTrigger()
                }
            }

            ControlButton {
                glyph: "⏮"
                canDo: root.currentPlayer ? root.currentPlayer.canGoPrevious : false
                onTrigger: root.currentPlayer ? root.currentPlayer.previous() : null
            }

            ControlButton {
                glyph: root.playGlyph(root.currentPlayer)
                canDo: root.currentPlayer ? root.currentPlayer.canControl : false
                onTrigger: root.currentPlayer ? root.currentPlayer.togglePlaying() : null
            }

            ControlButton {
                glyph: "⏭"
                canDo: root.currentPlayer ? root.currentPlayer.canGoNext : false
                onTrigger: root.currentPlayer ? root.currentPlayer.next() : null
            }

            // Laufzeit
            Text {
                text: root.formatTime(root.currentPlayer ? root.currentPlayer.position : 0)
                     + " / " + root.formatTime(root.currentPlayer ? root.currentPlayer.length : 0)

                color: "#565f89"

                font.pixelSize: 9
                font.family: "JetBrains Mono"
            }
        }

        // --- Zeile 2: Fortschrittsbalken ueber volle Breite ---

        Item {
            id: seekBar

            Layout.fillWidth: true
            Layout.preferredHeight: 3

            readonly property real progress: {
                let p = root.currentPlayer

                if (!p || !p.lengthSupported || !p.length || p.length <= 0)
                    return 0

                return Math.max(0, Math.min(1, p.position / p.length))
            }

            // Track
            Rectangle {
                anchors.fill: parent
                radius: 1.5
                color: "#1f2335"
            }

            // Fuellung
            Rectangle {
                width: parent.width * seekBar.progress
                height: parent.height
                radius: 1.5
                color: "#7aa2f7"
            }

            HoverHandler {
                cursorShape: root.currentPlayer && root.currentPlayer.canSeek
                    ? Qt.PointingHandCursor
                    : Qt.ArrowCursor
            }

            TapHandler {
                // seek() nimmt einen VERSATZ in Mikrosekunden
                enabled: root.currentPlayer !== null
                         && root.currentPlayer.canSeek
                         && root.currentPlayer.lengthSupported

                onTapped: function (eventPoint) {
                    let p = root.currentPlayer

                    if (!enabled || !p || !p.length || p.length <= 0)
                        return

                    let ratio = Math.max(0, Math.min(1, eventPoint.position.x / width))

                    p.seek((ratio * p.length - p.position) * 1000000)
                }
            }
        }
    }
}
