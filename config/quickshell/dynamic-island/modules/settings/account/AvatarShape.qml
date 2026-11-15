pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Profilbild in einer Form (Material 3 Expressive) mit Ring in primary.
// Canvas statt MultiEffect-Maske: zeichnet auch im Software-Renderer
// (docs/settings-shot) und malt nur neu, wenn sich Bild oder Form aendern.
//
//   shape  sunny (Konto-Seite) | circle | cookie | squircle | clover
//   source Bild-URL; leer oder kaputt -> Flaeche mit Personen-Symbol
Item {
    id: avatar

    property url source: ""
    property string shape: "sunny"
    // Abstand Bild -> Ring und Ringstaerke in px; 0 = kein Ring
    property real ring: 3
    property real gap: 4
    // Drehung der Form (Grad), z. B. fuer langsames Kreisen beim Hovern
    property real spin: 0
    // Abdunkeln (0..1) innerhalb der Form, z. B. beim Hovern
    property real dim: 0
    // Bild geladen; die Canvas-Abfragen selbst melden keine Aenderung
    property bool ready: false

    // Radius-Faktor (0..1) je Winkel; die Formen sind Polarkurven, damit
    // Bild-Clip und Ring dieselbe Kontur haben.
    function radiusAt(t: real): real {
        switch (avatar.shape) {
        case "cookie":   // 9 weiche Boegen
            return (1 + 0.07 * Math.cos(9 * t)) / 1.07;
        case "sunny":    // 12 flache Zacken
            return (1 + 0.045 * Math.cos(12 * t)) / 1.045;
        case "clover":   // 4 Blaetter
            return (1 + 0.16 * Math.cos(4 * t)) / 1.16;
        case "squircle": { // Superellipse n = 4
            const c = Math.pow(Math.abs(Math.cos(t)), 4), s = Math.pow(Math.abs(Math.sin(t)), 4);
            return 1 / Math.pow(2 * (c + s), 0.25);
        }
        default:
            return 1;
        }
    }

    function trace(ctx: var, cx: real, cy: real, r: real): void {
        const steps = 180, rot = avatar.spin * Math.PI / 180;
        ctx.beginPath();
        for (let i = 0; i <= steps; i++) {
            const t = i / steps * 2 * Math.PI;
            const k = r * avatar.radiusAt(t);
            const x = cx + k * Math.cos(t + rot), y = cy + k * Math.sin(t + rot);
            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
        }
        ctx.closePath();
    }

    onSourceChanged: {
        avatar.ready = false;
        if (avatar.source != "")
            canvas.loadImage(avatar.source);
        canvas.requestPaint();
    }
    onShapeChanged: canvas.requestPaint()
    onSpinChanged: canvas.requestPaint()
    onDimChanged: canvas.requestPaint()
    onRingChanged: canvas.requestPaint()

    Connections {
        target: Colors

        function onPrimaryChanged(): void {
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas

        anchors.fill: parent
        onImageLoaded: {
            avatar.ready = canvas.isImageLoaded(avatar.source) && !canvas.isImageError(avatar.source);
            requestPaint();
        }

        onPaint: {
            const ctx = getContext("2d");
            const cx = width / 2, cy = height / 2, outer = Math.min(width, height) / 2;
            const inner = avatar.ring > 0 ? outer - avatar.ring - avatar.gap : outer;
            ctx.reset();

            if (avatar.ring > 0) {
                avatar.trace(ctx, cx, cy, outer - avatar.ring / 2);
                ctx.lineWidth = avatar.ring;
                ctx.strokeStyle = Colors.primary;
                ctx.stroke();
            }

            avatar.trace(ctx, cx, cy, inner);
            ctx.fillStyle = Colors.alpha(Colors.fgSurface, 0.08);
            ctx.fill();
            ctx.save();
            ctx.clip();
            // ~/.face ist quadratisch (usermgr.py schneidet auf 512 px zu)
            if (avatar.ready)
                ctx.drawImage(avatar.source, cx - inner, cy - inner, inner * 2, inner * 2);
            if (avatar.dim > 0) {
                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.45 * avatar.dim);
                ctx.fillRect(0, 0, width, height);
            }
            ctx.restore();
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !avatar.ready
        text: "person"
        color: Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: avatar.width / 2
    }
}
