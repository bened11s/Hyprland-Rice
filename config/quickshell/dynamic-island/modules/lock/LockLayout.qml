pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.modules.services.config
import qs.modules.services.desktop

// Anordnung des Sperrbildschirms: Uhr, Medien-Karte und Desktop-Widgets.
//
// Gespeichert in Config.lock.layout (shell.json):
//
//   { "clock": { "x": 0.5, "y": 0.3,  "size": 1, "hidden": false },
//     "media": { "x": 0.5, "y": 0.92, "size": 1 },
//     "widgets": [ { "id", "type", "x", "y", "size", "opts" } ] }
//
// Widgets wie auf dem Desktop (DesktopWidgets/Plugins, gleicher Datensatz
// ohne "monitor"); sie stehen nur auf dem Hauptmonitor der Sperre und nehmen
// dort keine Eingaben an. Fuer WidgetPicker/WidgetOptions hat LockLayout
// dieselbe Schnittstelle wie Scenes (widgets, adding, addAt, add, patch,
// setOpt, duplicate, remove).
//
// `hidden` blendet Uhr oder Karte aus (im Editor schaltbar). Fehlt es bei der
// Karte, gilt noch der alte Schalter lock.media.
//
// x/y = Mittelpunkt des Elements als Anteil der Bildschirmbreite/-hoehe (wie
// bei den Desktop-Widgets), size = Vergroesserung (0.5 bis 2). Fehlt ein
// Element oder ist das Objekt leer, gilt die Vorgabe – und die ist genau das
// bisherige Bild: Uhr mittig mit der Oberkante bei 20 % der Hoehe, Karte
// mittig 56 px ueber dem unteren Rand. LockScreen fragt darum nicht nach
// Mittelpunkten, sondern nach dem, was es setzt: waagerechter Versatz von
// der Mitte (offsetX), Oberkante (top) und Vergroesserung (scale).
//
// Bearbeiten (LockEditor.qml): `edit()` nimmt eine Kopie als Entwurf, auf
// den set/preview schreiben; LockScreen liest waehrenddessen den Entwurf.
// Jeder Schritt (Loslassen, Pfeiltaste, Zuruecksetzen) landet im Verlauf
// fuer Strg+Z / Strg+Umschalt+Z. Gespeichert wird gesammelt (400 ms),
// `cancel()` stellt den Stand vom Anfang wieder her.
Singleton {
    id: root

    readonly property var names: ["clock", "media"]
    readonly property real minSize: 0.5
    readonly property real maxSize: 2
    // Widgets: gleiche Grenzen wie auf dem Desktop (WidgetOptions.setSize)
    readonly property real widgetMinSize: 0.3
    readonly property real widgetMaxSize: 8
    // Startet ein eigenes Fenster (kitty-Panel) – unter der Sperre unsichtbar
    readonly property var excluded: ["terminal"]

    // Was gilt: beim Bearbeiten der Entwurf, sonst die Einstellung
    readonly property var layout: root.editing ? root.draft : root.stored
    readonly property var stored: root.plain(Config.lock.layout)
    // Uhr/Karte weichen von der Vorgabe ab (Zuruecksetzen betrifft nur sie)
    readonly property bool custom: root.names.some(n => root.layout[n] !== undefined)

    // ---- Aufloesen ----

    function isWidget(name: string): bool {
        return !root.names.includes(name);
    }

    function entry(name: string): var {
        if (root.isWidget(name))
            return root.widget(name);
        const e = root.layout[name];
        return e && typeof e === "object" ? e : null;
    }

    // ---- Widgets ----

    readonly property var widgets: Array.isArray(root.layout.widgets) ? root.layout.widgets : []

    function widget(id: string): var {
        return root.widgets.find(w => w.id === id) ?? null;
    }

    function minOf(name: string): real {
        return root.isWidget(name) ? root.widgetMinSize : root.minSize;
    }

    function maxOf(name: string): real {
        return root.isWidget(name) ? root.widgetMaxSize : root.maxSize;
    }

    // Uhr/Karte ausgeblendet? Ohne eigenen Eintrag gilt fuer die Karte der
    // alte Schalter lock.media
    function hidden(name: string): bool {
        const h = root.entry(name)?.hidden;
        if (h !== undefined)
            return !!h;
        return name === "media" ? !Config.lock.media : false;
    }

    function setHidden(name: string, on: bool): void {
        if (root.isWidget(name))
            return;
        const e = Object.assign({}, root.entry(name) ?? {});
        e.hidden = on;
        root.apply(Object.assign({}, root.draft, { [name]: e }));
    }

    // Wie Scenes: Auswahl zum Hinzufuegen offen, optional an einer Stelle
    property bool adding: false
    property var addAt: null

    function openPicker(at: var): void {
        root.addAt = at ?? null;
        root.adding = true;
    }

    function newId(): string {
        return "w" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
    }

    function withWidgets(list: var): var {
        return Object.assign({}, root.draft, { widgets: list });
    }

    function add(type: string): void {
        if (!root.editing || !DesktopWidgets.info(type) || root.excluded.includes(type))
            return;
        const at = root.addAt;
        const spot = at ?? root.freeSpot();
        const w = {
            id: root.newId(),
            type: type,
            x: Number(spot.x.toFixed(4)),
            y: Number(spot.y.toFixed(4)),
            size: 1,
            opts: DesktopWidgets.defaults(type)
        };
        root.adding = false;
        root.addAt = null;
        root.apply(root.withWidgets([...root.widgets, w]));
        root.selected = w.id;
    }

    // Platz fuer ein neues Widget ohne Rechtsklick-Stelle: der erste Punkt
    // eines groben Rasters (unteres Drittel zuerst, ohne die Mitte unten, wo
    // die Karte steht), der weit genug von allem anderen weg ist
    function freeSpot(): var {
        const taken = root.widgets.map(w => ({ x: w.x, y: w.y }));
        taken.push({ x: 0.5, y: 0.3 }, { x: 0.5, y: 0.93 });
        for (const n of root.names) {
            const e = root.entry(n);
            if (e && isFinite(e.x) && isFinite(e.y))
                taken.push({ x: e.x, y: e.y });
        }
        const rows = [0.62, 0.78, 0.46, 0.3, 0.14];
        const cols = [0.5, 0.25, 0.75, 0.12, 0.88];
        for (const y of rows)
            for (const x of cols)
                if (taken.every(t => Math.hypot((t.x - x) * 1.78, t.y - y) > 0.2))
                    return { x, y };
        return { x: 0.5, y: 0.62 };
    }

    function patch(id: string, changes: var): void {
        const c = Object.assign({}, changes);
        delete c.id;
        delete c.type;
        if (c.size !== undefined)
            c.size = Number(Math.max(root.widgetMinSize, Math.min(root.widgetMaxSize, Number(c.size) || 1)).toFixed(3));
        root.apply(root.withWidgets(root.widgets.map(w => w.id === id ? Object.assign({}, w, c) : w)));
    }

    function setOpt(id: string, key: string, value: var): void {
        root.apply(root.withWidgets(root.widgets.map(w => w.id === id
            ? Object.assign({}, w, { opts: Object.assign({}, w.opts, { [key]: value }) }) : w)));
    }

    function remove(id: string): void {
        if (root.selected === id)
            root.selected = "";
        root.apply(root.withWidgets(root.widgets.filter(w => w.id !== id)));
    }

    function duplicate(id: string): void {
        const w = root.widget(id);
        if (!w)
            return;
        const copy = Object.assign({}, w, {
            id: root.newId(),
            x: Number(Math.min(0.95, w.x + 0.04).toFixed(4)),
            y: Number(Math.min(0.95, w.y + 0.04).toFixed(4)),
            opts: Object.assign({}, w.opts)
        });
        root.apply(root.withWidgets([...root.widgets, copy]));
        root.selected = copy.id;
    }

    function isCustom(name: string): bool {
        return root.entry(name) !== null;
    }

    function scale(name: string): real {
        const s = Number(root.entry(name)?.size);
        return isFinite(s) && s > 0 ? Math.max(root.minOf(name), Math.min(root.maxOf(name), s)) : 1;
    }

    // Versatz des Mittelpunkts von der Bildschirmmitte in px (0 = mittig)
    function offsetX(name: string, width: real): real {
        const x = Number(root.entry(name)?.x);
        return isFinite(x) ? Math.round((x - 0.5) * width) : 0;
    }

    // Oberkante in px; elemHeight = Hoehe des Elements ohne Vergroesserung
    function top(name: string, height: real, elemHeight: real): real {
        const y = Number(root.entry(name)?.y);
        if (isFinite(y))
            return Math.round(y * height - elemHeight / 2);
        return name === "media" ? height - elemHeight - 56 : Math.round(height * 0.2);
    }

    // ---- Bearbeiten ----

    property bool editing: false
    property string editScreen: ""
    property string selected: ""

    property var draft: ({})
    // Stand beim Start (Abbrechen) und zuletzt festgehaltener Stand (Verlauf)
    property string origin: ""
    property string committed: ""
    property var undoStack: []
    property var redoStack: []
    readonly property bool canUndo: root.undoStack.length > 0
    readonly property bool canRedo: root.redoStack.length > 0

    function plain(v: var): var {
        if (!v || typeof v !== "object")
            return {};
        try {
            return JSON.parse(JSON.stringify(v));
        } catch (e) {
            return {};
        }
    }

    function edit(screenName: string): void {
        if (root.editing)
            return;
        root.draft = root.stored;
        root.origin = JSON.stringify(root.draft);
        root.committed = root.origin;
        root.undoStack = [];
        root.redoStack = [];
        root.selected = "";
        root.adding = false;
        root.addAt = null;
        root.editScreen = screenName || (Hyprland.focusedMonitor?.name ?? "");
        root.editing = true;
    }

    // Erst speichern, dann umschalten: `layout` springt so direkt auf den
    // neuen Stand, nicht kurz auf den alten
    function done(): void {
        if (!root.editing)
            return;
        root.selected = "";
        root.adding = false;
        root.flush();
        root.editing = false;
    }

    // Alles seit dem Start verwerfen
    function cancel(): void {
        if (!root.editing)
            return;
        root.draft = JSON.parse(root.origin);
        root.selected = "";
        root.adding = false;
        root.flush();
        root.editing = false;
    }

    function toggleEdit(screenName: string): void {
        if (root.editing)
            root.done();
        else
            root.edit(screenName);
    }

    // Lage und Groesse bereinigt; alles andere des Eintrags (hidden, bei
    // Widgets id/type/opts) bleibt
    function clean(name: string, e: var): var {
        const out = Object.assign({}, root.entry(name) ?? {});
        for (const k of ["x", "y"]) {
            const v = Number(e?.[k]);
            if (isFinite(v))
                out[k] = Number(Math.max(0, Math.min(1, v)).toFixed(4));
        }
        const s = Number(e?.size);
        out.size = isFinite(s) && s > 0 ? Number(Math.max(root.minOf(name), Math.min(root.maxOf(name), s)).toFixed(3)) : 1;
        return out;
    }

    function withEntry(name: string, e: var): var {
        const c = root.clean(name, e);
        if (root.isWidget(name))
            return root.withWidgets(root.widgets.map(w => w.id === name ? c : w));
        return Object.assign({}, root.draft, { [name]: c });
    }

    // Waehrend des Ziehens: nur anzeigen, nicht festhalten
    function preview(name: string, e: var): void {
        if (!root.editing)
            return;
        root.draft = root.withEntry(name, e);
    }

    // Festhalten: in den Verlauf, gesammelt speichern
    function set(name: string, e: var): void {
        root.apply(root.withEntry(name, e));
    }

    // Uhr und Karte auf die Vorgabe; Widgets bleiben
    function reset(): void {
        root.apply(root.widgets.length > 0 ? { widgets: root.widgets } : {});
    }

    function apply(next: var): void {
        if (!root.editing)
            return;
        const text = JSON.stringify(next);
        if (text === root.committed) {
            root.draft = next;
            return;
        }
        root.undoStack = [...root.undoStack, root.committed];
        root.redoStack = [];
        root.draft = next;
        root.committed = text;
        saveDelay.restart();
    }

    function undo(): void {
        if (!root.canUndo)
            return;
        const text = root.undoStack[root.undoStack.length - 1];
        root.undoStack = root.undoStack.slice(0, -1);
        root.redoStack = [...root.redoStack, root.committed];
        root.restore(text);
    }

    function redo(): void {
        if (!root.canRedo)
            return;
        const text = root.redoStack[root.redoStack.length - 1];
        root.redoStack = root.redoStack.slice(0, -1);
        root.undoStack = [...root.undoStack, root.committed];
        root.restore(text);
    }

    function restore(text: string): void {
        root.draft = JSON.parse(text);
        root.committed = text;
        saveDelay.restart();
    }

    function flush(): void {
        saveDelay.stop();
        if (JSON.stringify(root.draft) !== JSON.stringify(root.stored))
            Config.set("lock", "layout", root.draft);
    }

    Timer {
        id: saveDelay

        interval: 400
        onTriggered: root.flush()
    }
}
