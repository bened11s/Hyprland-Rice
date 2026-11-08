pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.services.media
import qs.modules.services.audio

import qs
import qs.modules.services.config

// Ausklapp-Inhalt der Medien-Pille – kein eigenes Fenster, sondern ein Teil
// der Karte selbst (dasselbe Prinzip wie DatePanel in der Notch). Dadurch
// waechst die Pille nach unten, statt dass darunter ein zweites Fenster
// aufpoppt: eine Flaeche, keine Naht.
//
// Von oben nach unten: Quellenwahl (eigene, abgesetzte Karte), grosses Cover
// mit Visualiser-Ring, Titel, Fortschritt mit den beiden Zeiten, Transport,
// darunter – nur bei Spotify – voriger und naechster Titel (QueueRow).
Item {
    id: panel

    // Oberkante innerhalb der Karte (= Unterkante der Icon-Reihe)
    property real topOffset: 0
    // Grundfarbe der Karte – die Flaechen hier drin setzen sich davon ab,
    // statt feste Theme-Toene zu nehmen. Sonst beisst sich das Blau des
    // Themes mit einer vom Cover eingefaerbten Karte.
    property color tint: Colors.background
    property real padding: 14

    // Cover samt Ring fuellen die Karte bis auf den Rand. Die Rechnung laeuft
    // von aussen nach innen: das Aussenmass steht fest (Kartenbreite minus
    // Rand), davon gehen Balkenlaenge und Luft ab, der Rest ist das Bild.
    readonly property real ringMax: 16      // maximale Balkenlaenge
    readonly property real ringGap: 8       // Luft zwischen Bild und Balken
    readonly property real ringInset: 10    // Luft zwischen Ring und Kartenrand
    readonly property real ringBox: panel.width - panel.padding * 2 - panel.ringInset * 2
    // Obergrenze fuer das Cover – das Medien-Untermenue der Notch ist breit,
    // dort sollen nur die Zeilen die Breite nutzen, nicht das Bild
    property real maxCoverSize: Infinity
    readonly property real coverSize: Math.min(panel.maxCoverSize,
        Math.max(48, panel.ringBox - (panel.ringGap + panel.ringMax) * 2))
    readonly property int coverDecode: Number.isFinite(panel.maxCoverSize) ? panel.maxCoverSize * 2 : 380
    // Innenkante des Rings – die Balken wachsen von hier nach aussen
    readonly property real ringRadius: panel.coverSize / 2 + panel.ringGap

    // Platz, den die Karte fuer das Panel bereithalten muss
    readonly property real outerHeight: panel.implicitHeight

    anchors {
        left: parent.left
        right: parent.right
    }
    y: panel.topOffset
    implicitHeight: layout.implicitHeight + panel.padding

    ColumnLayout {
        id: layout

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: panel.padding
            rightMargin: panel.padding
        }
        spacing: 12

        // ---- Quellenwahl ----
        // Eigene Karte mit abgesetztem Grund und Rand: das ist der einzige
        // Teil, der den Zustand des Players aendert, statt ihn nur
        // anzuzeigen – das darf man sehen.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: sources.implicitHeight + 8

            radius: 10
            color: Colors.shade(panel.tint, 0.05)
            border.width: 1
            border.color: Colors.alpha(Colors.outline, 0.4)

            ColumnLayout {
                id: sources

                property bool open: false

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 4
                }
                spacing: 0

                // Kopfzeile: zeigt die aktuelle Quelle, klappt die Liste auf
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24

                    radius: 8
                    color: sourceHover.hovered ? Colors.shade(panel.tint, 0.11) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 140 }
                    }

                    Text {
                        font.family: Config.font
                        anchors {
                            left: parent.left
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: parent.width - 32

                        text: Media.source || I18n.tr("Keine Quelle")
                        color: Colors.fgBackground
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }

                        text: sources.open ? "keyboard_arrow_up" : "keyboard_arrow_down"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 14
                    }

                    HoverHandler {
                        id: sourceHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: sources.open = !sources.open
                    }
                }

                // Die Liste. Sie zaehlt in die implicitHeight, dadurch
                // waechst die Karte beim Aufklappen von selbst mit.
                Repeater {
                    model: sources.open ? Media.players : null

                    delegate: Rectangle {
                        id: entry

                        required property var modelData
                        readonly property bool current: Media.active === entry.modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 22

                        radius: 8
                        color: entryHover.hovered ? Colors.shade(panel.tint, 0.11) : "transparent"

                        Text {
                            font.family: Config.font
                            anchors {
                                left: parent.left
                                leftMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            width: parent.width - 30

                            text: Media.identityOf(entry.modelData)
                            color: entry.current ? Colors.primary : Colors.fgSurfaceVariant
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        // Punkt = spielt gerade
                        Rectangle {
                            anchors {
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            visible: entry.modelData.isPlaying

                            width: 5
                            height: 5
                            radius: 2.5
                            color: Colors.primary
                        }

                        HoverHandler {
                            id: entryHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                Media.select(entry.modelData);
                                sources.open = false;
                            }
                        }
                    }
                }
            }
        }

        // ---- Cover mit Ring ----
        Item {
            Layout.preferredWidth: (panel.ringRadius + panel.ringMax) * 2
            Layout.preferredHeight: (panel.ringRadius + panel.ringMax) * 2
            Layout.alignment: Qt.AlignHCenter

            // Der Ring: ein Balken je cava-Band, im Kreis angeordnet.
            // Jeder sitzt auf seinem Winkel und waechst nach aussen,
            // deshalb liegt der Mittelpunkt bei Radius + halbe Laenge.
            Repeater {
                model: Cava.bars

                delegate: Rectangle {
                    id: spike

                    required property int index

                    readonly property real angle: (spike.index / Cava.bars) * 2 * Math.PI
                    // Versteckt (Pille im Notch-Layout, zugeklapptes
                    // Untermenue) liegt der Ring still, statt fuer niemanden
                    // 30x pro Sekunde zu rechnen
                    readonly property real len: 3 + (panel.visible ? Cava.values[spike.index] ?? 0 : 0) * panel.ringMax
                    readonly property real dist: panel.ringRadius + len / 2

                    width: 2.5
                    height: spike.len
                    radius: width / 2
                    color: Colors.primary
                    opacity: Media.playing ? 1 : 0.3

                    x: parent.width / 2 + Math.sin(spike.angle) * spike.dist - width / 2
                    y: parent.height / 2 - Math.cos(spike.angle) * spike.dist - height / 2
                    rotation: (spike.index / Cava.bars) * 360

                    // Kein Behavior auf height: die Spitzen folgen cava
                    // direkt (siehe widgets/Visualizer.qml – sonst zeichnet
                    // die Leiste dauerhaft mit Monitorrate)
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }
            }

            // ---- Cover ----
            // Je nach Config.media.cover das runde Bild oder die
            // Schallplatte (VinylCover) – ein Loader, damit nur eines von
            // beiden das Bild decodiert.
            Loader {
                anchors.centerIn: parent
                sourceComponent: Config.media.cover === "vinyl" ? vinylCover : roundCover
            }

            Component {
                id: vinylCover

                VinylCover {
                    size: panel.coverSize
                    tint: panel.tint
                    source: Media.art
                    decode: panel.coverDecode
                    // Dreht nur, solange etwas laeuft und man es sieht
                    spinning: Media.playing && panel.visible
                }
            }

            // Rund, passend zum Ring. `clip: true` reicht dafuer nicht –
            // das schneidet nur am Rechteck. Deshalb eine Kreis-Maske.
            Component {
                id: roundCover

                Rectangle {
                    width: panel.coverSize
                    height: panel.coverSize
                    radius: width / 2
                    color: Colors.shade(panel.tint, 0.08)

                    Image {
                        id: cover

                        anchors.fill: parent
                        source: Media.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Feste Decodiergroesse: haengt sie an coverSize (= an der
                        // Kartenbreite), decodiert jede Morph-Animation das Cover
                        // pro Frame neu
                        sourceSize.width: panel.coverDecode
                        sourceSize.height: panel.coverDecode
                        // Wird nur als Quelle fuer den Effekt gebraucht
                        visible: false
                    }

                    Item {
                        id: coverMask

                        anchors.fill: parent
                        layer.enabled: true
                        visible: false

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "black"
                        }
                    }

                    MultiEffect {
                        anchors.fill: parent
                        visible: cover.status === Image.Ready

                        source: cover
                        maskEnabled: true
                        maskSource: coverMask
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready

                        text: "music_note"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 22
                    }
                }
            }
        }

        // ---- Titel ----
        Text {
            font.family: Config.font
            Layout.fillWidth: true

            text: Media.title || I18n.tr("Nichts")
            color: Colors.fgBackground
            font.pixelSize: 12
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Text {
            font.family: Config.font
            Layout.fillWidth: true
            Layout.topMargin: -8
            visible: text !== ""

            text: Media.artist
            color: Colors.fgSurfaceVariant
            font.pixelSize: 10
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        // ---- Fortschritt ----
        // Abgelaufene Zeit links, Gesamtlaenge rechts, der Slider dazwischen.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                font.family: Config.font
                text: Media.formatTime(Media.position)
                color: Colors.fgSurfaceVariant
                font.pixelSize: 9
                font.weight: Font.Medium
            }

            Rectangle {
                id: track

                Layout.fillWidth: true
                Layout.preferredHeight: 4
                Layout.alignment: Qt.AlignVCenter

                radius: height / 2
                color: Colors.alpha(Colors.outline, 0.5)
                // Ohne bekannte Laenge gibt es nichts anzuzeigen
                opacity: Media.hasLength ? 1 : 0.4

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: parent.width * Media.progress

                    radius: parent.radius
                    color: Colors.primary
                }

                // Trefferflaeche hoeher als der Balken – 4px trifft niemand
                Item {
                    id: hit

                    anchors.centerIn: parent
                    width: parent.width
                    height: 16

                    TapHandler {
                        enabled: Media.canSeek && Media.hasLength
                        onTapped: point => Media.seek(point.position.x / hit.width)
                    }

                    DragHandler {
                        id: scrub

                        enabled: Media.canSeek && Media.hasLength
                        target: null
                        yAxis.enabled: false

                        onCentroidChanged: if (scrub.active) Media.seek(scrub.centroid.position.x / hit.width)
                    }

                    HoverHandler {
                        cursorShape: Media.hasLength ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }

            Text {
                font.family: Config.font
                text: Media.hasLength ? Media.formatTime(Media.length) : "--:--"
                color: Colors.fgSurfaceVariant
                font.pixelSize: 9
                font.weight: Font.Medium
            }
        }


        // ---- Transport ----
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14

            MediaButton {
                icon: "skip_previous"
                outlined: true
                size: 20
                active: Media.canPrevious
                onTriggered: Media.previous()
            }

            MediaButton {
                icon: Media.playing ? "pause" : "play_arrow"
                outlined: true
                size: 26
                active: Media.canToggle
                onTriggered: Media.playPause()
            }

            MediaButton {
                icon: "skip_next"
                outlined: true
                size: 20
                active: Media.canNext
                onTriggered: Media.next()
            }
        }

        // ---- Songtext ----
        // Nur mit Config.media.lyrics. Derselbe Bauplan wie die Warteschlange
        // darunter: Haarlinie, Block mit animierter Wunschhoehe, der auf Null
        // faehrt, wenn es nichts zu zeigen gibt. Ob der Text aufgeklappt ist,
        // weiss nur LyricsView (lokal, nicht in der Config).
        Item {
            id: lyricsBlock

            readonly property bool shown: Config.media.lyrics && Media.available
            readonly property real gap: layout.spacing

            Layout.fillWidth: true
            Layout.topMargin: -lyricsBlock.gap
            Layout.preferredHeight: lyricsBlock.shown ? lyricsCol.implicitHeight + lyricsBlock.gap : 0

            clip: true
            opacity: lyricsBlock.shown ? 1 : 0
            visible: Layout.preferredHeight > 0

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                id: lyricsCol

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: lyricsBlock.gap
                }
                spacing: 2

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.bottomMargin: 4
                    color: Colors.alpha(Colors.outline, 0.35)
                }

                LyricsView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    tint: panel.tint
                    shown: panel.visible && lyricsBlock.shown
                }
            }
        }

        // ---- Warteschlange ----
        // Voriger und naechster Titel aus der Spotify-Queue (MediaQueue), als
        // zwei ruhige Zeilen unter einer Haarlinie. Gibt es keine Queue
        // (anderer Player, Extension nicht verbunden), faehrt der Block auf
        // Null zusammen – der obere Teil sieht dann aus wie ohne ihn. Der
        // Abstand zur Transportreihe steckt mit im Block (topMargin hebt den
        // Layout-Abstand auf), damit zusammengeklappt auch die Luft weg ist.
        //
        // Darunter ein Umschalter "Warteschlange · N weitere", der die
        // restlichen Titel als kompakte, scrollbare Liste aufklappt
        // (Config.media.queueOpen, bleibt ueber Neustarts).
        Item {
            id: queue

            readonly property bool shown: MediaQueue.valid
                                          && (!!MediaQueue.previous || !!MediaQueue.upcoming)
            // Weitere Titel nach "Als Naechstes"
            readonly property int more: Math.max(0, MediaQueue.next.length - 1)
            readonly property bool open: Config.media.queueOpen && queue.more > 0
            // Luft ueber der Haarlinie, gehoert zum Block
            readonly property real gap: layout.spacing

            Layout.fillWidth: true
            Layout.topMargin: -queue.gap
            // Die Liste liegt ausserhalb von queueRows und zaehlt nur
            // aufgeklappt mit: so hat die Hoehe ein festes Ziel und eine
            // einzige Animation, die Liste wird beim Zuklappen vom Rand
            // abgeschnitten statt vorher zu verschwinden
            Layout.preferredHeight: queue.shown
                ? queueRows.implicitHeight + queue.gap + (queue.open ? queueList.height + queueList.anchors.topMargin : 0)
                : 0

            clip: true
            opacity: queue.shown ? 1 : 0
            // Unsichtbare Elemente ueberspringt das Layout ganz (auch ihre
            // Raender) – deshalb an der animierten Wunschhoehe festmachen,
            // nicht an `height`, das vom Layout erst gesetzt wird
            visible: Layout.preferredHeight > 0

            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                id: queueRows

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: queue.gap
                }
                spacing: 2

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.bottomMargin: 4
                    color: Colors.alpha(Colors.outline, 0.35)
                }

                QueueRow {
                    visible: !!MediaQueue.previous
                    track: MediaQueue.previous
                    caption: I18n.tr("Zuvor")
                    tint: panel.tint
                    // Spotifys "Zurueck" startet den laufenden Titel neu, wenn
                    // er schon ein paar Sekunden laeuft – erst an den Anfang,
                    // dann springt es wirklich zum vorigen
                    onTriggered: {
                        Media.seek(0);
                        Media.previous();
                    }
                }

                QueueRow {
                    visible: !!MediaQueue.upcoming
                    track: MediaQueue.upcoming
                    caption: I18n.tr("Als Nächstes")
                    tint: panel.tint
                    onTriggered: Media.next()
                }

                // Umschalter: nur, wenn es ueberhaupt mehr gibt
                Item {
                    id: queueToggle

                    visible: queue.more > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: toggleHover.hovered ? Colors.shade(panel.tint, 0.11) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        font.family: Config.font
                        text: I18n.tr(queue.more === 1 ? "Warteschlange · %1 weiterer" : "Warteschlange · %1 weitere").arg(queue.more)
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.75)
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors {
                            right: parent.right
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        text: "expand_more"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 14
                        rotation: queue.open ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                        }
                    }

                    HoverHandler {
                        id: toggleHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: Config.set("media", "queueOpen", !Config.media.queueOpen)
                    }
                }
            }

            // Die Liste haengt unter den Zeilen; ihre Hoehe ist immer die
            // volle Wunschhoehe, ob sie zu sehen ist, entscheidet der
            // Block drueber (siehe Layout.preferredHeight)
            QueueList {
                id: queueList

                anchors {
                    left: parent.left
                    right: parent.right
                    top: queueRows.bottom
                    topMargin: 2
                }
                height: wantedHeight
                visible: queue.more > 0
                tint: panel.tint
            }
        }
    }
}
