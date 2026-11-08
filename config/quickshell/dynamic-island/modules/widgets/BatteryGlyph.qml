import QtQuick
import QtQuick.Shapes

import qs

// Liegende Batterie, gefuellt nach Ladestand – ein Symbol fuer Notch,
// Settings-Pille und Sperrbildschirm statt der groben Material-Stufen.
//
//   laden / am Kabel   Fuellung im Akzent, Blitz in der Batterie, Lichtschimmer
//   bis 20 %           Fuellung bernstein (Rot zum Gelb hin, passt zu jedem Schema)
//   unter 10 %         Fuellung und Rahmen rot
//
// Die Grenzen sind dieselben wie Power.low/critical; percent und charging
// sind eigene Properties, damit der Sperrbildschirm sie fuer Tests setzen kann.
//
// Rahmen, Fuellung und Pol sind Shape-Pfade (CurveRenderer): Rectangles mit
// 1,5-px-Rand landen auf halben Pixeln und wirken in der Notch-Groesse
// stufig, die Pfade werden sauber geglaettet.
Item {
    id: glyph

    property int percent: 0
    property bool charging: false
    // Grundfarbe fuer Rahmen und normale Fuellung
    property color fg: Colors.fgBackground
    property real bodyWidth: 20
    property real bodyHeight: 11
    // Ladeschimmer (aus fuer Stellen, die nur kurz zu sehen sind)
    property bool animate: true

    readonly property real level: Math.max(0, Math.min(100, glyph.percent)) / 100
    readonly property bool critical: !glyph.charging && glyph.percent < 10
    readonly property bool low: !glyph.charging && glyph.percent <= 20
    readonly property color fillColor: glyph.charging ? Colors.primary
                                     : glyph.critical ? Colors.error
                                     : glyph.low ? Colors.mix(Colors.error, "#ffb547", 0.55)
                                     : glyph.fg
    readonly property color frameColor: glyph.critical ? Colors.alpha(Colors.error, 0.8)
                                                       : Colors.alpha(glyph.fg, 0.5)

    readonly property real stroke: Math.max(1, glyph.bodyHeight * 0.13)
    readonly property real radius: glyph.bodyHeight * 0.34
    // Pol: Halbkreis rechts neben dem Rahmen
    readonly property real nubHeight: glyph.bodyHeight * 0.42
    readonly property real nubGap: 1

    implicitWidth: glyph.bodyWidth + glyph.nubGap + glyph.nubHeight / 2
    implicitHeight: glyph.bodyHeight

    // Rahmen und Pol
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true

        ShapePath {
            strokeWidth: glyph.stroke
            strokeColor: glyph.frameColor
            fillColor: "transparent"

            PathRectangle {
                x: glyph.stroke / 2
                y: glyph.stroke / 2
                width: glyph.bodyWidth - glyph.stroke
                height: glyph.bodyHeight - glyph.stroke
                radius: glyph.radius - glyph.stroke / 2
            }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: glyph.frameColor

            PathSvg {
                readonly property real x0: glyph.bodyWidth + glyph.nubGap
                readonly property real r: glyph.nubHeight / 2
                readonly property real cy: glyph.bodyHeight / 2
                path: `M ${x0} ${cy - r} A ${r} ${r} 0 0 1 ${x0} ${cy + r} Z`
            }
        }
    }

    Item {
        id: body

        width: glyph.bodyWidth
        height: glyph.bodyHeight

        // Fuellung buendig an der Innenkante des Rahmens; links rund wie der
        // Rahmen, rechts gerade, nie ganz weg (leer bleibt als Akku lesbar).
        // Ein Kasten mit Clip schneidet die volle, abgerundete Fuellung ab.
        Item {
            id: fill

            readonly property real inset: glyph.stroke
            readonly property real full: body.width - 2 * fill.inset

            x: fill.inset
            y: fill.inset
            width: Math.max(1.5, fill.full * glyph.level)
            height: body.height - 2 * fill.inset
            clip: true

            Behavior on width {
                NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
            }

            Shape {
                width: fill.full
                height: fill.height
                preferredRendererType: Shape.CurveRenderer
                antialiasing: true

                ShapePath {
                    strokeWidth: -1
                    fillColor: glyph.fillColor

                    PathRectangle {
                        width: fill.full
                        height: fill.height
                        radius: Math.max(0, glyph.radius - fill.inset)
                    }
                }
            }
            // Laden: ein Lichtschimmer wandert durch die Fuellung, dann Pause
            // (zwischen den Durchlaeufen zeichnet die Notch nichts neu)
            Item {
                anchors.fill: parent
                visible: glyph.charging

                Rectangle {
                    id: shimmer

                    width: Math.max(6, body.width * 0.45)
                    height: parent.height
                    x: -width
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                        GradientStop { position: 1; color: "transparent" }
                    }

                    SequentialAnimation on x {
                        running: glyph.charging && glyph.visible && glyph.animate
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: -shimmer.width
                            to: fill.width
                            duration: Appearance.morphDuration * 3
                            easing.type: Easing.InOutSine
                        }
                        PauseAnimation { duration: Appearance.morphDuration * 7 }
                    }
                }
            }
        }

        // Blitz zweifarbig, an der Fuellkante geteilt: ueber der Fuellung
        // ausgestanzt (Hintergrundfarbe), ueber der Leere in Rahmenfarbe.
        // Eine Kontur um den ganzen Blitz war bei 11 px nur noch Brei.
        Repeater {
            model: glyph.charging ? [true, false] : []

            Item {
                id: half

                required property bool modelData   // true = Teil ueber der Fuellung
                readonly property real edge: fill.x + fill.width

                x: half.modelData ? 0 : half.edge
                width: half.modelData ? half.edge : body.width - half.edge
                height: body.height
                clip: true

                Text {
                    x: -half.x
                    width: body.width
                    height: body.height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "bolt"
                    color: half.modelData ? Colors.background : glyph.fg
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: body.height
                    font.variableAxes: ({ FILL: 1 })
                }
            }
        }
    }
}
