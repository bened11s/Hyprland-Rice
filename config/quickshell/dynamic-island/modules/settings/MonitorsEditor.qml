pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.hypr
import qs.modules.widgets

// Einstellungsseite Monitore (Config.meta editor "monitors").
//
// Oben die Anordnung: jeder Monitor als Kaertchen in seiner logischen
// Groesse (Pixel / Skalierung, gedreht bei 90/270), ziehbar; beim Loslassen
// rastet er an den Kanten der Nachbarn ein und liegt nie auf einem anderen.
// Klick waehlt. Darunter die Werte des gewaehlten Monitors als Zeilen:
// Aktiv, Aufloesung, Bildwiederholrate, Skalierung, Drehung, VRR, Spiegeln.
// Die Leiste darunter erscheint nur bei ausstehenden Aenderungen (Verwerfen,
// Uebernehmen), einem Fehler oder der Rueckfrage "Einstellungen behalten?"
// (15 s nach dem Uebernehmen, Monitors.qml dreht sonst zurueck).
//
// Aenderungen sammeln sich in `pending` je Portname und werden erst mit
// Uebernehmen als Regeln (hl.monitor) an Hyprland gegeben.
Item {
    id: editor

    implicitHeight: content.implicitHeight

    // ---- Zustand ----
    property string selectedName: ""
    // { [name]: { w, h, hz, x, y, scale, transform, vrr, disabled, mirror } }
    // – nur die Felder, die vom gemeldeten Stand abweichen
    property var pending: ({})

    readonly property var monitors: Monitors.monitors
    readonly property var selected: editor.monitors.find(m => m.name === editor.selectedName)
                                    ?? editor.monitors.find(m => m.focused)
                                    ?? editor.monitors[0] ?? null
    readonly property var current: editor.selected ? editor.effective(editor.selected) : null
    readonly property int changeCount: Object.keys(editor.pending).length
    readonly property bool dirty: editor.changeCount > 0
    readonly property bool locked: Monitors.confirming || Monitors.busy

    readonly property var scaleChoices: [1, 1.25, 1.5, 1.6, 2]
    // Werte des gewaehlten Monitors bedienbar?
    readonly property bool editable: !editor.locked && !(editor.current?.disabled ?? false)
    // Ausgeschaltete Monitore fehlen in der Anordnung – dann braucht es den Waehler im Kopf
    readonly property bool needsPicker: editor.monitors.some(m => editor.effective(m).disabled)

    // Nach dem Behalten/Zuruecksetzen ist alles im gemeldeten Stand
    Connections {
        target: Monitors

        function onAppliedChanged(): void {
            editor.pending = {};
        }
    }

    Component.onCompleted: Monitors.refresh()

    // ---- Werte ----

    // Gemeldeter Stand + ausstehende Aenderungen eines Monitors
    function effective(m: var): var {
        const p = editor.pending[m.name] ?? {};
        const out = {
            name: m.name,
            w: p.w ?? m.width,
            h: p.h ?? m.height,
            hz: p.hz ?? m.refresh,
            x: p.x ?? m.x,
            y: p.y ?? m.y,
            scale: p.scale ?? m.scale,
            transform: p.transform ?? m.transform,
            vrr: p.vrr ?? m.vrrMode,
            disabled: p.disabled ?? m.disabled,
            mirror: p.mirror ?? m.mirrorOf
        };
        const rot = out.transform % 2 === 1;
        out.lw = Math.round((rot ? out.h : out.w) / out.scale);
        out.lh = Math.round((rot ? out.w : out.h) / out.scale);
        return out;
    }

    function set(name: string, patch: var): void {
        const m = editor.monitors.find(x => x.name === name);
        if (!m)
            return;
        const base = { w: m.width, h: m.height, hz: m.refresh, x: m.x, y: m.y, scale: m.scale, transform: m.transform, vrr: m.vrrMode, disabled: m.disabled, mirror: m.mirrorOf };
        const next = Object.assign({}, editor.pending);
        const entry = Object.assign({}, next[name] ?? {}, patch);
        for (const k of Object.keys(entry))
            if (entry[k] === base[k])
                delete entry[k];
        if (Object.keys(entry).length === 0)
            delete next[name];
        else
            next[name] = entry;
        editor.pending = next;
    }

    function discard(): void {
        editor.pending = {};
    }

    // Hyprland will ganzzahlige logische Groessen – sonst nimmt es den
    // naechsten Wert in 1/120-Schritten
    function cleanScale(w: int, h: int, s: real): bool {
        return Math.abs(w / s - Math.round(w / s)) < 0.0001 && Math.abs(h / s - Math.round(h / s)) < 0.0001;
    }

    function nearestScale(w: int, h: int, s: real): real {
        if (editor.cleanScale(w, h, s))
            return s;
        const base = Math.round(s * 120);
        for (let i = 1; i < 120; i++) {
            for (const k of [base + i, base - i]) {
                if (k < 60)
                    continue;
                if (editor.cleanScale(w, h, k / 120))
                    return Math.round(k / 120 * 1000) / 1000;
            }
        }
        return s;
    }

    function stepScale(d: real): void {
        editor.set(editor.selected.name, { scale: Math.max(0.5, Math.min(4, Math.round((editor.current.scale + d) * 100) / 100)) });
    }

    function scaleLabel(s: real): string {
        return (Math.round(s * 100) / 100).toString().replace(".", ",") + "×";
    }

    // Wie viele Monitore nach den Aenderungen an sind
    readonly property int enabledCount: editor.monitors.filter(m => !editor.effective(m).disabled).length

    // ---- Uebernehmen ----

    function applyPending(): void {
        const specs = [];
        const previous = [];
        for (const name of Object.keys(editor.pending)) {
            const m = editor.monitors.find(x => x.name === name);
            if (!m)
                continue;
            const v = editor.effective(m);
            previous.push(Monitors.snapshot(m));
            if (v.disabled) {
                specs.push({ output: m.key, disabled: true });
                continue;
            }
            const p = editor.pending[name];
            const spec = {
                output: m.key,
                mode: Monitors.modeLabel(v.w, v.h, v.hz),
                // Frisch eingeschaltet ohne Platz: Hyprland setzt ihn daneben
                position: m.disabled && p.x === undefined && p.y === undefined ? "auto" : `${v.x}x${v.y}`,
                scale: v.scale,
                transform: v.transform,
                vrr: v.vrr
            };
            if (v.mirror !== "")
                spec.mirror = v.mirror;
            specs.push(spec);
        }
        Monitors.apply(specs, [], previous);
    }

    function resetSelected(): void {
        const m = editor.selected;
        if (!m)
            return;
        const next = Object.assign({}, editor.pending);
        delete next[m.name];
        editor.pending = next;
        Monitors.apply([], [m.key], [Monitors.snapshot(m)]);
    }

    // ---- Anordnung (logische Pixel) ----

    readonly property var rects: {
        const out = [];
        for (const m of editor.monitors) {
            const v = editor.effective(m);
            if (v.disabled)
                continue;
            out.push({ name: m.name, x: v.x, y: v.y, w: v.lw, h: v.lh });
        }
        return out;
    }

    // Einrasten an Nachbarkanten, Ueberlappung aufloesen, Kontakt halten
    function place(name: string, lx: real, ly: real, snap: real): point {
        const me = editor.rects.find(r => r.name === name);
        if (!me)
            return Qt.point(Math.round(lx), Math.round(ly));
        const others = editor.rects.filter(r => r.name !== name);
        let x = lx, y = ly;
        let bestX = snap, bestY = snap, sx = null, sy = null;
        for (const o of others) {
            for (const cx of [o.x - me.w, o.x + o.w, o.x, o.x + o.w - me.w]) {
                const d = Math.abs(cx - x);
                if (d < bestX) {
                    bestX = d;
                    sx = cx;
                }
            }
            for (const cy of [o.y - me.h, o.y + o.h, o.y, o.y + o.h - me.h]) {
                const d = Math.abs(cy - y);
                if (d < bestY) {
                    bestY = d;
                    sy = cy;
                }
            }
        }
        if (sx !== null)
            x = sx;
        if (sy !== null)
            y = sy;
        // Aus Nachbarn herausschieben, immer die kuerzeste Strecke
        for (let i = 0; i < 6; i++) {
            let moved = false;
            for (const o of others) {
                const ox = Math.min(x + me.w, o.x + o.w) - Math.max(x, o.x);
                const oy = Math.min(y + me.h, o.y + o.h) - Math.max(y, o.y);
                if (ox <= 0 || oy <= 0)
                    continue;
                const left = x + me.w - o.x, right = o.x + o.w - x, up = y + me.h - o.y, down = o.y + o.h - y;
                const min = Math.min(left, right, up, down);
                if (min === left)
                    x = o.x - me.w;
                else if (min === right)
                    x = o.x + o.w;
                else if (min === up)
                    y = o.y - me.h;
                else
                    y = o.y + o.h;
                moved = true;
            }
            if (!moved)
                break;
        }
        // Ohne Kontakt kaeme der Zeiger nicht hinueber: an die naechste Kante
        if (others.length > 0 && !editor.touching(x, y, me, others)) {
            let best = null, bestD = Infinity;
            const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
            for (const o of others) {
                const cands = [
                    { x: o.x - me.w, y: clamp(y, o.y - me.h + 1, o.y + o.h - 1) },
                    { x: o.x + o.w, y: clamp(y, o.y - me.h + 1, o.y + o.h - 1) },
                    { x: clamp(x, o.x - me.w + 1, o.x + o.w - 1), y: o.y - me.h },
                    { x: clamp(x, o.x - me.w + 1, o.x + o.w - 1), y: o.y + o.h }
                ];
                for (const c of cands) {
                    const d = Math.hypot(c.x - x, c.y - y);
                    if (d < bestD && !others.some(p => p !== o && editor.overlaps(c.x, c.y, me, p))) {
                        bestD = d;
                        best = c;
                    }
                }
            }
            if (best) {
                x = best.x;
                y = best.y;
            }
        }
        return Qt.point(Math.round(x), Math.round(y));
    }

    function overlaps(x: real, y: real, me: var, o: var): bool {
        return Math.min(x + me.w, o.x + o.w) - Math.max(x, o.x) > 0 && Math.min(y + me.h, o.y + o.h) - Math.max(y, o.y) > 0;
    }

    function touching(x: real, y: real, me: var, others: var): bool {
        for (const o of others) {
            const vo = Math.min(y + me.h, o.y + o.h) - Math.max(y, o.y) > 0;
            const ho = Math.min(x + me.w, o.x + o.w) - Math.max(x, o.x) > 0;
            if (vo && (x + me.w === o.x || o.x + o.w === x))
                return true;
            if (ho && (y + me.h === o.y || o.y + o.h === y))
                return true;
        }
        return false;
    }

    // ---- Bausteine ----

    // Knopf: Text oder ein einzelnes Symbol
    component ActionButton: Rectangle {
        id: button

        property string icon: ""
        property string label: ""
        property bool filled: false
        signal clicked()

        implicitWidth: button.icon !== "" ? 30 : buttonLabel.implicitWidth + 28
        implicitHeight: 30
        radius: 8
        opacity: enabled ? 1 : 0.4
        color: button.filled ? (buttonHover.hovered ? Colors.alpha(Colors.primary, 0.85) : Colors.primary)
             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
             : Colors.alpha(Colors.fgSurface, 0.06)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
        Fade on opacity {}

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: button.icon !== "" ? button.icon : button.label
            color: button.filled ? Colors.fgPrimary : Colors.fgSurface
            font.family: button.icon !== "" ? "Material Symbols Outlined" : Config.font
            font.pixelSize: button.icon !== "" ? 16 : 12
            font.weight: button.filled ? Font.DemiBold : Font.Normal
        }

        HoverHandler {
            id: buttonHover

            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: button.enabled
            onTapped: button.clicked()
        }
    }

    // Schalter wie in SettingsRow
    component Toggle: Rectangle {
        id: sw

        property bool checked: false
        signal toggled()

        width: 40
        height: 22
        radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: sw.checked ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.18)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            color: sw.checked ? Colors.fgPrimary : Colors.fgSurfaceVariant

            Morph on x {}
        }

        HoverHandler {
            cursorShape: sw.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: sw.enabled
            onTapped: sw.toggled()
        }
    }

    // Eine Zeile der Liste: Titel (+ Hinweis) links, Bedienelement rechts
    component Field: Item {
        id: field

        property string title: ""
        property string note: ""
        default property alias content: fieldControls.data

        width: parent.width
        implicitHeight: field.note !== "" ? 52 : 44

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 14
                rightMargin: 14
            }
            height: 1
            color: Colors.alpha(Colors.outline, 0.14)
        }

        Column {
            anchors {
                left: parent.left
                leftMargin: 14
                right: fieldControls.left
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 2
            opacity: field.enabled ? 1 : 0.4

            Text {
                width: parent.width
                text: field.title
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: field.note !== ""
                text: field.note
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Row {
            id: fieldControls

            anchors {
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            spacing: 6
        }
    }

    // ---- Seite ----

    Column {
        id: content

        // Die Seite bekommt die volle Fensterbreite – Zeilen werden darueber zu lang
        width: Math.min(parent.width, 820)
        spacing: 12

        // ---- Anordnung ----
        Rectangle {
            id: canvasCard

            width: parent.width
            height: 190
            radius: 16
            color: Colors.alpha(Colors.fgSurface, 0.035)
            border.width: 1
            border.color: Colors.alpha(Colors.outline, 0.14)
            clip: true

            // Leer: nichts gemeldet
            Text {
                anchors.centerIn: parent
                visible: editor.monitors.length === 0
                text: Monitors.loaded ? I18n.tr("Keine Monitore gemeldet") : I18n.tr("Lese Monitore …")
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 12
            }

            Item {
                id: canvas

                anchors {
                    fill: parent
                    topMargin: 12
                    bottomMargin: 12
                    leftMargin: 24
                    rightMargin: 24
                }

                // Massstab: alle Monitore in die Flaeche, Ursprung = Rand der Gesamtflaeche
                readonly property var bounds: {
                    const rs = editor.rects;
                    if (rs.length === 0)
                        return { x: 0, y: 0, w: 1, h: 1 };
                    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
                    for (const r of rs) {
                        x0 = Math.min(x0, r.x);
                        y0 = Math.min(y0, r.y);
                        x1 = Math.max(x1, r.x + r.w);
                        y1 = Math.max(y1, r.y + r.h);
                    }
                    return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
                }
                // Etwas Luft, damit Ziehen ueber den Rand hinaus sichtbar bleibt
                readonly property real factor: Math.min((canvas.width - 40) / (canvas.bounds.w + canvas.bounds.w * 0.25),
                                                        (canvas.height - 20) / (canvas.bounds.h + canvas.bounds.h * 0.25))
                readonly property real ox: (canvas.width - canvas.bounds.w * canvas.factor) / 2 - canvas.bounds.x * canvas.factor
                readonly property real oy: (canvas.height - canvas.bounds.h * canvas.factor) / 2 - canvas.bounds.y * canvas.factor

                // Logische Zielposition eines Monitors aus seinem Zug (eingerastet)
                function dropPoint(name: string, baseX: real, baseY: real, tx: real, ty: real): point {
                    return editor.place(name, baseX + tx / canvas.factor, baseY + ty / canvas.factor, 18 / canvas.factor);
                }

                Repeater {
                    model: editor.rects

                    Item {
                        id: block

                        required property var modelData
                        readonly property string name: block.modelData.name
                        readonly property var mon: editor.monitors.find(m => m.name === block.name) ?? null
                        readonly property var vals: block.mon ? editor.effective(block.mon) : null
                        readonly property bool selected: editor.selected?.name === block.name
                        readonly property bool dragging: drag.active
                        // Logische Zielposition waehrend des Ziehens (schon eingerastet)
                        readonly property point live: block.dragging
                            ? canvas.dropPoint(block.name, block.modelData.x, block.modelData.y, drag.translation.x, drag.translation.y)
                            : Qt.point(block.modelData.x, block.modelData.y)

                        x: canvas.ox + block.live.x * canvas.factor
                        y: canvas.oy + block.live.y * canvas.factor
                        width: Math.max(8, block.modelData.w * canvas.factor)
                        height: Math.max(8, block.modelData.h * canvas.factor)
                        z: block.dragging ? 2 : block.selected ? 1 : 0

                        Behavior on x {
                            enabled: !block.dragging
                            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                        }
                        Behavior on y {
                            enabled: !block.dragging
                            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 10
                            color: block.selected ? Colors.alpha(Colors.primary, block.dragging ? 0.32 : 0.22)
                                 : blockHover.hovered ? Colors.alpha(Colors.fgSurface, 0.14)
                                 : Colors.alpha(Colors.fgSurface, 0.08)
                            border.width: block.selected ? 2 : 1
                            border.color: block.selected ? Colors.primary : Colors.alpha(Colors.outline, 0.5)

                            Behavior on color {
                                ColorAnimation { duration: Appearance.fadeDuration }
                            }
                            Behavior on border.color {
                                ColorAnimation { duration: Appearance.fadeDuration }
                            }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                spacing: 1

                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 4

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: block.mon?.focused ?? false
                                        text: "star"
                                        color: block.selected ? Colors.primary : Colors.fgSurface
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: block.name
                                        color: block.selected ? Colors.primary : Colors.fgSurface
                                        font.family: Config.font
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: (block.vals?.transform ?? 0) % 2 === 1
                                        text: "screen_rotation"
                                        color: Colors.fgSurfaceVariant
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, parent.width)
                                    visible: block.height > 54
                                    text: block.mon?.short ?? ""
                                    color: Colors.fgSurfaceVariant
                                    font.family: Config.font
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: block.height > 70
                                    text: block.vals ? `${block.vals.lw} × ${block.vals.lh}` : ""
                                    color: Colors.fgSurfaceVariant
                                    font.family: Config.font
                                    font.pixelSize: 10
                                }
                            }

                            // Punkt: Aenderung ausstehend
                            Rectangle {
                                anchors {
                                    right: parent.right
                                    top: parent.top
                                    margins: 7
                                }
                                width: 7
                                height: 7
                                radius: 3.5
                                visible: editor.pending[block.name] !== undefined
                                color: Colors.tertiary
                            }
                        }

                        HoverHandler {
                            id: blockHover

                            cursorShape: block.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        }

                        TapHandler {
                            onTapped: editor.selectedName = block.name
                        }

                        DragHandler {
                            id: drag

                            // Letzter Zug – beim Loslassen ist `translation`
                            // je nach Qt-Stand schon zurueckgesetzt
                            property point last: Qt.point(0, 0)

                            target: null
                            onTranslationChanged: if (drag.active) drag.last = Qt.point(drag.translation.x, drag.translation.y)
                            onActiveChanged: {
                                if (drag.active) {
                                    drag.last = Qt.point(0, 0);
                                    editor.selectedName = block.name;
                                    return;
                                }
                                // Nicht ueber `live`: das zeigt nach dem Loslassen
                                // schon wieder den alten Platz
                                const p = canvas.dropPoint(block.name, block.modelData.x, block.modelData.y, drag.last.x, drag.last.y);
                                editor.set(block.name, { x: p.x, y: p.y });
                            }
                        }
                    }
                }
            }
        }

        // ---- Details ----
        Rectangle {
            width: parent.width
            visible: editor.selected !== null
            implicitHeight: rows.implicitHeight
            radius: 16
            color: Colors.alpha(Colors.fgSurface, 0.035)
            border.width: 1
            border.color: Colors.alpha(Colors.outline, 0.14)

            Column {
                id: rows

                width: parent.width

                // Kopf: Modell + Anschluss, rechts Menue und Aktiv
                Item {
                    width: parent.width
                    implicitHeight: 56

                    Column {
                        anchors {
                            left: parent.left
                            leftMargin: 14
                            right: head.left
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 2

                        Text {
                            width: parent.width
                            text: editor.selected?.short ?? ""
                            color: Colors.fgBackground
                            font.family: Config.font
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: text !== (editor.selected?.short ?? "")
                            text: editor.selected?.name ?? ""
                            color: Colors.fgSurfaceVariant
                            font.family: Config.font
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: head

                        anchors {
                            right: parent.right
                            rightMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        SettingsDropdown {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: editor.needsPicker
                            width: implicitWidth
                            maxWidth: 180
                            options: editor.monitors.map(m => m.name)
                            current: editor.selected?.name
                            onPicked: v => editor.selectedName = v
                        }

                        SettingsMenuButton {
                            anchors.verticalCenter: parent.verticalCenter
                            entries: [
                                { text: I18n.tr("Standard wiederherstellen"), icon: "restart_alt", enabled: !editor.locked, action: () => editor.resetSelected() },
                                { text: I18n.tr("Neu lesen"), icon: "refresh", enabled: !Monitors.busy, action: () => Monitors.refresh() }
                            ]
                        }

                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: !(editor.current?.disabled ?? false)
                            // Der letzte aktive Monitor bleibt an
                            enabled: !editor.locked && (checked ? editor.enabledCount > 1 : true)
                            onToggled: editor.set(editor.selected.name, { disabled: !editor.current.disabled })
                        }
                    }
                }

                Field {
                    title: I18n.tr("Auflösung")
                    enabled: editor.editable

                    SettingsDropdown {
                        width: implicitWidth
                        options: (editor.selected?.resolutions ?? []).map(r => r.label)
                        current: editor.current
                                 ? (editor.selected.resolutions.find(r => r.w === editor.current.w && r.h === editor.current.h)?.label
                                    ?? `${editor.current.w}x${editor.current.h}`)
                                 : undefined
                        onPicked: v => {
                            const r = editor.selected.resolutions.find(x => x.label === v);
                            if (!r)
                                return;
                            // Rate behalten, wenn die Aufloesung sie bietet, sonst die hoechste
                            const hz = r.rates.includes(editor.current.hz) ? editor.current.hz : r.rates[0];
                            editor.set(editor.selected.name, { w: r.w, h: r.h, hz });
                        }
                    }
                }

                Field {
                    id: rateField

                    readonly property var rates: {
                        const r = editor.selected?.resolutions.find(x => x.w === editor.current?.w && x.h === editor.current?.h);
                        return r ? r.rates : (editor.current ? [editor.current.hz] : []);
                    }

                    title: I18n.tr("Bildwiederholrate")
                    enabled: editor.editable

                    SettingsDropdown {
                        width: implicitWidth
                        options: rateField.rates
                        current: editor.current
                                 ? (rateField.rates.find(r => Math.abs(r - editor.current.hz) < 0.5) ?? editor.current.hz)
                                 : undefined
                        labelOf: v => Monitors.hzLabel(v) + " Hz"
                        onPicked: v => editor.set(editor.selected.name, { hz: v })
                    }
                }

                Field {
                    title: I18n.tr("Skalierung")
                    enabled: editor.editable
                    note: editor.current && !editor.cleanScale(editor.current.w, editor.current.h, editor.current.scale)
                          ? I18n.tr("Ergibt keine ganzen Pixel – Hyprland nimmt %1").arg(editor.scaleLabel(editor.nearestScale(editor.current.w, editor.current.h, editor.current.scale)))
                          : ""

                    ActionButton {
                        icon: "remove"
                        onClicked: editor.stepScale(-0.05)
                    }

                    SettingsDropdown {
                        width: implicitWidth
                        options: editor.scaleChoices
                        current: editor.current?.scale
                        labelOf: v => editor.scaleLabel(v)
                        onPicked: v => editor.set(editor.selected.name, { scale: v })
                    }

                    ActionButton {
                        icon: "add"
                        onClicked: editor.stepScale(0.05)
                    }
                }

                Field {
                    title: I18n.tr("Drehung")
                    enabled: editor.editable

                    SettingsDropdown {
                        width: implicitWidth
                        options: [0, 1, 2, 3]
                        current: editor.current ? editor.current.transform % 4 : undefined
                        labelOf: v => v * 90 + "°"
                        onPicked: v => editor.set(editor.selected.name, { transform: v + (editor.current.transform >= 4 ? 4 : 0) })
                    }
                }

                Field {
                    title: I18n.tr("Gespiegelt")
                    enabled: editor.editable

                    Toggle {
                        checked: (editor.current?.transform ?? 0) >= 4
                        onToggled: editor.set(editor.selected.name, { transform: (editor.current.transform + 4) % 8 })
                    }
                }

                Field {
                    title: I18n.tr("Variable Bildrate (VRR)")
                    enabled: editor.editable

                    SettingsDropdown {
                        width: implicitWidth
                        options: [0, 1, 2]
                        current: editor.current?.vrr
                        labelOf: v => [I18n.tr("Aus"), I18n.tr("An"), I18n.tr("Nur Vollbild")][v] ?? String(v)
                        onPicked: v => editor.set(editor.selected.name, { vrr: v })
                    }
                }

                Field {
                    title: I18n.tr("Spiegeln")
                    visible: editor.monitors.length > 1
                    enabled: editor.editable

                    SettingsDropdown {
                        width: implicitWidth
                        options: [""].concat(editor.monitors.filter(m => m.name !== editor.selected?.name).map(m => m.name))
                        current: editor.current?.mirror ?? ""
                        labelOf: v => v === "" ? I18n.tr("Nein") : v
                        onPicked: v => editor.set(editor.selected.name, { mirror: v })
                    }
                }
            }
        }

        // ---- Leiste: Aenderungen / Fehler / Behalten? ----
        Rectangle {
            id: bar

            width: parent.width
            height: 48
            radius: 14
            visible: editor.dirty || Monitors.confirming || Monitors.busy || Monitors.lastError !== ""
            color: Monitors.confirming ? Colors.alpha(Colors.primary, 0.12)
                 : Monitors.lastError !== "" ? Colors.alpha(Colors.error, 0.1)
                 : Colors.alpha(Colors.fgSurface, 0.035)
            border.width: 1
            border.color: Monitors.confirming ? Colors.alpha(Colors.primary, 0.4)
                        : Monitors.lastError !== "" ? Colors.alpha(Colors.error, 0.4)
                        : Colors.alpha(Colors.outline, 0.14)

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    right: buttons.left
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                elide: Text.ElideRight
                text: Monitors.confirming
                    ? I18n.tr("Einstellungen behalten? Zurück in %1 s").arg(Monitors.countdown)
                    : Monitors.lastError !== "" ? Monitors.lastError
                    : Monitors.busy ? I18n.tr("Wird angewendet …")
                    : I18n.tr("Nicht übernommene Änderungen")
                color: Monitors.lastError !== "" && !Monitors.confirming ? Colors.error : Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Monitors.confirming ? Font.DemiBold : Font.Normal
            }

            Row {
                id: buttons

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    rightMargin: 10
                }
                spacing: 8

                ActionButton {
                    visible: !Monitors.confirming && editor.dirty
                    label: I18n.tr("Verwerfen")
                    enabled: !Monitors.busy
                    onClicked: editor.discard()
                }

                ActionButton {
                    visible: !Monitors.confirming && editor.dirty
                    label: I18n.tr("Übernehmen")
                    filled: true
                    enabled: !Monitors.busy
                    onClicked: editor.applyPending()
                }

                ActionButton {
                    visible: Monitors.confirming
                    label: I18n.tr("Zurücksetzen")
                    onClicked: Monitors.revert()
                }

                ActionButton {
                    visible: Monitors.confirming
                    label: I18n.tr("Behalten")
                    filled: true
                    onClicked: Monitors.keep()
                }
            }

            // Restzeit als Linie am unteren Rand
            Rectangle {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    leftMargin: 14
                    bottomMargin: 4
                }
                height: 2
                radius: 1
                visible: Monitors.confirming
                width: (bar.width - 28) * Monitors.countdown / Monitors.confirmSeconds
                color: Colors.primary

                Behavior on width {
                    NumberAnimation { duration: 900 }
                }
            }
        }
    }
}
