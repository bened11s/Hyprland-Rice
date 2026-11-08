pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.lock
import qs.modules.services.config

// Griff ueber einem Element der Sperrbildschirm-Vorschau (Uhr, Karte): legt
// sich auf dessen sichtbare Grenzen (samt Vergroesserung) und zeigt Rahmen,
// Etikett und an den Ecken die Griffe fuer die Groesse.
//
// Ziehen mit Einrasten (Mitte, Drittel, Raender und am anderen Element:
// Kante an Kante, Mitte an Mitte), Shift = frei. Groesse: die Ecke
// gegenueber dem Griff bleibt stehen, die gezogene Kante rastet mit ein.
// Waehrend des Ziehens geht der Stand nur zur Anzeige an LockLayout
// (preview), festgehalten (Verlauf, Speichern) wird beim Loslassen (set).
// Das Element selbst folgt LockLayout – der Griff liest seine Lage zurueck.
Item {
    id: handle

    property string name: ""
    property string title: ""
    // Das Element in der Vorschau (LockScreen.clockItem / mediaItem)
    property Item target: null
    // Die anderen Griffe: ihre Kanten und Mitten sind Einrast-Linien
    property var others: []
    // Maus liegt ueber der Leiste (EditStage)
    property bool blocked: false
    // Element steht leer da (Karte ohne Musik): zurueckgenommen zeichnen
    property bool placeholder: false
    // Ausgeblendet (LockLayout.hidden): bleibt als blasser Platzhalter greifbar
    readonly property bool hiddenHere: LockLayout.hidden(handle.name)
    property Item guideX
    property Item guideY

    readonly property bool selected: LockLayout.selected === handle.name
    readonly property bool otherSelected: LockLayout.selected !== "" && !handle.selected
    readonly property real frame: 8
    readonly property real snapRange: 12
    readonly property real areaW: handle.parent?.width ?? 0
    readonly property real areaH: handle.parent?.height ?? 0
    readonly property real size: LockLayout.scale(handle.name)

    // Sichtbare Grenzen des Elements: dessen `scale` dreht um die Mitte
    readonly property real tScale: handle.target?.scale ?? 1
    x: handle.target ? handle.target.x + handle.target.width * (1 - handle.tScale) / 2 : 0
    y: handle.target ? handle.target.y + handle.target.height * (1 - handle.tScale) / 2 : 0
    width: handle.target ? handle.target.width * handle.tScale : 0
    height: handle.target ? handle.target.height * handle.tScale : 0
    visible: handle.target !== null && handle.target.visible
    z: handle.selected ? 3 : 1

    property bool resizing: false
    property real liveSize: 1
    // Ziehen oder Skalieren laeuft (Optionsfeld solange weg)
    readonly property bool busy: dragger.active || handle.resizing

    // Gewaehlt wird schon beim Druecken; ein anderes gewaehltes Element
    // tritt zurueck, ein leeres (Platzhalter) immer
    readonly property real dimLevel: (handle.otherSelected ? 0.45 : 1) * (handle.placeholder ? 0.55 : 1)
                                     * (handle.hiddenHere ? 0.25 : 1)
    property real dim: handle.dimLevel

    Behavior on dim {
        NumberAnimation { duration: Appearance.fadeDuration }
    }

    Binding {
        target: handle.target
        property: "opacity"
        value: handle.dim
        when: handle.target !== null
    }

    // Mittelpunkt und Groesse als Eintrag fuer LockLayout
    function entry(): var {
        return {
            x: (handle.x + handle.width / 2) / handle.areaW,
            y: (handle.y + handle.height / 2) / handle.areaH,
            size: handle.size
        };
    }

    function select(): void {
        LockLayout.selected = handle.name;
    }

    // Pfeiltasten: um dx/dy (Anteil des Bildschirms) verschieben
    function nudge(dx: real, dy: real): void {
        const e = handle.entry();
        e.x = Math.max(0, Math.min(1, e.x + dx));
        e.y = Math.max(0, Math.min(1, e.y + dy));
        LockLayout.set(handle.name, e);
    }

    // + / -: um den Faktor vergroessern, Mitte bleibt
    function grow(f: real): void {
        const e = handle.entry();
        e.size = handle.clampSize(e.size * f);
        LockLayout.set(handle.name, e);
    }

    // Gehoert ein Punkt (Buehnenkoordinaten) zu diesem Griff – Rahmen oder
    // Ecken-Griff? Dann ist ein Druck dort kein Druck ins Leere
    function owns(px: real, py: real): bool {
        if (!handle.visible)
            return false;
        const m = handle.frame + (handle.selected ? 16 : 0);
        return px >= handle.x - m && py >= handle.y - m
            && px <= handle.x + handle.width + m && py <= handle.y + handle.height + m;
    }

    // ---- Rahmen ----

    Rectangle {
        anchors.fill: parent
        anchors.margins: -handle.frame
        radius: 12
        color: handle.selected ? Colors.alpha(Colors.primary, 0.08) : "transparent"
        border.width: handle.selected ? 2 : 1
        border.color: handle.selected ? Colors.primary
                    : Colors.alpha("#ffffff", (hoverArea.hovered ? 0.6 : 0.3) * (handle.hiddenHere ? 0.5 : 1))

        // Etikett oben links; beim Skalieren mit der Groesse in Prozent
        Rectangle {
            visible: handle.selected || hoverArea.hovered
            x: 10
            y: -height / 2
            width: label.implicitWidth + 12
            height: 18
            radius: 9
            color: handle.selected ? Colors.primary : Colors.alpha("#000000", 0.6)

            Text {
                id: label

                anchors.centerIn: parent
                text: handle.resizing ? `${handle.title} · ${Math.round(handle.liveSize * 100)} %` : handle.title
                color: handle.selected ? Colors.fgPrimary : "#ffffff"
                font.family: Config.font
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    // Rahmen (handle.frame) gehoert dazu: Hover, Antippen und Ziehen greifen
    // auch dort
    HoverHandler {
        id: hoverArea

        enabled: !handle.blocked
        margin: handle.frame
        cursorShape: dragger.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }

    TapHandler {
        id: tap

        enabled: !handle.blocked || tap.pressed
        margin: handle.frame
        gesturePolicy: TapHandler.DragThreshold
        onPressedChanged: if (tap.pressed) handle.select()
    }

    // ---- Einrasten ----

    // Linien einer Achse: Bildschirm (Mitte und Drittel fuer Mittelpunkte,
    // Rand mit Abstand fuer Kanten; senkrecht mehr wegen der Notch) und das
    // andere Element (Rahmenkanten fuer Kanten, Mitte fuer Mitte).
    // { at, center } – center = nur fuer Mittelpunkte
    function snapLines(vertical: bool): var {
        const total = vertical ? handle.areaH : handle.areaW;
        const margin = total * (vertical ? 0.07 : 0.035);
        const lines = [
            { at: total / 3, center: true },
            { at: total / 2, center: true },
            { at: total * 2 / 3, center: true },
            { at: margin, center: false },
            { at: total - margin, center: false }
        ];
        for (const o of handle.others) {
            if (!o || o === handle || !o.visible)
                continue;
            const a = vertical ? o.y : o.x;
            const len = vertical ? o.height : o.width;
            lines.push({ at: a - handle.frame, center: false },
                       { at: a + len + handle.frame, center: false },
                       { at: a + len / 2, center: true });
        }
        return lines;
    }

    // Verschieben: Mittelpunkt c (Laenge len ohne Rahmen) so, dass eine
    // Rahmenkante oder die Mitte auf der naechsten Linie liegt.
    // { v, line } – line -1 = frei
    function snapMove(c: real, len: real, lines: var): var {
        const half = len / 2 + handle.frame;
        let best = { v: c, line: -1, d: handle.snapRange };
        for (const l of lines)
            for (const part of l.center ? [0] : [-half, half]) {
                const v = l.at - part;
                const d = Math.abs(v - c);
                if (d < best.d)
                    best = { v: v, line: l.at, d: d };
            }
        return best;
    }

    // Skalieren: Groesse s so, dass die gezogene Rahmenkante auf einer
    // Linie liegt. a = feste Ecke, dir = Richtung, k = px je Groesseneinheit.
    // { s, line, d } – d = Abstand in px
    function snapResize(s: real, a: real, dir: int, k: real, lines: var): var {
        let best = { s: s, line: -1, d: handle.snapRange };
        for (const l of lines) {
            if (l.center)
                continue;
            const ss = (dir * (l.at - a) - handle.frame) / k;
            const d = Math.abs(ss - s) * k;
            if (ss > 0 && d < best.d)
                best = { s: ss, line: l.at, d: d };
        }
        return best;
    }

    // Wie weit die Maus seit dem Druck gewandert ist, in Fensterkoordinaten
    // (nicht `translation`: die misst Qt im Griff, und der wandert selbst mit)
    function moved(h: var): point {
        const c = h.centroid;
        return Qt.point(c.scenePosition.x - c.scenePressPosition.x, c.scenePosition.y - c.scenePressPosition.y);
    }

    // Shift gedrueckt: frei, ohne Einrasten
    function free(h: var): bool {
        return (h.centroid.modifiers & Qt.ShiftModifier) !== 0;
    }

    function clampSize(s: real): real {
        return Math.max(LockLayout.minOf(handle.name), Math.min(LockLayout.maxOf(handle.name), s));
    }

    DragHandler {
        id: dragger

        // Ein laufendes Ziehen nicht abbrechen, wenn es ueber die Leiste geht
        enabled: dragger.active || (!handle.blocked && !handle.resizing)
        margin: handle.frame
        target: null
        dragThreshold: 4

        property real startX: 0
        property real startY: 0
        property real dragX: 0
        property real dragY: 0
        // Linien beim Start einmal sammeln – waehrend des Ziehens aendern sie sich nicht
        property var linesX: []
        property var linesY: []

        onActiveChanged: {
            if (dragger.active) {
                handle.select();
                dragger.startX = handle.x + handle.width / 2;
                dragger.startY = handle.y + handle.height / 2;
                dragger.dragX = dragger.startX;
                dragger.dragY = dragger.startY;
                dragger.linesX = handle.snapLines(false);
                dragger.linesY = handle.snapLines(true);
                return;
            }
            handle.guideX.at = -1;
            handle.guideY.at = -1;
            LockLayout.set(handle.name, {
                x: dragger.dragX / handle.areaW,
                y: dragger.dragY / handle.areaH,
                size: handle.size
            });
        }

        onCentroidChanged: {
            if (!dragger.active)
                return;
            const m = handle.moved(dragger);
            const nx = dragger.startX + m.x;
            const ny = dragger.startY + m.y;
            const free = handle.free(dragger);
            const sx = free ? { v: nx, line: -1 } : handle.snapMove(nx, handle.width, dragger.linesX);
            const sy = free ? { v: ny, line: -1 } : handle.snapMove(ny, handle.height, dragger.linesY);
            dragger.dragX = sx.v;
            dragger.dragY = sy.v;
            handle.guideX.at = sx.line;
            handle.guideY.at = sy.line;
            LockLayout.preview(handle.name, {
                x: sx.v / handle.areaW,
                y: sy.v / handle.areaH,
                size: handle.size
            });
        }
    }

    // Groesse: Griffe an den vier Ecken
    Repeater {
        model: [{ dx: -1, dy: -1 }, { dx: 1, dy: -1 }, { dx: -1, dy: 1 }, { dx: 1, dy: 1 }]

        Rectangle {
            id: grip

            required property var modelData
            readonly property int dx: grip.modelData.dx
            readonly property int dy: grip.modelData.dy

            visible: handle.selected
            z: 11
            x: (grip.dx < 0 ? -handle.frame : handle.width + handle.frame) - width / 2
            y: (grip.dy < 0 ? -handle.frame : handle.height + handle.frame) - height / 2
            width: 16
            height: 16
            radius: 8
            color: Colors.primary
            border.width: 2
            border.color: Colors.fgPrimary

            HoverHandler {
                cursorShape: grip.dx === grip.dy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            }

            DragHandler {
                id: sizer

                target: null
                dragThreshold: 1
                // Der Griff gewinnt gegen alles darunter (Ziehen des Elements)
                grabPermissions: PointerHandler.CanTakeOverFromAnything

                property real startSize: 1
                property real startW: 1
                property real startH: 1
                // Die Ecke gegenueber dem Griff bleibt stehen
                property real anchorX: 0
                property real anchorY: 0
                property real liveX: 0
                property real liveY: 0
                property var linesX: []
                property var linesY: []

                onActiveChanged: {
                    if (sizer.active) {
                        sizer.startSize = handle.size;
                        sizer.startW = Math.max(20, handle.width);
                        sizer.startH = Math.max(20, handle.height);
                        sizer.anchorX = handle.x + handle.width / 2 - grip.dx * handle.width / 2;
                        sizer.anchorY = handle.y + handle.height / 2 - grip.dy * handle.height / 2;
                        sizer.liveX = handle.x + handle.width / 2;
                        sizer.liveY = handle.y + handle.height / 2;
                        sizer.linesX = handle.snapLines(false);
                        sizer.linesY = handle.snapLines(true);
                        handle.liveSize = sizer.startSize;
                        handle.resizing = true;
                        return;
                    }
                    handle.resizing = false;
                    handle.guideX.at = -1;
                    handle.guideY.at = -1;
                    LockLayout.set(handle.name, {
                        x: sizer.liveX / handle.areaW,
                        y: sizer.liveY / handle.areaH,
                        size: handle.liveSize
                    });
                }

                onCentroidChanged: {
                    if (!sizer.active)
                        return;
                    const m = handle.moved(sizer);
                    // px je Groesseneinheit, beim Start gemessen – nicht bei
                    // jeder Bewegung neu, sonst schaukelte sich alte Breite /
                    // neue Groesse auf
                    const kw = sizer.startW / sizer.startSize;
                    const kh = sizer.startH / sizer.startSize;
                    // Groesse, bei der die Rahmenkante je Achse unter der Maus
                    // laege; das Seitenverhaeltnis ist fest, also zaehlt die
                    // Achse, auf der die Maus weiter gewandert ist (4. Potenz:
                    // etwas Drift quer dazu stoert nicht, schraeg wird gemischt)
                    const s0 = sizer.startSize;
                    const a = (sizer.startW + grip.dx * m.x) / kw - s0;
                    const b = (sizer.startH + grip.dy * m.y) / kh - s0;
                    const wa = Math.pow(m.x, 4), wb = Math.pow(m.y, 4);
                    let s = s0 + (wa + wb > 0 ? (a * wa + b * wb) / (wa + wb) : 0);
                    let lineX = -1, lineY = -1;
                    if (!handle.free(sizer)) {
                        const sx = handle.snapResize(s, sizer.anchorX, grip.dx, kw, sizer.linesX);
                        const sy = handle.snapResize(s, sizer.anchorY, grip.dy, kh, sizer.linesY);
                        const best = sx.d <= sy.d ? sx : sy;
                        if (best.d < handle.snapRange) {
                            s = best.s;
                            if (best === sx)
                                lineX = best.line;
                            else
                                lineY = best.line;
                        }
                    }
                    s = handle.clampSize(s);
                    handle.liveSize = s;
                    // Der Mittelpunkt folgt der neuen Breite, so bleibt die
                    // feste Ecke stehen
                    sizer.liveX = sizer.anchorX + grip.dx * kw * s / 2;
                    sizer.liveY = sizer.anchorY + grip.dy * kh * s / 2;
                    handle.guideX.at = lineX;
                    handle.guideY.at = lineY;
                    LockLayout.preview(handle.name, {
                        x: sizer.liveX / handle.areaW,
                        y: sizer.liveY / handle.areaH,
                        size: s
                    });
                }
            }
        }
    }
}
