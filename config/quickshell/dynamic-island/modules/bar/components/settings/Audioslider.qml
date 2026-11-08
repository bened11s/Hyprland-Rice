pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.modules.services.audio

import qs

// Der Ring am Aussenrand der Settings-Karte.
//
// Frueher ein fester Kreisbogen (PathAngleArc). Weil die Karte beim Hovern
// seitlich aufgeht, ist daraus eine Stadion-Form geworden: zwei Halbkreise
// als Kappen, dazwischen gerade Stuecke. Bei gleicher Breite und Hoehe ist
// das exakt wieder der alte Kreis – der eingeklappte Zustand sieht also aus
// wie vorher, und beim Aufklappen zieht sich der Ring einfach mit.
//
// Die Luecke unten bleibt (Bogenlaenge aus `sweepAngle`), und der Fuellstand
// laeuft von ihrem rechten Ende einmal herum. Beides wird als SVG-Pfad
// gerechnet: ein Teilbogen laesst sich anders nicht sauber abschneiden.
Shape {
    id: slider

    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer   // echte Kurven, nicht "eckig"
    // Kein layer.samples: der CurveRenderer glaettet selbst, ein 8x-
    // Multisampling-Layer kostete je Ring einen eigenen Puffer
    smooth: true
    antialiasing: true

    required property real arcWidth
    required property real arcGap
    // Bleiben aus Kompatibilitaet: aus sweepAngle faellt die Luecke
    property real startAngle: 130
    property real sweepAngle: 280

    property real value: Audio.volume
    property real fromValue: 0
    property bool muted: Audio.muted
    property color activeColor: muted ? Colors.error : Colors.fgBackground
    property bool showTrack: true

    // Radius der Kappen; alles Weitere haengt daran
    readonly property real ringRadius: (Math.min(width, height) - arcWidth) / 2 - arcGap
    readonly property real straight: Math.max(0, width - height)   // gerade Strecke oben/unten
    readonly property real capLength: Math.PI * ringRadius
    readonly property real totalLength: 2 * straight + 2 * capLength
    // Luecke unten, als Bogenlaenge – bei einem Kreis entspricht das dem
    // fehlenden Winkel von frueher
    readonly property real gapLength: (360 - sweepAngle) * Math.PI / 180 * ringRadius

    readonly property real fromLength: slider.gapLength / 2
    readonly property real toLength: slider.totalLength - slider.gapLength / 2

    // Punkt auf dem Umriss, gemessen ab der Mitte unten.
    //
    // Gerechnet wird nach rechts, ausgegeben gespiegelt: dadurch beginnt der
    // Fuellstand links unten bei 0 % und endet rechts unten bei 100 %. Die
    // Form ist symmetrisch, deshalb genuegt es, x zu spiegeln – die Boegen
    // drehen sich damit um, was in buildPath das Richtungsflag erklaert.
    function pointAt(s: real): var {
        const p = slider.rawPointAt(s);
        return { x: slider.width - p.x, y: p.y };
    }

    function rawPointAt(s: real): var {
        const r = slider.ringRadius;
        const cy = slider.height / 2;
        const lx = slider.height / 2;
        const rx = slider.width - slider.height / 2;
        const half = slider.straight / 2;

        if (s <= half)                                   // unten rechts
            return { x: slider.width / 2 + s, y: cy + r };

        s -= half;
        if (s <= slider.capLength) {                     // rechte Kappe
            const a = (90 - (s / r) * 180 / Math.PI) * Math.PI / 180;
            return { x: rx + r * Math.cos(a), y: cy + r * Math.sin(a) };
        }

        s -= slider.capLength;
        if (s <= slider.straight)                        // oben
            return { x: rx - s, y: cy - r };

        s -= slider.straight;
        if (s <= slider.capLength) {                     // linke Kappe
            const a = (-90 - (s / r) * 180 / Math.PI) * Math.PI / 180;
            return { x: lx + r * Math.cos(a), y: cy + r * Math.sin(a) };
        }

        s -= slider.capLength;                           // unten links
        return { x: lx + Math.min(s, half), y: cy + r };
    }

    // Pfadstueck zwischen zwei Laengen als SVG. Gerade Abschnitte werden zu
    // L, die Kappen zu A – dort, wo ein Abschnitt endet, wird geschnitten.
    function buildPath(from: real, to: real): string {
        const r = slider.ringRadius;
        if (r <= 0 || to <= from)
            return "";

        const half = slider.straight / 2;
        const bounds = [0, half, half + slider.capLength,
            half + slider.capLength + slider.straight,
            half + 2 * slider.capLength + slider.straight,
            slider.totalLength];
        // 0 = gerade, 1 = Kappe
        const kinds = [0, 1, 0, 1, 0];

        const start = slider.pointAt(from);
        let d = `M ${start.x} ${start.y}`;

        for (let i = 0; i < kinds.length; i++) {
            const segFrom = Math.max(from, bounds[i]);
            const segTo = Math.min(to, bounds[i + 1]);
            if (segTo <= segFrom)
                continue;

            const p = slider.pointAt(segTo);
            if (kinds[i] === 0)
                d += ` L ${p.x} ${p.y}`;
            else {
                // Grosser Bogen erst ab einem Halbkreis; Richtung immer gleich
                const large = (segTo - segFrom) > Math.PI * r ? 1 : 0;
                // Richtung 1, weil die Punkte gespiegelt herauskommen
                d += ` A ${r} ${r} 0 ${large} 1 ${p.x} ${p.y}`;
            }
        }
        return d;
    }

    ShapePath {
        strokeWidth: slider.arcWidth
        strokeColor: slider.showTrack ? Colors.alpha(slider.activeColor, 0.55) : "transparent"
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathSvg {
            path: slider.buildPath(slider.fromLength, slider.toLength)
        }
    }

    ShapePath {
        strokeWidth: slider.arcWidth
        strokeColor: slider.activeColor
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap

        PathSvg {
            readonly property real start: slider.fromLength
                + (slider.toLength - slider.fromLength)
                    * Math.max(0, Math.min(1, slider.fromValue))
            readonly property real end: slider.fromLength
                + (slider.toLength - slider.fromLength)
                    * Math.max(0, Math.min(1, slider.value))

            path: slider.buildPath(start, end)
        }
    }
}
