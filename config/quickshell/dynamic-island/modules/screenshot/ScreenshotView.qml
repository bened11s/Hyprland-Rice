pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.screenshot
import qs.modules.widgets

// Das Screenshot-Overlay EINES Monitors: das Standbild, darueber die
// Abdunkelung mit dem Ausschnitt als Loch, beim Zeigen der Rahmen des
// Fensters unter dem Zeiger, am Ausschnitt die Werkzeugleiste. Der Ausschnitt
// selbst liegt in der gemeinsamen `session` – gehoert er einem anderen
// Monitor, zeigt dieser hier nur sein abgedunkeltes Standbild.
//
// Zeiger:  Klick auf ein Fenster waehlt es, Klick auf den Desktop den ganzen
//          Monitor, Ziehen zieht ein freies Rechteck (Shift: Quadrat).
//          Danach: innen verschieben, an Kanten und Ecken ziehen.
//          Rechtsklick schliesst.
// Tasten:  Enter = Vorgabe (`preset`), C S E T Q R = Kopieren, Speichern,
//          Bearbeiten, Text, QR-Code, Aufnehmen. Escape hebt erst den
//          Ausschnitt auf, dann schliesst es.
// ocr/qr:  der erste Ausschnitt loest sofort aus – kein Bearbeiten, keine
//          Leiste (SUPER+SHIFT+T soll zackig gehen).
Item {
    id: view

    required property string screenName
    required property ScreenshotSession session
    // Standbild (file://-URL) in Geraetepixeln; `dpr` ist die Skalierung des
    // Monitors, damit das Bild 1:1 auf den Pixeln liegt
    property string shot: ""
    property real dpr: 1
    // [{x,y,w,h,title,cls}] in Monitor-Koordinaten, obenliegende zuerst
    property var windows: []
    // Was Enter tut: "copy" | "save" | "edit" | "ocr" | "qr"
    property string preset: "copy"
    readonly property bool instant: view.preset === "ocr" || view.preset === "qr"

    // Der Ausschnitt liegt auf diesem Monitor
    readonly property bool owner: view.session.has && view.session.screen === view.screenName
    readonly property rect sel: view.owner
        ? Qt.rect(view.session.x, view.session.y, view.session.w, view.session.h)
        : Qt.rect(0, 0, 0, 0)
    // Bearbeitbar: Griffe, Verschieben, Leiste
    readonly property bool editable: view.owner && !view.instant

    // "idle" | "pending" (gedrueckt, noch nicht gezogen) | "draw" | "move" | "resize"
    property string mode: "idle"
    property real pressX: 0
    property real pressY: 0
    // Ausschnitt beim Druecken – Bezug fuer Verschieben und Ziehen
    property rect startRect: Qt.rect(0, 0, 0, 0)
    // Gezogene Kanten: 1 links, 2 rechts, 4 oben, 8 unten
    property int edges: 0
    // Griffbreite der Kanten, innen wie aussen
    readonly property real grip: 12
    readonly property real dragThreshold: 4

    // Fenster unter dem Zeiger (nur im Leerlauf, nicht ueber dem Ausschnitt)
    property var hoverWin: null
    // Erst nach dem Aufbau: die Abdunkelung blendet ein, das Bild steht sofort
    property bool shown: false

    readonly property bool dragging: view.mode === "draw" || view.mode === "resize"

    focus: true
    Component.onCompleted: {
        view.shown = true;
        view.forceActiveFocus();
    }

    // ---- Geometrie ----

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    function windowAt(px: real, py: real): var {
        for (const w of view.windows) {
            if (px >= w.x && px < w.x + w.w && py >= w.y && py < w.y + w.h)
                return w;
        }
        return null;
    }

    function inside(r: rect, px: real, py: real): bool {
        return px >= r.x && px < r.x + r.width && py >= r.y && py < r.y + r.height;
    }

    // Kanten im Griffbereich des Ausschnitts (Bitmaske, 0 = keine)
    function hitEdges(px: real, py: real): int {
        if (!view.editable)
            return 0;
        const r = view.sel, g = view.grip;
        if (px < r.x - g || px > r.x + r.width + g || py < r.y - g || py > r.y + r.height + g)
            return 0;
        let e = 0;
        if (Math.abs(px - r.x) <= g)
            e |= 1;
        else if (Math.abs(px - (r.x + r.width)) <= g)
            e |= 2;
        if (Math.abs(py - r.y) <= g)
            e |= 4;
        else if (Math.abs(py - (r.y + r.height)) <= g)
            e |= 8;
        return e;
    }

    function cursorFor(e: int): int {
        switch (e) {
        case 1: case 2: return Qt.SizeHorCursor;
        case 4: case 8: return Qt.SizeVerCursor;
        case 5: case 10: return Qt.SizeFDiagCursor;
        case 6: case 9: return Qt.SizeBDiagCursor;
        }
        return Qt.CrossCursor;
    }

    // Fenster unter dem Punkt waehlen (auf den Monitor beschnitten), sonst
    // den ganzen Monitor
    function pick(px: real, py: real): void {
        const w = view.windowAt(px, py);
        if (w) {
            const x0 = view.clamp(w.x, 0, view.width), y0 = view.clamp(w.y, 0, view.height);
            const x1 = view.clamp(w.x + w.w, 0, view.width), y1 = view.clamp(w.y + w.h, 0, view.height);
            if (x1 - x0 >= 1 && y1 - y0 >= 1) {
                view.session.set(view.screenName, x0, y0, x1 - x0, y1 - y0);
                return;
            }
        }
        view.session.set(view.screenName, 0, 0, view.width, view.height);
    }

    function draw(mx: real, my: real, square: bool): void {
        const x0 = view.pressX, y0 = view.pressY;
        let x1 = view.clamp(mx, 0, view.width), y1 = view.clamp(my, 0, view.height);
        if (square) {
            const side = Math.min(Math.abs(x1 - x0), Math.abs(y1 - y0));
            x1 = x0 + Math.sign(x1 - x0) * side;
            y1 = y0 + Math.sign(y1 - y0) * side;
        }
        view.session.set(view.screenName, Math.min(x0, x1), Math.min(y0, y1),
                         Math.abs(x1 - x0), Math.abs(y1 - y0));
    }

    function move(mx: real, my: real): void {
        const r = view.startRect;
        view.session.set(view.screenName,
                         view.clamp(r.x + mx - view.pressX, 0, view.width - r.width),
                         view.clamp(r.y + my - view.pressY, 0, view.height - r.height),
                         r.width, r.height);
    }

    function resize(mx: real, my: real): void {
        const r = view.startRect, dx = mx - view.pressX, dy = my - view.pressY;
        let l = r.x, t = r.y, rt = r.x + r.width, b = r.y + r.height;
        if (view.edges & 1)
            l = view.clamp(l + dx, 0, rt - 1);
        if (view.edges & 2)
            rt = view.clamp(rt + dx, l + 1, view.width);
        if (view.edges & 4)
            t = view.clamp(t + dy, 0, b - 1);
        if (view.edges & 8)
            b = view.clamp(b + dy, t + 1, view.height);
        view.session.set(view.screenName, l, t, rt - l, b - t);
    }

    // Nach einem neuen Ausschnitt per Zeiger: ocr/qr laufen sofort
    function settled(fresh: bool): void {
        if (fresh && view.instant && view.session.has)
            view.session.run(view.preset);
    }

    function closeOrClear(): void {
        if (view.session.has)
            view.session.clear();
        else
            Screenshot.close();
    }

    Keys.onPressed: event => {
        const run = {
            [Qt.Key_C]: "copy", [Qt.Key_S]: "save", [Qt.Key_E]: "edit",
            [Qt.Key_T]: "ocr", [Qt.Key_Q]: "qr", [Qt.Key_R]: "record"
        };
        if (event.key === Qt.Key_Escape)
            view.closeOrClear();
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            view.session.run(view.preset);
        else if (run[event.key] !== undefined && event.modifiers === Qt.NoModifier)
            view.session.run(run[event.key]);
        else
            return;
        event.accepted = true;
    }

    // ---- Standbild ----
    Image {
        id: shotImage

        anchors.fill: parent
        source: view.shot
        // Das Standbild hat genau die Pixelmasse des Monitors; ohne
        // sourceSize bleibt es in voller Groesse und liegt 1:1 auf den
        // Pixeln. Nur wenn das einmal nicht stimmt, wird geglaettet.
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        smooth: shotImage.sourceSize.width !== Math.round(view.width * view.dpr)
             || shotImage.sourceSize.height !== Math.round(view.height * view.dpr)
    }

    // ---- Abdunkelung mit Loch ----
    Item {
        id: shade

        anchors.fill: parent
        opacity: view.shown ? 1 : 0

        readonly property color tint: Colors.alpha("#000000", 0.5)

        Fade on opacity {}

        Rectangle {
            width: view.width
            height: view.owner ? view.sel.y : view.height
            color: shade.tint
        }
        Rectangle {
            visible: view.owner
            y: view.sel.y + view.sel.height
            width: view.width
            height: view.height - y
            color: shade.tint
        }
        Rectangle {
            visible: view.owner
            y: view.sel.y
            width: view.sel.x
            height: view.sel.height
            color: shade.tint
        }
        Rectangle {
            visible: view.owner
            x: view.sel.x + view.sel.width
            y: view.sel.y
            width: view.width - x
            height: view.sel.height
            color: shade.tint
        }
    }

    // ---- Fenster unter dem Zeiger ----
    Rectangle {
        readonly property var win: view.hoverWin
        readonly property bool shown: view.mode === "idle" && win !== null && !toolbar.hovered

        visible: opacity > 0
        opacity: shown ? 1 : 0
        x: win ? win.x : 0
        y: win ? win.y : 0
        width: win ? win.w : 0
        height: win ? win.h : 0
        color: Colors.alpha("#ffffff", 0.08)
        border.width: 1
        border.color: Colors.alpha(Colors.primary, 0.85)

        Fade on opacity {}
    }

    // ---- Ausschnitt ----
    Rectangle {
        visible: view.owner
        x: view.sel.x - 1
        y: view.sel.y - 1
        width: view.sel.width + 2
        height: view.sel.height + 2
        color: "transparent"
        border.width: 1
        border.color: Colors.alpha("#000000", 0.35)
    }
    Rectangle {
        visible: view.owner
        x: view.sel.x
        y: view.sel.y
        width: view.sel.width
        height: view.sel.height
        color: "transparent"
        border.width: 1
        border.color: Colors.primary
    }

    // Griffe an den Ecken
    Repeater {
        model: view.editable && view.mode === "idle" ? 4 : 0

        Rectangle {
            required property int index

            readonly property real size: 7
            x: (index % 2 === 0 ? view.sel.x : view.sel.x + view.sel.width) - size / 2
            y: (index < 2 ? view.sel.y : view.sel.y + view.sel.height) - size / 2
            width: size
            height: size
            radius: 1.5
            color: Colors.primary
            border.width: 1
            border.color: Colors.alpha("#000000", 0.35)
        }
    }

    // ---- Groesse beim Ziehen ----
    Rectangle {
        id: readout

        readonly property real gap: 6
        readonly property bool above: view.sel.y >= height + gap + 2

        visible: opacity > 0
        opacity: view.owner && view.dragging ? 1 : 0
        x: view.clamp(view.sel.x, 4, view.width - width - 4)
        y: above ? view.sel.y - gap - height : view.sel.y + gap
        width: readoutText.implicitWidth + 16
        height: 22
        radius: 6
        color: Colors.alpha(Colors.background, 0.88)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.4)

        Fade on opacity {}

        Text {
            id: readoutText

            anchors.centerIn: parent
            text: `${view.sel.width} × ${view.sel.height}`
            font.family: Config.font
            font.pixelSize: 11
            color: Colors.fgBackground
        }
    }

    // ---- Zeiger ----
    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: view.mode === "move" ? Qt.SizeAllCursor
                   : view.mode === "resize" ? view.cursorFor(view.edges)
                   : view.mode !== "idle" ? Qt.CrossCursor
                   : view.hitEdges(mouseX, mouseY) ? view.cursorFor(view.hitEdges(mouseX, mouseY))
                   : view.editable && view.inside(view.sel, mouseX, mouseY) ? Qt.SizeAllCursor
                   : Qt.CrossCursor

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                Screenshot.close();
                return;
            }
            view.pressX = mouse.x;
            view.pressY = mouse.y;
            view.hoverWin = null;
            if (view.editable) {
                view.startRect = view.sel;
                view.edges = view.hitEdges(mouse.x, mouse.y);
                if (view.edges) {
                    view.mode = "resize";
                    return;
                }
                if (view.inside(view.sel, mouse.x, mouse.y)) {
                    view.mode = "move";
                    return;
                }
            }
            view.mode = "pending";
        }

        onPositionChanged: mouse => {
            const square = (mouse.modifiers & Qt.ShiftModifier) !== 0;
            switch (view.mode) {
            case "pending":
                if (Math.abs(mouse.x - view.pressX) < view.dragThreshold
                    && Math.abs(mouse.y - view.pressY) < view.dragThreshold)
                    return;
                view.mode = "draw";
                view.draw(mouse.x, mouse.y, square);
                break;
            case "draw":
                view.draw(mouse.x, mouse.y, square);
                break;
            case "move":
                view.move(mouse.x, mouse.y);
                break;
            case "resize":
                view.resize(mouse.x, mouse.y);
                break;
            default: {
                // Ueber dem eigenen Ausschnitt gibt es nichts zu waehlen
                const onSel = view.editable
                    && (view.hitEdges(mouse.x, mouse.y) || view.inside(view.sel, mouse.x, mouse.y));
                view.hoverWin = onSel ? null : view.windowAt(mouse.x, mouse.y);
            }
            }
        }

        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            const mode = view.mode;
            view.mode = "idle";
            if (mode === "pending") {
                view.pick(mouse.x, mouse.y);
                view.settled(true);
            } else if (mode === "draw") {
                // Ein winziger Zug war ein Klick
                if (view.session.w < 3 || view.session.h < 3)
                    view.pick(view.pressX, view.pressY);
                view.settled(true);
            } else {
                view.settled(false);
            }
            view.hoverWin = view.editable && view.inside(view.sel, mouse.x, mouse.y)
                ? null : view.windowAt(mouse.x, mouse.y);
        }

        onExited: view.hoverWin = null
    }

    // ---- Werkzeugleiste ----
    // Unter dem Ausschnitt; fehlt dort der Platz, darueber; fehlt er auch
    // da, innen am unteren Rand.
    ShotToolbar {
        id: toolbar

        readonly property real gap: 10
        readonly property real margin: 6
        readonly property bool below: view.sel.y + view.sel.height + gap + height + margin <= view.height
        readonly property bool above: !below && view.sel.y - gap - height >= margin
        readonly property bool shown: view.editable && view.mode === "idle"

        preset: view.preset
        tipAbove: !below
        x: view.clamp(view.sel.x + view.sel.width / 2 - width / 2, margin, view.width - width - margin)
        y: below ? view.sel.y + view.sel.height + gap
         : above ? view.sel.y - gap - height
         : view.sel.y + view.sel.height - gap - height
        visible: opacity > 0
        opacity: shown ? 1 : 0

        Fade on opacity {}

        onPicked: action => view.session.run(action)
    }
}
