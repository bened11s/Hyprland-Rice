pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import qs

// Die Flaeche, aus der alle Pillen und Karten der Leiste bestehen: Notch,
// Workspace-Selektor, Tray, Settings, Medien, Benachrichtigungen, System.
//
// Ein Item mit zwei Schichten:
//   1. ein weicher Schatten darunter (MultiEffect auf einer schwarzen Kopie
//      der Form – der Schatten darf ueber die Flaeche hinausragen, deshalb
//      liegt er NICHT in der Karte, die ja clippt)
//   2. die Karte selbst: Rundung (flach = Pille, hoch = Karte), Rand und ein
//      leichter Verlauf von oben nach unten
//
// Kinder landen in der Karte (default property) – `parent` ist fuer sie also
// die Karte, nicht dieses Item. Beide sind aber deckungsgleich.
//
//     Surface {
//         anchors.fill: parent
//         baseColor: Colors.background   // Grundton (Default)
//         clipContent: false             // wenn etwas herausragen soll
//         ...
//     }
Item {
    id: surface

    default property alias content: card.data

    // Grundton; der Verlauf hellt ihn oben leicht auf
    property color baseColor: Colors.background
    property real maxRadius: Appearance.radius
    property real borderWidth: Appearance.borderWidth
    property color borderColor: Appearance.borderColor
    property bool clipContent: true
    // Verlauf von oben nach unten (0 = flach). Die angedockte Notch nimmt 0,
    // damit ihre Schultern nahtlos dieselbe Farbe haben.
    property real lift: Appearance.lift
    // Im Notch-Layout liegen die Pillen IN der schwarzen Notch (Hub). Dort
    // wirkt ein eigener Schatten wie eine zweite Ebene – sie werden zu
    // flachen Chips. `docked` ist die Notch selbst und davon ausgenommen.
    readonly property bool nested: Appearance.notchLayout && !surface.docked
    property bool shadow: Appearance.shadow && !surface.nested
    // Deckkraft des Schattens (0..1), damit er weich kommen und gehen kann
    property real shadowStrength: 1
    // Angedockt an der Bildschirmkante: oben eckig, nur unten gerundet
    // (Notch-Layout). Der Schatten folgt der Form.
    property bool docked: false
    // Angedockt an der rechten Kante (OSD): rechts eckig, links gerundet, und
    // oben wie unten ein nach innen gewoelbtes "Ohr", mit dem die Karte aus
    // der Bildschirmkante herauswaechst (Reverse-Rundung wie bei einer Notch).
    property bool dockedRight: false
    property real earRadius: Appearance.radius
    // Angedockt wuerde der Rechteck-Rand auch die Seite an der
    // Bildschirmkante nachzeichnen und quer ueber die Ansaetze von Ohren und
    // Schultern laufen – dort stand er als harte Kante. Darum zeichnet dann
    // eine Kontur nur die freien Seiten (beim OSD samt Ohren).
    readonly property bool outlined: surface.docked || surface.dockedRight
    // docked: Hoehe der Schultern (NotchShoulder, ausserhalb der Karte). Ihre
    // Kurve zeichnen sie selbst, die Kontur der Seiten beginnt erst darunter.
    property real shoulder: 0

    // Die tatsaechliche Rundung – fuer Masken und Vignetten, die ihr folgen
    readonly property alias radius: card.radius
    readonly property alias card: card

    // ---- Schatten ----
    Item {
        id: shadowShape

        anchors.fill: card
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: card.radius
            topLeftRadius: surface.docked ? 0 : card.radius
            topRightRadius: surface.docked || surface.dockedRight ? 0 : card.radius
            bottomRightRadius: surface.dockedRight ? 0 : card.radius
            color: "black"
        }
    }

    MultiEffect {
        anchors.fill: card
        source: shadowShape
        visible: surface.shadow && surface.shadowStrength > 0
        opacity: surface.shadowStrength

        shadowEnabled: true
        shadowColor: Appearance.shadowColor
        shadowBlur: Appearance.shadowBlur
        blurMax: 32
        shadowOpacity: Appearance.shadowOpacity
        shadowVerticalOffset: Appearance.shadowOffset
        // Der Effekt darf ueber die Form hinauswachsen – genau das ist der
        // Schatten. Die schwarze Form selbst liegt exakt unter der Karte.
        autoPaddingEnabled: true
    }

    // ---- Ohren beim Andocken rechts ----
    // Ein Quadrat an der Kante, aus dem ein Viertelkreis ausgespart ist:
    // uebrig bleibt die Hohlkehle zwischen Kartenecke und Bildschirmkante.
    Shape {
        id: earTop

        visible: surface.dockedRight
        anchors {
            right: card.right
            bottom: card.top
        }
        width: surface.earRadius
        height: surface.earRadius
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Colors.shade(surface.baseColor, surface.lift)

            startX: earTop.width
            startY: 0
            PathLine { x: earTop.width; y: earTop.height }   // die Kante hinunter zur Kartenecke
            PathLine { x: 0; y: earTop.height }              // auf der Kartenoberkante nach links
            PathQuad {                                       // zurueck zur Kante, Kurve zur Ecke hin
                x: earTop.width                              // (dieselbe Kurve wie NotchShoulder)
                y: 0
                controlX: earTop.width
                controlY: earTop.height
            }
        }
    }

    Shape {
        id: earBottom

        visible: surface.dockedRight
        anchors {
            right: card.right
            top: card.bottom
        }
        width: surface.earRadius
        height: surface.earRadius
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: surface.baseColor

            startX: earBottom.width
            startY: earBottom.height
            PathLine { x: earBottom.width; y: 0 }             // die Kante hinauf zur Kartenecke
            PathLine { x: 0; y: 0 }                           // auf der Kartenunterkante nach links
            PathQuad {
                x: earBottom.width
                y: earBottom.height
                controlX: earBottom.width
                controlY: 0
            }
        }
    }

    // ---- Karte ----
    Rectangle {
        id: card

        anchors.fill: parent

        // Pille, solange sie flach ist; ab 2 x maxRadius Hoehe eine Karte.
        // Als Formel, damit die Rundung waehrend einer Animation mitwandert.
        radius: Math.min(height / 2, surface.maxRadius)
        topLeftRadius: surface.docked ? 0 : radius
        topRightRadius: surface.docked || surface.dockedRight ? 0 : radius
        bottomRightRadius: surface.dockedRight ? 0 : radius
        border.width: surface.outlined ? 0 : surface.borderWidth
        border.color: surface.borderColor
        clip: surface.clipContent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Colors.shade(surface.baseColor, surface.lift)
            }
            GradientStop {
                position: 1
                color: surface.baseColor
            }
        }
    }
    // ---- Kontur beim Andocken ----
    // Ueber der Karte, damit sie wie der Rand die Kante sauber schliesst. Die
    // Linie liegt um die halbe Breite nach innen versetzt, genau wie ein
    // Rectangle-Rand.
    Shape {
        id: outlineTop

        readonly property real half: surface.borderWidth / 2
        readonly property real corner: card.radius
        readonly property real sideStart: Math.min(surface.shoulder, height - corner)

        anchors.fill: card
        visible: surface.docked && surface.borderWidth > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: surface.borderWidth
            strokeColor: surface.borderColor
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            // linke Seite ab der Schulter hinunter, unten herum, rechts hinauf
            startX: outlineTop.half
            startY: outlineTop.sideStart
            PathLine { x: outlineTop.half; y: outlineTop.height - outlineTop.corner }
            PathArc {
                x: outlineTop.corner
                y: outlineTop.height - outlineTop.half
                radiusX: Math.max(0, outlineTop.corner - outlineTop.half)
                radiusY: radiusX
                direction: PathArc.Counterclockwise
            }
            PathLine { x: outlineTop.width - outlineTop.corner; y: outlineTop.height - outlineTop.half }
            PathArc {
                x: outlineTop.width - outlineTop.half
                y: outlineTop.height - outlineTop.corner
                radiusX: Math.max(0, outlineTop.corner - outlineTop.half)
                radiusY: radiusX
                direction: PathArc.Counterclockwise
            }
            PathLine { x: outlineTop.width - outlineTop.half; y: outlineTop.sideStart }
        }
    }

    Shape {
        id: outlineRight

        readonly property real half: surface.borderWidth / 2
        readonly property real corner: card.radius
        readonly property real ear: surface.earRadius

        anchors.fill: card
        visible: surface.dockedRight && surface.borderWidth > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: surface.borderWidth
            strokeColor: surface.borderColor
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            // von der Kante das obere Ohr hinunter, links um die Karte, das
            // untere Ohr zurueck an die Kante
            startX: outlineRight.width
            startY: -outlineRight.ear
            PathQuad {
                x: outlineRight.width - outlineRight.ear
                y: outlineRight.half
                controlX: outlineRight.width
                controlY: outlineRight.half
            }
            PathLine { x: outlineRight.corner; y: outlineRight.half }
            PathArc {
                x: outlineRight.half
                y: outlineRight.corner
                radiusX: Math.max(0, outlineRight.corner - outlineRight.half)
                radiusY: radiusX
                direction: PathArc.Counterclockwise
            }
            PathLine { x: outlineRight.half; y: outlineRight.height - outlineRight.corner }
            PathArc {
                x: outlineRight.corner
                y: outlineRight.height - outlineRight.half
                radiusX: Math.max(0, outlineRight.corner - outlineRight.half)
                radiusY: radiusX
                direction: PathArc.Counterclockwise
            }
            PathLine { x: outlineRight.width - outlineRight.ear; y: outlineRight.height - outlineRight.half }
            PathQuad {
                x: outlineRight.width
                y: outlineRight.height + outlineRight.ear
                controlX: outlineRight.width
                controlY: outlineRight.height - outlineRight.half
            }
        }
    }
}
