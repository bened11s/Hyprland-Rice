pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs
import qs.modules.services.audio
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.services.media

// "Jetzt laeuft" auf dem Desktop: Cover, Titel, Interpret und (optional) eine
// duenne Fortschrittslinie mit Zeit – frei auf dem Wallpaper, ohne Karte,
// in der Sprache der Notch (Inter Display fuer den Titel, Interpret als kleine
// Versalien-Kopfzeile mit Akzentpunkt). Stile:
//
//   zeile   kleines, abgerundetes Cover links, rechts Kopfzeile/Titel/Linie
//   cover   grosses Cover, darunter Kopfzeile/Titel/Linie
//   vinyl   Schallplatte mit dem Cover als Label, rechts die Texte; dreht
//           sich nur waehrend der Wiedergabe (Timer mit `fps`, keine
//           RotationAnimation – die liefe mit der Monitorrate)
//
// Akzent: `tint` nimmt die Hauptfarbe des Covers (Media.artColor, zum Lesen
// etwas zur Textfarbe hin aufgehellt), sonst den Akzent des Hosts.
//
// Lesbarkeit: Kopfzeile + Titel liegen in einer Layer-Textur mit weichem
// Schatten (MultiEffect) – die aendert sich nur beim Titelwechsel. Alles,
// was laufend tickt (Fortschritt, Zeit, drehende Scheibe), liegt bewusst
// AUSSERHALB dieser Textur: Zeit mit Text.Raised, Cover/Scheibe mit einem
// RectangularShadow darunter (kein Layer ueber dem drehenden Teil).
//
// Position wird nur gepollt, solange die Linie sichtbar ist und etwas laeuft
// (Media.positionDemand). Bei active: false steht alles still.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property int fps: 30

    readonly property string style: {
        const s = root.opts.style ?? "zeile";
        return ["zeile", "cover", "vinyl"].includes(s) ? s : "zeile";
    }
    readonly property bool showProgress: root.opts.progress ?? true
    readonly property bool useTint: root.opts.tint ?? true
    readonly property bool idleShown: root.opts.idle === "ruhig"

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font

    // Gibt es einen Titel? (pausiert zaehlt – nur "nichts da" ist leer)
    readonly property bool hasMusic: Media.available && Media.title !== ""
    readonly property bool placeholder: !root.hasMusic
    readonly property bool shown: root.hasMusic || root.editing || root.idleShown
    readonly property bool live: root.active && root.visible && root.hasMusic

    // Akzent: Coverfarbe, zur Textfarbe hin aufgehellt, damit sie auf dunklem
    // Bild nicht absaeuft; ohne bekannte Farbe (oder ohne Musik) der Host-Akzent
    readonly property color tint: root.useTint && root.hasMusic && Media.artColor.a > 0
        ? Colors.mix(Media.artColor, root.color, 0.35)
        : root.accent

    // Platzhalter (idle "ruhig" / Bearbeiten): nur gedimmt "Keine Musik",
    // die Kopfzeile (Interpret) faellt weg
    readonly property string titleText: root.placeholder ? I18n.tr("Keine Musik") : Media.title
    readonly property string artistText: root.placeholder ? "" : Media.artist

    // Groessen in Grundeinheiten
    readonly property real smallArt: Math.round(root.unit * 4.6)
    readonly property real bigArt: Math.round(root.unit * 11)
    readonly property real discSize: Math.round(root.unit * 8)
    readonly property real textWidth: Math.round(root.unit * (root.style === "cover" ? 11 : root.style === "vinyl" ? 14 : 16.4))
    readonly property real artRadius: Math.round(root.unit * 0.6)

    implicitWidth: loader.item?.implicitWidth ?? root.unit * 22
    implicitHeight: loader.item?.implicitHeight ?? root.unit * 7

    opacity: root.shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    DemandRequest {
        demand: Media.positionDemand
        active: root.live && root.showProgress && Media.playing
    }

    // ---- Titelwechsel: einmal kurz einblenden ----
    // reveal 0 -> 1: Texte ruecken ein Stueck hoch und werden sichtbar, das
    // Cover dippt kurz. Laeuft nur, wenn das Widget wirklich zu sehen ist.
    property real reveal: 1
    readonly property string trackKey: Media.title + "\n" + Media.artist

    onTrackKeyChanged: {
        if (!root.live)
            return;
        revealAnim.restart();
    }

    NumberAnimation {
        id: revealAnim

        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: Appearance.morphDuration
        easing.type: Easing.OutCubic
    }

    Loader {
        id: loader

        sourceComponent: root.style === "cover" ? coverStyle
                       : root.style === "vinyl" ? vinylStyle
                       : lineStyle
    }

    // =====================================================================
    // Bausteine
    // =====================================================================

    // Kleine Versalien-Zeile mit Akzentpunkt: der Interpret. Bleibt immer im
    // Layout (ohne Interpret nur der Punkt aus): ein `visible`-Wechsel in
    // der unsichtbaren Layer-Column kaeme beim Positioner nicht mehr an.
    component Caption: Row {
        id: cap

        property real px: root.unit * 0.8

        spacing: cap.px * 0.6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: cap.px * 0.45
            height: width
            radius: width / 2
            color: root.tint
            opacity: root.artistText !== "" ? 1 : 0
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, cap.width - cap.spacing - cap.px * 0.45)
            text: root.artistText
            color: Colors.alpha(root.color, 0.72)
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // Kopfzeile + Titel in einer Schatten-Textur (aendert sich nur beim
    // Titelwechsel). Der Titelwechsel-Effekt greift an der Huelle, nicht am
    // Inhalt – so bleibt die Textur unangetastet.
    component TextBlock: Item {
        id: block

        property real titlePx: root.unit * 1.6
        property int maxLines: 1

        width: root.textWidth
        implicitWidth: root.textWidth
        implicitHeight: textContent.implicitHeight

        opacity: root.reveal
        transform: Translate { y: (1 - root.reveal) * root.unit * 0.4 }

        Column {
            id: textContent

            width: block.width
            spacing: root.unit * 0.35
            layer.enabled: true
            visible: false

            Caption {
                width: parent.width
                visible: root.artistText !== ""
                px: root.unit * 0.8
            }

            Text {
                width: parent.width
                text: root.titleText
                color: root.color
                opacity: root.placeholder ? 0.55 : 1
                font.family: root.display
                font.pixelSize: block.titlePx
                font.weight: Font.DemiBold
                font.letterSpacing: -block.titlePx * 0.02
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: block.maxLines
            }
        }

        MultiEffect {
            source: textContent
            anchors.fill: textContent
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.45
            shadowBlur: 0.8
            shadowVerticalOffset: Math.round(root.unit * 0.12)
            blurMax: 32
            autoPaddingEnabled: true
        }
    }

    // Duenne Fortschrittslinie, rechts die Zeit. Fuellung auf ganze Pixel
    // gerundet: Subpixel-Aenderungen zeichnen nicht neu. Ohne Laenge
    // (Browser bei YouTube) bleibt die Linie leer und nur die Position steht.
    component ProgressLine: Item {
        id: prog

        property real px: root.unit * 0.72

        readonly property real lineH: Math.max(2, Math.round(root.unit * 0.14))
        readonly property real trackW: Math.max(0, prog.width - timeLabel.width - root.unit * 0.6)

        visible: root.showProgress && !root.placeholder
        width: root.textWidth
        implicitWidth: root.textWidth
        implicitHeight: Math.max(prog.lineH, timeLabel.implicitHeight)

        Rectangle {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: prog.trackW
            height: prog.lineH
            radius: height / 2
            color: Colors.alpha(root.color, 0.18)
        }

        Rectangle {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(prog.trackW * Media.progress)
            height: prog.lineH
            radius: height / 2
            color: root.tint
        }

        Text {
            id: timeLabel

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Media.timeLabel
            color: Colors.alpha(root.color, 0.72)
            font.family: Config.font
            font.pixelSize: prog.px
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
            style: Text.Raised
            styleColor: Colors.alpha("#000000", 0.4)
        }
    }

    // Abgerundetes Cover mit weichem Schatten darunter; ohne Bild eine
    // zurueckhaltende Flaeche mit Note. Beim Titelwechsel kurz gedippt.
    component Cover: Item {
        id: art

        property real size: root.smallArt
        property real radius: root.artRadius

        readonly property bool ready: cover.status === Image.Ready

        width: art.size
        height: art.size
        implicitWidth: art.size
        implicitHeight: art.size

        RectangularShadow {
            visible: art.ready
            anchors.fill: parent
            radius: art.radius
            offset.y: root.unit * 0.2
            blur: root.unit * 1.2
            spread: 0
            color: Colors.alpha("#000000", 0.45)
        }

        Rectangle {
            anchors.fill: parent
            radius: art.radius
            color: Colors.alpha(root.color, 0.08)
            border.width: 1
            border.color: Colors.alpha(root.color, 0.14)
            visible: !art.ready
        }

        Text {
            anchors.centerIn: parent
            visible: !art.ready
            text: "music_note"
            color: Colors.alpha(root.color, 0.5)
            font.family: "Material Symbols Outlined"
            font.pixelSize: art.size * 0.4
        }

        Image {
            id: cover

            anchors.fill: parent
            source: root.placeholder ? "" : Media.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: Math.round(art.size * 2)
            sourceSize.height: Math.round(art.size * 2)
            visible: false
        }

        Item {
            id: coverMask

            anchors.fill: parent
            layer.enabled: true
            layer.textureSize: Qt.size(art.size * 2, art.size * 2)
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: art.radius
                color: "black"
            }
        }

        MultiEffect {
            anchors.fill: parent
            visible: art.ready
            opacity: 0.5 + 0.5 * root.reveal
            source: cover
            maskEnabled: true
            maskSource: coverMask
        }

        // Feine helle Kante, damit das Cover auf dunklem Bild nicht verschwimmt
        Rectangle {
            anchors.fill: parent
            visible: art.ready
            radius: art.radius
            color: "transparent"
            border.width: 1
            border.color: Colors.alpha("#ffffff", 0.14)
        }
    }

    // Schallplatte: fast schwarze Scheibe mit feinen Rillen, das Cover als
    // rundes Label, Mittelloch. Die Scheibe ist EINE Layer-Textur – pro
    // Tick dreht sich nur die Textur, nichts wird neu gerastert. Glanz und
    // Schatten liegen ausserhalb und drehen nicht mit.
    component Vinyl: Item {
        id: vinyl

        property real size: root.discSize
        property real rpm: 9
        property real angle: 0

        readonly property real labelSize: Math.round(vinyl.size * 0.56)
        readonly property bool spinning: root.live && Media.playing && root.style === "vinyl"
        readonly property bool ready: label.status === Image.Ready

        width: vinyl.size
        height: vinyl.size
        implicitWidth: vinyl.size
        implicitHeight: vinyl.size

        // Weiterdrehen nach vergangener Zeit, nicht um feste Schritte – so
        // ist die Drehzahl gleich, egal welcher Takt gerade schiebt
        property real lastStep: 0

        function step(): void {
            const now = Date.now();
            const dt = vinyl.lastStep > 0 ? Math.min(200, now - vinyl.lastStep) : 1000 / Math.max(1, root.fps);
            vinyl.lastStep = now;
            vinyl.angle = (vinyl.angle + 360 * vinyl.rpm / 60 * dt / 1000) % 360;
        }

        onSpinningChanged: vinyl.lastStep = 0

        // Laeuft cava (Visualizer daneben), im selben Takt mitdrehen: zwei
        // freie 30-Hz-Takte lagen versetzt und liessen das Fenster bis zu 60x/s
        // zeichnen. Der Timer springt nur ein, wenn keine Frames kommen (Stille
        // – cava ueberspringt gleiche Frames – oder Szene ohne Visualizer).
        Connections {
            target: vinyl.spinning && Cava.enabled ? Cava : null

            function onValuesChanged(): void {
                vinyl.step();
                spinTimer.restart();
            }
        }

        Timer {
            id: spinTimer

            running: vinyl.spinning
            interval: Math.round(1000 / Math.max(1, root.fps) * (Cava.enabled ? 1.5 : 1))
            repeat: true
            onTriggered: vinyl.step()
        }

        // Schatten unter der Scheibe (statisch, kein Layer)
        RectangularShadow {
            anchors.fill: parent
            radius: width / 2
            offset.y: root.unit * 0.25
            blur: root.unit * 1.4
            spread: 0
            color: Colors.alpha("#000000", 0.5)
        }

        Item {
            id: disc

            anchors.fill: parent
            rotation: vinyl.angle
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(vinyl.size * 2, vinyl.size * 2)

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#0b0b0d"
            }

            // Rillen: wenige duenne Ringe mit sehr geringer Deckung, nach
            // innen etwas dichter
            Repeater {
                model: 9

                delegate: Rectangle {
                    id: groove

                    required property int index

                    readonly property real t: groove.index / 8

                    anchors.centerIn: parent
                    width: vinyl.labelSize + 6 + (vinyl.size - vinyl.labelSize - 10) * groove.t
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.alpha("#ffffff", 0.035 + 0.02 * (1 - groove.t))
                }
            }

            // Aussenkante
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Colors.alpha("#ffffff", 0.14)
            }

            // Label: das Cover, rund maskiert
            Rectangle {
                anchors.centerIn: parent
                width: vinyl.labelSize
                height: vinyl.labelSize
                radius: width / 2
                color: "#1a1a1e"

                Image {
                    id: label

                    anchors.fill: parent
                    source: root.placeholder ? "" : Media.art
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.round(vinyl.labelSize * 2)
                    sourceSize.height: Math.round(vinyl.labelSize * 2)
                    visible: false
                }

                Item {
                    id: labelMask

                    anchors.fill: parent
                    layer.enabled: true
                    layer.textureSize: Qt.size(vinyl.labelSize * 2, vinyl.labelSize * 2)
                    visible: false

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                    }
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: vinyl.ready
                    source: label
                    maskEnabled: true
                    maskSource: labelMask
                }

                Text {
                    anchors.centerIn: parent
                    visible: !vinyl.ready
                    text: "music_note"
                    color: Colors.alpha("#ffffff", 0.45)
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: Math.max(14, vinyl.labelSize * 0.3)
                }

                // Feine dunkle Kante zwischen Label und Rille
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.alpha("#000000", 0.5)
                }
            }

            // Mittelloch
            Rectangle {
                anchors.centerIn: parent
                width: Math.max(5, Math.round(vinyl.size * 0.055))
                height: width
                radius: width / 2
                color: "#0b0b0d"
                border.width: 1
                border.color: Colors.alpha("#000000", 0.7)
            }
        }

        // Glanz: schraeger Lichtstreifen, statisch ueber den Rillen
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            rotation: -35
            opacity: 0.5 + 0.5 * root.reveal
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Colors.alpha("#ffffff", 0.0) }
                GradientStop { position: 0.18; color: Colors.alpha("#ffffff", 0.13) }
                GradientStop { position: 0.30; color: Colors.alpha("#ffffff", 0.0) }
                GradientStop { position: 0.70; color: Colors.alpha("#ffffff", 0.0) }
                GradientStop { position: 0.82; color: Colors.alpha("#ffffff", 0.06) }
                GradientStop { position: 1.0;  color: Colors.alpha("#ffffff", 0.0) }
            }
        }
    }

    // =====================================================================
    // Stile
    // =====================================================================

    // zeile: Cover links, Texte rechts, Linie darunter
    Component {
        id: lineStyle

        Row {
            spacing: root.unit * 1.0

            Cover {
                anchors.verticalCenter: parent.verticalCenter
                size: root.smallArt
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.unit * 0.55

                TextBlock {
                    titlePx: root.unit * 1.6
                }

                ProgressLine {}
            }
        }
    }

    // cover: grosses Cover, Texte darunter
    Component {
        id: coverStyle

        Column {
            spacing: root.unit * 0.8

            Cover {
                size: root.bigArt
                radius: Math.round(root.unit * 0.8)
            }

            Column {
                spacing: root.unit * 0.55

                TextBlock {
                    titlePx: root.unit * 1.4
                    maxLines: 2
                }

                ProgressLine {}
            }
        }
    }

    // vinyl: Scheibe links, Texte rechts
    Component {
        id: vinylStyle

        Row {
            spacing: root.unit * 1.2

            Vinyl {
                anchors.verticalCenter: parent.verticalCenter
                size: root.discSize
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.unit * 0.55

                TextBlock {
                    titlePx: root.unit * 1.6
                }

                ProgressLine {}
            }
        }
    }
}
