pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.services.hypr
import qs.modules.services.media

import qs
import qs.modules.services.config
import qs.modules.widgets

// Medien-Pille rechts in der Leiste.
//
// Aufbau, von links nach rechts: Cover, Visualiser (4 Balken), Zeit, zurueck,
// Play/Pause, weiter, Aufklapp-Pfeil – alles auf einer Zeile und vertikal
// mittig.
//
// Der Pfeil klappt die Karte nach unten auf: kein zweites Fenster, sondern
// dieselbe Flaeche, die hoeher wird (genau wie die Notch mit ihrem DatePanel).
// Damit gibt es keine Naht zwischen Pille und Menue. Das Bar-Fenster muss den
// Platz dafuer reservieren – siehe `maxDrop`, das Bar.qml abfragt.
//
// Alles Inhaltliche kommt aus dem Media-Service (modules/services/media),
// die Pegel aus Cava (modules/services/audio). Diese Datei ist reine Ansicht.
Item {
    id: root
    anchors {
        right: parent.right
        rightMargin: HyprGaps.right
    }

    required property real verticalMargin // margin über bzw unter der notch
    required property real borderWidth   // von außen überschreibbar (Bar.qml macht das)
    required property color borderColor
    required property real cardRadius    // gemeinsamer Wert mit Notch und Selektor

    property real padding: 14

    // Ist die Karte aufgeklappt?
    property bool expanded: false

    // Groessen der Einzelteile – hier einmal, damit die Breite unten daraus
    // ausgerechnet werden kann statt doppelt gepflegt zu werden.
    readonly property real artSize: 18
    readonly property real iconSize: 15
    readonly property real barWidth: 2
    readonly property real barSpacing: 2

    // Untergrenze der Breite: der ausgeklappte Teil mit Cover, Ring und Titel
    // waere schmaler zu gedraengt. Die Reihe oben darf breiter werden.
    readonly property real minWidth: 250

    // Grundfarbe der Karte: der Mittelton des Covers, kraeftig abgedunkelt und
    // entsaettigt – sonst leuchtet die Leiste. Kennt der Service keine Farbe
    // (kein Cover), bleibt es beim Theme-Grund.
    readonly property color cardColor: Media.artColor.a > 0
        ? Qt.hsla(Media.artColor.hslHue,
                  Math.min(Media.artColor.hslSaturation, 0.30),
                  0.14,
                  1)
        : Colors.background

    // Hoehen: eingeklappt wie die anderen Karten. Ausgeklappt weicht die
    // Leisten-Zeile zur Seite und die Karte gehoert allein dem Panel – sie ist
    // dann genau so hoch wie dessen Inhalt plus dem Rand oben.
    readonly property real collapsedHeight: parent.height - verticalMargin
    readonly property real panelTop: 10
    readonly property real expandedHeight: root.panelTop + panel.outerHeight
    // Platz, den sich das Bar-Fenster nach unten nehmen muss (Bar.qml liest das)
    readonly property real maxDrop: root.expandedHeight + root.verticalMargin

    y: verticalMargin / 2
    width: Math.max(content.implicitWidth + root.padding * 2, root.minWidth)
    height: root.expanded ? root.expandedHeight : root.collapsedHeight

    Morph on height {}

    // Aufklappen nach kurzem Verweilen – ohne die Verzoegerung springt die
    // Karte schon auf, wenn man nur auf dem Weg zum Systray drueberfaehrt.
    // Laeuft nur, solange der Zeiger auf der Karte steht und NICHT auf dem
    // Play-Knopf: wer nur kurz Pause druecken will, soll sich nicht das ganze
    // Menue aufziehen. Als Bedingung statt restart()-Aufrufen, damit der Timer
    // beim Wechsel auf den Knopf von selbst stehen bleibt.
    Timer {
        id: openTimer

        interval: 220
        running: pillHover.hovered && !playButton.hovered && !root.expanded
        onTriggered: root.expanded = true
    }

    // Zuklappen mit Nachlauf, sobald der Zeiger die Karte verlaesst
    Timer {
        id: closeTimer

        interval: 600
        onTriggered: root.expanded = false
    }

    // Den Visualiser (Cava) schaltet Bar.qml ein – die Notch zeigt die Pegel
    // auch, deshalb haengt das nicht mehr an dieser Karte allein.

    // Die abgelaufene Zeit muss gepollt werden (MPRIS schickt sie nicht von
    // selbst). Das schaltet Bar.qml zentral: diese Pille ODER das
    // Medien-Untermenue der Notch.

    Surface {
        id: pill
        anchors.fill: parent

        maxRadius: root.cardRadius
        borderWidth: root.borderWidth
        borderColor: root.borderColor
        // Eingeklappt der normale Theme-Grund, ausgeklappt der Ton des Covers
        // (und darueber dessen unscharfes Bild, siehe unten).
        baseColor: root.expanded ? root.cardColor : Colors.background

        Behavior on baseColor {
            ColorAnimation { duration: 400 }
        }

        // ---- Unscharfes Cover als Kartengrund ----
        // Nur im ausgeklappten Zustand. Das `clip` der Karte schneidet
        // rechteckig, deshalb bekommt der Effekt dieselbe Rundung als Maske –
        // sonst stuende das Bild in den Ecken ueber.
        Image {
            id: bgArt

            anchors.fill: parent
            source: Media.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Klein laden reicht: es wird ohnehin zerblurrt, und so kostet der
            // Effekt einen Bruchteil.
            sourceSize.width: 128
            sourceSize.height: 128
            visible: false
        }

        Item {
            id: bgMask

            anchors.fill: parent
            layer.enabled: true
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: pill.radius
                color: "black"
            }
        }

        MultiEffect {
            anchors.fill: parent

            source: bgArt
            // `autoPadding` wuerde den Effekt ueber die Karte hinauswachsen
            // lassen, damit der Blur ausfransen kann – hier unerwuenscht.
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 72
            // abdunkeln und entsaettigen, sonst ist kein Text mehr lesbar
            brightness: -0.55
            saturation: -0.35
            maskEnabled: true
            maskSource: bgMask

            opacity: root.expanded && bgArt.status === Image.Ready ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        // Schleier in der Cover-Farbe darueber: erst das macht aus dem noch
        // erkennbaren Bild einen ruhigen Grund, auf dem Text steht.
        Rectangle {
            anchors.fill: parent

            radius: pill.radius
            color: Colors.alpha(root.cardColor, 0.55)
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        // Solange der Zeiger auf der Karte steht, bleibt sie offen. Weil die
        // Karte beim Aufklappen unter dem Zeiger waechst, bleibt der Hover
        // auch nach einer Ziehgeste bestehen – eine Schonfrist wie beim
        // frueheren Popup-Fenster braucht es hier nicht.
        HoverHandler {
            id: pillHover

            onHoveredChanged: hovered ? closeTimer.stop() : closeTimer.restart()
        }

        // Nach unten ziehen klappt das Menue auf – dieselbe Geste, mit der die
        // Notch ihren Launcher aufzieht. `target: null`, es wird also nichts
        // verschoben; die Knoepfe behalten ihren Tap, weil ein TapHandler bei
        // Bewegung von selbst abbricht.
        DragHandler {
            id: openDrag

            target: null
            xAxis.enabled: false

            readonly property real threshold: 18

            onActiveChanged: if (!openDrag.active) openDrag.triggered = false

            property bool triggered: false

            onTranslationChanged: {
                if (!openDrag.active || openDrag.triggered)
                    return;
                if (openDrag.activeTranslation.y > openDrag.threshold) {
                    openDrag.triggered = true;
                    root.expanded = true;
                }
            }
        }

        // Mausrad auf der Pille schaltet die Audioquelle durch
        WheelHandler {
            parent: pill
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            property real acc: 0

            onWheel: event => {
                acc += event.angleDelta.y;
                if (Math.abs(acc) < 120)
                    return;
                Media.cycle(acc > 0 ? -1 : 1);
                acc = 0;
            }
        }

        Item {
            id: content

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: root.padding
                rightMargin: root.padding
            }
            height: root.collapsedHeight

            implicitWidth: row.implicitWidth

            // Aufgeklappt gehoert die Karte dem Panel: die Leisten-Zeile
            // schiebt sich nach links raus und blendet aus, statt ueber dem
            // Menue stehen zu bleiben.
            opacity: root.expanded ? 0 : 1
            visible: opacity > 0

            transform: Translate {
                x: root.expanded ? -24 : 0

                Behavior on x {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            // Fuellt das obere Band; jedes Element darin zentriert sich
            // ueber `Layout.alignment` selbst.
            RowLayout {
                id: row

                anchors.fill: parent
                spacing: 6

                // ---- Cover ----
                Rectangle {
                    Layout.preferredWidth: root.artSize
                    Layout.preferredHeight: root.artSize
                    Layout.alignment: Qt.AlignVCenter

                    radius: 4
                    color: Colors.surfaceContainer
                    clip: true

                    Image {
                        id: art

                        anchors.fill: parent
                        source: Media.art
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Cover sind gross (Spotify liefert 640px) – klein
                        // dekodieren spart Speicher und Skalierarbeit.
                        sourceSize.width: root.artSize * 2
                        sourceSize.height: root.artSize * 2
                        visible: status === Image.Ready
                    }

                    // Platzhalter, solange es kein Cover gibt
                    Text {
                        anchors.centerIn: parent
                        visible: !art.visible

                        text: "music_note"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 12
                    }
                }

                // ---- Zeit ----
                Text {
                    font.family: Config.font
                    Layout.alignment: Qt.AlignVCenter
                    visible: Media.timeLabel !== ""

                    text: Media.timeLabel
                    color: Colors.fgSurfaceVariant
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }

                // ---- Visualiser ----
                // Gespiegelte Wellenform (modules/widgets/Visualizer.qml);
                // pausiert steht sie als ruhiger Bogen da
                Visualizer {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: root.artSize - 2
                    Layout.alignment: Qt.AlignVCenter

                    count: 5
                    barWidth: root.barWidth
                    spacing: root.barSpacing
                    active: Media.playing
                }

                // ---- Titel als Laufschrift ----
                // Feste Breite und `clip`: der Titel wird abgeschnitten statt
                // die Pille zu sprengen. Passt er nicht, wandert er endlos
                // durch – die zweite Kopie hinter der Luecke macht den
                // Uebergang nahtlos, sonst gaebe es einen sichtbaren Sprung.
                Item {
                    id: marquee

                    readonly property string label: Media.title
                    readonly property real gap: 26
                    readonly property bool scrolling: title.implicitWidth > marquee.width

                    Layout.preferredWidth: 116
                    Layout.preferredHeight: root.artSize
                    Layout.alignment: Qt.AlignVCenter
                    // Der Play-Knopf bringt selbst schon Rand mit – hier
                    // nochmal die vollen 6px Reihenabstand waere zu viel Luft.
                    Layout.rightMargin: -4

                    clip: true

                    Row {
                        id: strip

                        y: (marquee.height - height) / 2
                        spacing: marquee.gap

                        Text {
                            id: title
                            font.family: Config.font

                            text: marquee.label
                            color: Colors.fgBackground
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        Text {
                            // Nur noetig, solange gelaufen wird
                            text: marquee.scrolling ? marquee.label : ""
                            color: title.color
                            font: title.font
                        }
                    }

                    // Steht der Titel still, faengt er wieder links an
                    onScrollingChanged: if (!marquee.scrolling) strip.x = 0;
                    readonly property bool playing: Media.playing
                    onPlayingChanged: if (!marquee.playing) strip.x = 0;

                    SequentialAnimation {
                        // Pausiert steht der Titel: eine Endlos-Animation
                        // zwingt das Leistenfenster sonst auf Monitorrate
                        running: marquee.scrolling && marquee.visible && Media.playing
                        loops: Animation.Infinite

                        // Erst lesen lassen, dann losfahren
                        PauseAnimation {
                            duration: 1500
                        }

                        NumberAnimation {
                            target: strip
                            property: "x"
                            from: 0
                            to: -(title.implicitWidth + marquee.gap)
                            // konstantes Tempo statt fester Dauer, sonst rasen
                            // kurze Titel und lange schleichen
                            duration: (title.implicitWidth + marquee.gap) * 22
                            easing.type: Easing.Linear
                        }
                    }
                }

                // ---- Transport ----
                // Nur Play/Pause. Vor- und Zurueckspringen steht im
                // ausgeklappten Teil – in der Leiste waren es drei Knoepfe
                // zu viel fuer den Platz.
                MediaButton {
                    id: playButton

                    icon: Media.playing ? "pause" : "play_arrow"
                    size: root.iconSize + 3
                    active: Media.canToggle
                    onTriggered: Media.playPause()
                }
            }

        }

        // Der ausgeklappte Teil – sitzt in derselben Karte, direkt unter der
        // Reihe. `clip: true` der Pille schneidet ihn weg, solange sie flach
        // ist, deshalb braucht es kein eigenes Ein-/Ausblenden der Groesse.
        MediaPanel {
            id: panel

            topOffset: root.panelTop
            padding: root.padding
            tint: root.cardColor
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0

            // Der Inhalt faehrt beim Aufklappen von oben herein, statt einfach
            // aufzutauchen – zusammen mit der wachsenden Karte liest sich das
            // als eine Bewegung nach unten.
            transform: Translate {
                y: root.expanded ? 0 : -16

                Behavior on y {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }
    }
}
