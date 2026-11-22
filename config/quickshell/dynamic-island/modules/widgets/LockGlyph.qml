pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs
import qs.modules.services.config

// Vorhaengeschloss, selbst gezeichnet: Koerper als runde Platte, Buegel
// als Bogen. `open` hebt den Buegel heraus und kippt ihn – mit Feder,
// wie das Schloss beim Entsperren aufspringt.
Item {
    id: glyph

    property real size: 16
    property color color: "white"
    property bool open: false

    readonly property real stroke: Math.max(1.6, glyph.size * 0.16)
    readonly property real legX: glyph.size * 0.5 - glyph.size * 0.36 + glyph.stroke / 2

    width: glyph.size
    height: glyph.size * 1.25

    Behavior on color { ColorAnimation { duration: Appearance.fadeDuration } }

    Shape {
        id: shackle

        width: glyph.size
        height: glyph.size * 0.75
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Rotation {
                origin.x: glyph.size - glyph.legX
                origin.y: glyph.size * 0.62
                angle: glyph.open ? 22 : 0

                Behavior on angle {
                    NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }
            },
            Translate {
                y: glyph.open ? -glyph.size * 0.2 : 0

                Behavior on y {
                    NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }
            }
        ]

        ShapePath {
            strokeWidth: glyph.stroke
            strokeColor: glyph.color
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            startX: glyph.legX
            startY: glyph.size * 0.66
            PathLine { x: glyph.legX; y: glyph.size * 0.42 }
            PathArc {
                x: glyph.size - glyph.legX
                y: glyph.size * 0.42
                radiusX: glyph.size * 0.5 - glyph.legX
                radiusY: glyph.size * 0.5 - glyph.legX
            }
            PathLine { x: glyph.size - glyph.legX; y: glyph.size * 0.66 }
        }
    }

    Rectangle {
        y: glyph.size * 0.58
        width: glyph.size
        height: glyph.size * 0.67
        radius: glyph.size * 0.2
        color: glyph.color
    }
}
