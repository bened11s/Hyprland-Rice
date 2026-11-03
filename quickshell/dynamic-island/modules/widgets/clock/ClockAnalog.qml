import QtQuick
import QtQuick.Shapes

import qs
import qs.modules.services.config

// Analoge Uhr in der Material-You-"Cookie"-Form: ein Kreis mit weichen
// Wellen am Rand, gefuellt in der halbtransparenten Textfarbe, darauf
// Stunden- und Minutenzeiger als abgerundete Balken (Minuten in Akzent).
//
// Der Durchmesser ist size * 1.3 – so ist das Blatt in der Notch etwa so hoch wie
// das digitale Label. Die Zeiger stehen ohne Animation (die Zeit kommt
// minutengenau von aussen); die Wellenkontur wird nur bei Groessenwechsel
// neu gerechnet.
Item {
    id: root

    property date date
    property real size: 16
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property bool use12h: Config.appearance.clock === "12h"
    property string fontFamily: Config.font
    property int weight: Font.Bold

    // Wellen am Rand und ihre Tiefe (Anteil des Radius)
    property int waves: 10
    property real waveDepth: 0.07

    readonly property real diameter: Math.round(root.size * 1.3)
    readonly property real cx: root.diameter / 2
    readonly property real cy: root.diameter / 2
    // Grundradius: Wellenberge reichen genau bis zum Rand
    readonly property real radius: root.cx / (1 + root.waveDepth)

    // In der Notch (Radius ~10) sind die Zeiger relativ dicker und die
    // Fuellung kraeftiger, sonst bleibt nur ein grauer Fleck
    readonly property bool tiny: root.radius < 16

    readonly property int hour: root.date.getHours()
    readonly property int minute: root.date.getMinutes()

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    // Konturpunkte der Cookie-Form, r(t) = R * (1 + d * cos(n * t))
    readonly property var outline: {
        const pts = [];
        const n = Math.max(48, root.waves * 16);
        for (let i = 0; i <= n; i++) {
            const t = i / n * Math.PI * 2;
            const r = root.radius * (1 + root.waveDepth * Math.cos(root.waves * t));
            pts.push(Qt.point(root.cx + r * Math.cos(t), root.cy + r * Math.sin(t)));
        }
        return pts;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: Colors.alpha(root.color, root.tiny ? 0.28 : 0.2)
            strokeColor: "transparent"
            strokeWidth: 0

            PathPolyline {
                path: root.outline
            }
        }
    }

    // Vier zarte Markierungen (12, 3, 6, 9) – erst, wenn Platz dafuer ist
    Repeater {
        model: root.radius >= 28 ? 4 : 0

        Rectangle {
            id: tick

            required property int index
            readonly property real angle: tick.index * Math.PI / 2 - Math.PI / 2
            readonly property real dist: root.radius * 0.84

            width: Math.max(2, Math.round(root.radius * 0.07))
            height: width
            radius: width / 2
            x: root.cx + Math.cos(tick.angle) * tick.dist - width / 2
            y: root.cy + Math.sin(tick.angle) * tick.dist - height / 2
            color: root.color
            opacity: 0.45
        }
    }

    // Zeiger: abgerundeter Balken, der Drehpunkt sitzt in der Mitte der
    // unteren Rundung – die ragt um die halbe Breite ueber den Mittelpunkt
    // hinaus, damit die Zeiger dort sauber ineinander laufen
    component Hand: Rectangle {
        id: hand

        property real length: 10
        property real angle: 0

        x: root.cx - width / 2
        y: root.cy - hand.length
        height: hand.length + width / 2
        radius: width / 2
        antialiasing: true

        transform: Rotation {
            origin.x: hand.width / 2
            origin.y: hand.length
            angle: hand.angle
        }
    }

    Hand {
        width: root.tiny ? 3 : Math.max(3, Math.round(root.radius * 0.17))
        length: root.radius * (root.tiny ? 0.5 : 0.52)
        color: root.color
        angle: (root.hour % 12 + root.minute / 60) * 30
    }

    Hand {
        width: root.tiny ? 2 : Math.max(2, Math.round(root.radius * 0.12))
        length: root.radius * (root.tiny ? 0.82 : 0.8)
        color: root.accent
        angle: root.minute * 6
    }

    // Mittelpunkt
    Rectangle {
        width: root.tiny ? 3 : Math.max(3, Math.round(root.radius * 0.16))
        height: width
        radius: width / 2
        x: root.cx - width / 2
        y: root.cy - height / 2
        color: root.color
        antialiasing: true
    }
}
