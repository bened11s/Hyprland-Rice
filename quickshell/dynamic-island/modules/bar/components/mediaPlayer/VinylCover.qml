pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs

// Das Cover als Schallplatte (Config.media.cover == "vinyl"): fast schwarze
// Scheibe mit feinen Rillen, das Cover als rundes Label in der Mitte, ein
// kleines Mittelloch. Darueber liegt ein statischer Glanz, der nicht
// mitdreht – so wirkt die Scheibe beleuchtet statt gemalt.
//
// Drehung: KEINE RotationAnimation (die liesse das Fenster mit Monitorrate
// zeichnen), sondern ein Timer mit ~30 Bildern pro Sekunde, der den Winkel
// in Schritten weiterstellt – nur solange `spinning`. Pausiert bleibt die
// Scheibe stehen, wo sie ist. Die ganze Scheibe ist eine Ebene (layer), d.h.
// pro Schritt dreht sich eine einzige Textur, nichts wird neu gerastert.
Item {
    id: vinyl

    property real size: 120
    property color tint: Colors.background
    property string source: ""
    property int decode: 380
    property bool spinning: false
    // Umdrehungen pro Minute – echte 33 1/3 wirken in klein zu hektisch
    property real rpm: 9
    property real angle: 0

    readonly property real labelSize: Math.round(vinyl.size * 0.56)
    readonly property int fps: 30

    width: vinyl.size
    height: vinyl.size

    Timer {
        running: vinyl.spinning
        interval: Math.round(1000 / vinyl.fps)
        repeat: true
        onTriggered: vinyl.angle = (vinyl.angle + 360 * vinyl.rpm / 60 / vinyl.fps) % 360
    }

    // ---- Scheibe (dreht) ----
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

        // Rillen: ein paar duenne Ringe mit sehr geringer Deckung, nach innen
        // dichter – das reicht, dass das Auge "Platte" liest
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

        // Aussenkante leicht abgesetzt
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Colors.alpha("#ffffff", 0.12)
        }

        // ---- Label: das Cover, rund maskiert ----
        Rectangle {
            anchors.centerIn: parent
            width: vinyl.labelSize
            height: vinyl.labelSize
            radius: width / 2
            color: Colors.shade(vinyl.tint, 0.12)

            Image {
                id: cover

                anchors.fill: parent
                source: vinyl.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: vinyl.decode
                sourceSize.height: vinyl.decode
                visible: false
            }

            Item {
                id: coverMask

                anchors.fill: parent
                layer.enabled: true
                // Dieselbe Aufloesung wie die Scheiben-Ebene, sonst wird der
                // Labelrand beim Hochskalieren treppig
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
                font.pixelSize: Math.max(14, vinyl.labelSize * 0.3)
            }

            // Labelrand: feine dunkle Kante zwischen Bild und Rille
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
            color: Colors.shade(vinyl.tint, -0.02)
            border.width: 1
            border.color: Colors.alpha("#000000", 0.6)
        }
    }

    // ---- Glanz (statisch, dreht nicht mit) ----
    // Ein schraeger Lichtstreifen ueber die Rillen; als Kreis mit Verlauf
    // bleibt er beim Drehen des Rechtecks ein Kreis.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        rotation: -35
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
