import QtQuick
import QtQuick.Shapes

// Eine "Schulter" der angedockten Notch: die nach innen gewoelbte Ecke, mit
// der die Notch in die Bildschirmoberkante uebergeht – wie die Aussparung
// eines Laptop-Displays. Ohne sie sieht die Notch aus wie ein Tab, der an der
// Kante klebt; mit ihr wie ein Teil des Rahmens (saneAspect-Vorbild).
//
// Die Notch setzt links und rechts je eine davon AUSSERHALB ihrer Breite an
// (x = -size bzw. x = notch.width). So bleibt die Notch selbst ein Rechteck:
// Maske, Anker der Nachbarn und alle Innenmasse rechnen weiter mit ihr, und
// die Schultern bewegen sich beim Morphen nur mit, ohne neu tesselliert zu
// werden.
//
//     NotchShoulder { mirrored: false }   // links
//     NotchShoulder { mirrored: true }    // rechts
Shape {
    id: root

    property real size: 12
    property color color: "black"
    // false = linke Schulter (Kurve oeffnet nach links), true = rechte
    property bool mirrored: false
    // Kontur nur entlang der Kurve – setzt die Randlinie der Notch fort
    property real strokeWidth: 0
    property color strokeColor: "transparent"

    width: size
    height: size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: root.color

        // Linke Schulter: Oberkante -> Kante der Notch -> Kurve zurueck in die
        // obere linke Ecke, die sich zur Notch-Ecke (size, 0) hin woelbt.
        // Rechts dasselbe gespiegelt.
        startX: root.mirrored ? root.size : 0
        startY: 0

        PathLine {
            x: root.mirrored ? 0 : root.size
            y: 0
        }
        PathLine {
            x: root.mirrored ? 0 : root.size
            y: root.size
        }
        PathQuad {
            x: root.mirrored ? root.size : 0
            y: 0
            controlX: root.mirrored ? 0 : root.size
            controlY: 0
        }
    }

    // Kontur: nur die Kurve, von der Notch-Kante hoch zur Bildschirmkante
    ShapePath {
        strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
        strokeColor: root.strokeColor
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap

        // Endet genau auf der Kontur der Notch-Seite (Surface zeichnet sie
        // um die halbe Breite nach innen versetzt, also schon in der Notch)
        startX: root.mirrored ? -root.strokeWidth / 2 : root.size + root.strokeWidth / 2
        startY: root.size

        PathQuad {
            x: root.mirrored ? root.size : 0
            y: root.strokeWidth / 2
            controlX: root.mirrored ? -root.strokeWidth / 2 : root.size + root.strokeWidth / 2
            controlY: root.strokeWidth / 2
        }
    }
}
