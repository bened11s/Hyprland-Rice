pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs
import qs.modules.widgets

// Akku-Ring fuer die angedockte Notch (notch.batteryStyle "ring") – das
// Gegenstueck zum Ring der Insel (Audioslider als batteryRing), aber fuer
// ihre Form: oben gerade am Bildschirmrand, unten abgerundet.
//
// Der Ring folgt dem Umriss der Notch knapp innerhalb der Kante: aus der
// linken Schulter (NotchShoulder) an der Bildschirmkante herein, die linke
// Seite runter, unten entlang, rechts hoch und in die rechte Schulter wieder
// hinaus – an der Oberkante nicht. Unten in der Mitte bleibt eine Luecke mit
// einer kleinen Batterie. Der Fuellstand laeuft von links nach rechts.
//
// Die Schultern liegen ausserhalb der Notch-Breite, deshalb steht der Ring
// neben ihnen in der Notch und nicht in der Karte (die schneidet ab).
// Die Schulterkurve (Quad von (0, s) nach (-s, 0), Kontrollpunkt (0, 0))
// wird als Viertelkreis um (-s, s) genaehert; der Ring liegt auf dem um
// `edge` nach innen versetzten Kreis und laeuft oben aus dem Bild. Je naeher
// am Rand, desto weiter reicht er in die Schulter hinaus – die Kurve wird zur
// Spitze hin duenn.
Item {
    id: ring

    property int percent: 0
    property bool charging: false
    property real arcWidth: 2
    // Abstand der Ringmitte zur Kante: halbe Linienbreite plus rund 2,5 px
    // Luft, damit der Ring nicht an der Kante klebt. Mehr kostet Reichweite
    // in die Schultern (sie sind nur `shoulder` gross und laufen spitz aus).
    property real edge: ring.arcWidth / 2 + 2.5
    // Rundung der Notch unten (Surface.radius) und Groesse der Schultern
    property real bottomRadius: 12
    property real shoulder: 10

    // Voll = Akzent, leer = Fehlerfarbe; der Exponent haelt die Mitte
    // ausgewogen (gleiche Rechnung wie batteryRing der Insel)
    readonly property real drain: Math.pow(Math.max(0, Math.min(1, (1 - ring.percent / 100) / 0.8)), 1.5)
    readonly property color activeColor: ring.charging ? Colors.primary
                                                       : Colors.mix(Colors.primary, Colors.error, ring.drain)

    // ---- Geometrie ----
    readonly property real x0: ring.edge
    readonly property real x1: ring.width - ring.edge
    readonly property real y1: ring.height - ring.edge
    readonly property real rb: Math.max(0, Math.min(ring.bottomRadius - ring.edge, (ring.x1 - ring.x0) / 2, ring.y1 - ring.shoulder))
    // Schulterbogen: Kreis um (-s, s) bzw. (W + s, s) mit Radius s + edge,
    // bis knapp ueber die Bildschirmkante (die runde Kappe bleibt unsichtbar)
    readonly property real sr: ring.shoulder + ring.edge
    readonly property real sweep: {
        const sin = Math.max(-1, Math.min(1, (-ring.arcWidth - ring.shoulder) / ring.sr));
        return -Math.asin(sin) * 180 / Math.PI;     // Grad, positiv
    }
    readonly property real cx: ring.width / 2

    // Luecke fuer die Batterie samt Luft links und rechts
    readonly property real gapLength: glyph.width + 10

    // Abschnitte von links oben an: Gerade { x, y, dx, dy } oder Bogen
    // { mx, my, r, a, sweep } (Mittelpunkt, Start- und Drehwinkel in Grad;
    // 0 = rechts, 90 = unten, positiv = im Uhrzeigersinn auf dem Bildschirm)
    readonly property var segments: {
        const s = ring.shoulder;
        const list = [
            { kind: 1, mx: -s, my: s, r: ring.sr, a: -ring.sweep, sweep: ring.sweep },
            { kind: 0, x: ring.x0, y: s, dx: 0, dy: ring.y1 - ring.rb - s },
            { kind: 1, mx: ring.x0 + ring.rb, my: ring.y1 - ring.rb, r: ring.rb, a: 180, sweep: -90 },
            { kind: 0, x: ring.x0 + ring.rb, y: ring.y1, dx: ring.x1 - ring.x0 - 2 * ring.rb, dy: 0 },
            { kind: 1, mx: ring.x1 - ring.rb, my: ring.y1 - ring.rb, r: ring.rb, a: 90, sweep: -90 },
            { kind: 0, x: ring.x1, y: ring.y1 - ring.rb, dx: 0, dy: -(ring.y1 - ring.rb - s) },
            { kind: 1, mx: ring.width + s, my: s, r: ring.sr, a: 180, sweep: ring.sweep }
        ];
        let at = 0;
        for (const seg of list) {
            seg.length = seg.kind === 0 ? Math.abs(seg.dx) + Math.abs(seg.dy) : Math.abs(seg.sweep) * Math.PI / 180 * seg.r;
            seg.start = at;
            at += seg.length;
        }
        return list;
    }
    readonly property real totalLength: {
        const last = ring.segments[ring.segments.length - 1];
        return last.start + last.length;
    }
    // Die Luecke liegt mittig auf der Strecke (die Form ist symmetrisch)
    readonly property real gapFrom: (ring.totalLength - ring.gapLength) / 2
    readonly property real gapTo: (ring.totalLength + ring.gapLength) / 2

    function pointIn(seg: var, t: real): var {
        if (seg.kind === 0) {
            const f = seg.length > 0 ? t / seg.length : 0;
            return { x: seg.x + seg.dx * f, y: seg.y + seg.dy * f };
        }
        const turn = seg.r > 0 ? t / seg.r * 180 / Math.PI : 0;
        const a = (seg.a + (seg.sweep < 0 ? -turn : turn)) * Math.PI / 180;
        return { x: seg.mx + seg.r * Math.cos(a), y: seg.my + seg.r * Math.sin(a) };
    }

    function pointAt(s: real): var {
        for (const seg of ring.segments) {
            if (s <= seg.start + seg.length)
                return ring.pointIn(seg, Math.max(0, s - seg.start));
        }
        const last = ring.segments[ring.segments.length - 1];
        return ring.pointIn(last, last.length);
    }

    // Pfadstueck zwischen zwei Laengen als SVG, die Luecke ausgespart:
    // Geraden als L, Boegen als A (Richtungsflag aus dem Vorzeichen)
    function buildPath(from: real, to: real): string {
        return ring.buildRun(from, Math.min(to, ring.gapFrom)) + " " + ring.buildRun(Math.max(from, ring.gapTo), to);
    }

    function buildRun(from: real, to: real): string {
        if (to <= from || ring.width <= 0)
            return "";
        const p0 = ring.pointAt(from);
        let d = `M ${p0.x} ${p0.y}`;
        for (const seg of ring.segments) {
            const a = Math.max(from, seg.start);
            const b = Math.min(to, seg.start + seg.length);
            if (b <= a)
                continue;
            const p = ring.pointIn(seg, b - seg.start);
            d += seg.kind === 0 ? ` L ${p.x} ${p.y}` : ` A ${seg.r} ${seg.r} 0 0 ${seg.sweep > 0 ? 1 : 0} ${p.x} ${p.y}`;
        }
        return d;
    }

    // Fuellstand ueber die sichtbare Strecke (ohne Luecke) verteilt
    readonly property real fillEnd: {
        const visible = ring.totalLength - ring.gapLength;
        const l = visible * Math.max(0, Math.min(1, ring.percent / 100));
        return l <= ring.gapFrom ? l : l + ring.gapLength;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        smooth: true
        antialiasing: true

        // Leerer Teil, gedaempft
        ShapePath {
            strokeWidth: ring.arcWidth
            strokeColor: Colors.alpha(ring.activeColor, 0.22)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: ring.buildPath(ring.fillEnd, ring.totalLength)
            }
        }

        ShapePath {
            strokeWidth: ring.arcWidth
            strokeColor: ring.activeColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: ring.buildPath(0, ring.fillEnd)
            }
        }
    }

    // Die Batterie in der Luecke, mittig auf der Ringlinie
    BatteryGlyph {
        id: glyph

        // auf der Ringlinie, aber nie ueber die Unterkante der Notch hinaus
        x: Math.round(ring.cx - width / 2)
        y: Math.min(ring.y1 - height / 2, ring.height - height - 1)
        bodyWidth: 14
        bodyHeight: 7
        percent: ring.percent
        charging: ring.charging
        fg: Colors.alpha(Colors.fgBackground, 0.75)
    }
}
