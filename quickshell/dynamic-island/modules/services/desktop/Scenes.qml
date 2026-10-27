pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.modules.services.wallpaper

import qs

// Desktop-Widgets je Wallpaper ("Szenen").
//
// Datei: ~/.config/dynamic-island/scenes.json (im Dotfiles-Repo, wandert per
// chezmoi auf den Laptop mit)
//
//   { "version": 1, "scenes": {
//       "*":                     [ … ],   ueberall, wo nichts Genaueres steht
//       "Miku/":                 [ … ],   alle Bilder im Ordner Miku
//       "Miku/wallhaven-zp85do_2560x1440.png": [ … ]  genau dieses Bild
//   } }
//
// Schluessel sind relativ zum Wallpaper-Ordner, damit sie auf jedem Rechner
// passen. Gesucht wird vom Genauen zum Allgemeinen: Bild, Ordner (auch
// Elternordner), "*". Eine leere Liste ist eine echte Szene ("hier keine
// Widgets") und haelt die Suche an.
//
// Ein Widget:
//   { "id": "w…", "type": "clock", "x": 0.5, "y": 0.3, "size": 1,
//     "monitor": "*" | "<name>", "opts": { "style": "gestapelt", "color": "hell" } }
// x/y = Mittelpunkt als Anteil der Bildschirmbreite/-hoehe, size skaliert die
// Grundeinheit (16 px bei 1440p). Typen: DesktopWidgets.qml.
//
// Die Szene folgt Wallpapers.current – also auch der Vorschau beim Blaettern
// in der Wallpaper-Auswahl.
Singleton {
    id: root

    // DYNAMIC_ISLAND_SCENES_FILE: andere Datei (Tests mit einer Kopie der Shell)
    readonly property string path: Quickshell.env("DYNAMIC_ISLAND_SCENES_FILE")
                                   || Quickshell.env("HOME") + "/.config/dynamic-island/scenes.json"
    readonly property string wallsDir: Wallpapers.wallsDir

    property var data: ({ version: 1, scenes: {} })
    readonly property var scenes: root.data.scenes ?? {}

    // ---- Aufloesung ----

    function relOf(path: string): string {
        const prefix = root.wallsDir + "/";
        return path.startsWith(prefix) ? path.slice(prefix.length) : "";
    }

    // Kandidaten vom Genauen zum Allgemeinen
    function chainFor(path: string): var {
        const rel = root.relOf(path);
        const out = [];
        if (rel !== "") {
            out.push(rel);
            const parts = rel.split("/");
            for (let i = parts.length - 1; i > 0; i--)
                out.push(parts.slice(0, i).join("/") + "/");
        }
        out.push("*");
        return out;
    }

    function keyFor(path: string): string {
        for (const key of root.chainFor(path))
            if (Array.isArray(root.scenes[key]))
                return key;
        return "";
    }

    readonly property string wallpaper: Wallpapers.current
    readonly property string currentKey: root.keyFor(root.wallpaper)

    // Was gerade zu sehen ist: beim Bearbeiten die Szene des Ziels
    readonly property string shownKey: root.editing ? root.target : root.currentKey
    readonly property var widgets: root.scenes[root.shownKey] ?? []

    // Auf einen Monitor festgelegte Widgets duerfen ueber dessen Rand ragen
    // (halb links, halb rechts) – der Nachbar zeichnet sie dann mit. Ob sie
    // hinueberreichen, sagt ihre Groesse in px, die der Host auf dem eigenen
    // Monitor meldet (`extents`), beim Ziehen/Skalieren `live`
    function widgetsFor(screenName: string): var {
        const own = root.screenNamed(screenName);
        return root.widgets.filter(w => {
            if (!w.monitor || w.monitor === "*")
                return true;
            const home = root.homeOf(w);
            if (home?.name === screenName || root.live?.id === w.id)
                return true;
            const e = root.extents[w.id];
            if (!own || !home || !e)
                return false;
            const gx = home.x + w.x * home.width, gy = home.y + w.y * home.height;
            return gx + e.w / 2 > own.x && gx - e.w / 2 < own.x + own.width
                   && gy + e.h / 2 > own.y && gy - e.h / 2 < own.y + own.height;
        });
    }

    // Monitor eines festgelegten Widgets. Gibt es ihn nicht (anderer Rechner,
    // Anschluss umbenannt), der erste – sonst waere das Widget unsichtbar
    function homeOf(w: var): var {
        return root.screenNamed(w?.monitor ?? "") ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
    }

    function screenNamed(name: string): var {
        for (const s of Quickshell.screens)
            if (s.name === name)
                return s;
        return null;
    }

    // { <id>: { w, h } } in px (WidgetHost.report)
    property var extents: ({})

    function setExtent(id: string, w: real, h: real): void {
        const e = root.extents[id];
        if (e && e.w === w && e.h === h)
            return;
        root.extents = Object.assign({}, root.extents, { [id]: { w: w, h: h } });
    }

    // ---- Bearbeiten ----

    property bool editing: false
    property string editScreen: ""
    property string target: ""
    property string selected: ""
    // Widget-Auswahl offen (WidgetPicker; Esc/Klick ins Leere schliesst).
    // `addAt`: per Rechtsklick an einer Stelle geoeffnet – { x, y } als
    // Anteil des Bildschirms, das neue Widget kommt genau dorthin. null =
    // ueber die Leiste geoeffnet, Platz sucht `place`.
    property bool adding: false
    property var addAt: null

    onAddingChanged: if (!root.adding) root.addAt = null

    function openPicker(at: var): void {
        root.addAt = at ?? null;
        root.adding = true;
    }
    readonly property var selectedWidget: root.widgets.find(w => w.id === root.selected) ?? null

    // Ein Widget wird gerade gezogen oder skaliert: { id, gx, gy, rx, ry,
    // size } – Mittelpunkt in globalen px bzw. als Anteil des Monitors darunter.
    // Seine Kopien auf den anderen Monitoren folgen damit live (WidgetHost):
    // festgelegte ueber gx/gy, "*"-Widgets an derselben relativen Stelle
    property var live: null

    // Wohin Aenderungen gehen koennen: [{ key, label, own }]
    readonly property var targets: {
        const out = [];
        const rel = root.relOf(root.wallpaper);
        for (const key of root.chainFor(root.wallpaper)) {
            let label;
            if (key === "*")
                label = I18n.tr("Überall");
            else if (key === rel)
                label = I18n.tr("Dieses Bild");
            else
                label = I18n.tr("Ordner %1").arg(key.slice(0, -1).split("/").pop());
            out.push({ key: key, label: label, own: Array.isArray(root.scenes[key]) });
        }
        return out;
    }

    // Stand beim Start des Bearbeitens, fuer "Abbrechen"
    property string snapshot: ""

    function edit(screenName: string): void {
        root.snapshot = JSON.stringify(root.data);
        root.target = root.currentKey !== "" ? root.currentKey : root.chainFor(root.wallpaper)[0];
        root.editScreen = screenName || (Hyprland.focusedMonitor?.name ?? "");
        root.selected = "";
        root.adding = false;
        root.live = null;
        root.editing = true;
        root.analyse();
    }

    function done(): void {
        root.live = null;
        root.adding = false;
        root.editing = false;
        root.selected = "";
        root.flush();
    }

    // Alles seit dem Start des Bearbeitens verwerfen
    function cancel(): void {
        if (root.snapshot !== "") {
            root.data = JSON.parse(root.snapshot);
            root.save();
        }
        root.live = null;
        root.adding = false;
        root.editing = false;
        root.selected = "";
        root.flush();
    }

    function toggleEdit(screenName: string): void {
        if (root.editing)
            root.done();
        else
            root.edit(screenName);
    }

    // Ziel wechseln. Hat es noch keine eigene Szene, startet es mit einer
    // Kopie dessen, was gerade zu sehen ist.
    function setTarget(key: string): void {
        if (!Array.isArray(root.scenes[key]))
            root.writeScene(key, JSON.parse(JSON.stringify(root.widgets)));
        root.target = key;
        root.selected = "";
    }

    // Eigene Szene des Ziels loeschen: es gilt wieder die allgemeinere
    function dropTarget(): void {
        const next = Object.assign({}, root.scenes);
        delete next[root.target];
        root.data = Object.assign({}, root.data, { scenes: next });
        root.save();
        const chain = root.chainFor(root.wallpaper);
        const at = chain.indexOf(root.target);
        let fallback = "*";
        for (let i = at + 1; i < chain.length; i++) {
            if (Array.isArray(next[chain[i]])) {
                fallback = chain[i];
                break;
            }
        }
        root.setTarget(fallback);
    }

    function writeScene(key: string, list: var): void {
        const next = Object.assign({}, root.scenes);
        next[key] = list;
        root.data = Object.assign({}, root.data, { scenes: next });
        root.save();
    }

    function newId(): string {
        return "w" + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
    }

    function add(type: string): void {
        const info = DesktopWidgets.info(type);
        if (!info)
            return;
        const w = {
            id: root.newId(),
            type: type,
            x: 0.5,
            y: 0.5,
            size: 1,
            monitor: "*",
            opts: DesktopWidgets.defaults(type)
        };
        const at = root.addAt;
        const spot = at ? root.spotAt(info.size ?? [10, 6], at) : root.place(info.size ?? [10, 6], 1, root.widgets);
        if (spot) {
            w.x = spot.x;
            w.y = spot.y;
            w.opts.color = spot.dark ? "dunkel" : "hell";
        }
        root.writeScene(root.target, [...root.widgets, w]);
        root.adding = false;
        root.selected = w.id;
    }

    function patch(id: string, changes: var): void {
        root.writeScene(root.target, root.widgets.map(w => w.id === id ? Object.assign({}, w, changes) : w));
    }

    function setOpt(id: string, key: string, value: var): void {
        const w = root.widgets.find(x => x.id === id);
        if (w)
            root.patch(id, { opts: Object.assign({}, w.opts ?? {}, { [key]: value }) });
    }

    function remove(id: string): void {
        root.writeScene(root.target, root.widgets.filter(w => w.id !== id));
        if (root.selected === id)
            root.selected = "";
    }

    function duplicate(id: string): void {
        const w = root.widgets.find(x => x.id === id);
        if (!w)
            return;
        const copy = JSON.parse(JSON.stringify(w));
        copy.id = root.newId();
        copy.x = Math.min(0.95, w.x + 0.04);
        copy.y = Math.min(0.95, w.y + 0.04);
        root.writeScene(root.target, [...root.widgets, copy]);
        root.selected = copy.id;
    }

    // Alle Widgets des Ziels neu auf ruhige Stellen verteilen (groesste zuerst)
    function arrange(): void {
        if (!root.analysis)
            return;
        const placed = [];
        const order = [...root.widgets].sort((a, b) => root.area(b) - root.area(a));
        const moved = {};
        for (const w of order) {
            const spot = root.place(DesktopWidgets.info(w.type)?.size ?? [10, 6], w.size ?? 1, placed);
            const next = spot ? Object.assign({}, w, { x: spot.x, y: spot.y }) : w;
            moved[w.id] = next;
            placed.push(next);
        }
        root.writeScene(root.target, root.widgets.map(w => moved[w.id] ?? w));
    }

    function area(w: var): real {
        const s = DesktopWidgets.info(w.type)?.size ?? [10, 6];
        return s[0] * s[1] * (w.size ?? 1) * (w.size ?? 1);
    }

    // ---- Ruhige Stellen (calm.py) ----
    // Raster mit Kantendichte und Helligkeit des Wallpapers. Damit setzt
    // `place` neue Widgets dorthin, wo das Bild wenig los hat, und waehlt die
    // Textfarbe nach dem Untergrund.

    property var analysis: null
    property string analysedPath: ""
    readonly property string calmScript: Qt.resolvedUrl("calm.py").toString().replace("file://", "")

    function analyse(): void {
        const path = root.wallpaper;
        if (path === "" || path === root.analysedPath)
            return;
        const thumb = Wallpapers.thumbPathFor(path);
        calm.forPath = path;
        calm.command = ["python3", "-I", root.calmScript, thumb !== "" ? thumb : path,
            Quickshell.env("HOME") + "/.cache/dynamic-island/calm"];
        calm.running = true;
    }

    onWallpaperChanged: if (root.editing) root.analyse()

    Process {
        id: calm

        property string forPath: ""

        stdout: StdioCollector {
            id: calmOut

            onStreamFinished: {
                try {
                    root.analysis = JSON.parse(calmOut.text);
                    root.analysedPath = calm.forPath;
                } catch (e) {
                    root.analysis = null;
                }
            }
        }
    }

    // Stelle fuer ein Widget der Groesse `cells` mit Mittelpunkt bei `at`
    // (Rechtsklick), so verschoben, dass es ganz auf den Bildschirm passt.
    // Textfarbe nach dem Untergrund, wenn die Analyse schon da ist.
    function spotAt(cells: var, at: var): var {
        const fw = Math.min(0.9, cells[0] * 16 / 2560);
        const fh = Math.min(0.9, cells[1] * 16 / 1440);
        const x = Math.max(fw / 2 + 0.01, Math.min(1 - fw / 2 - 0.01, at.x));
        const y = Math.max(fh / 2 + 0.01, Math.min(1 - fh / 2 - 0.01, at.y));
        let dark = false;
        const a = root.analysis;
        if (a) {
            let luma = 0, n = 0;
            const x0 = Math.floor((x - fw / 2) * a.cols), x1 = Math.ceil((x + fw / 2) * a.cols);
            const y0 = Math.floor((y - fh / 2) * a.rows), y1 = Math.ceil((y + fh / 2) * a.rows);
            for (let cy = Math.max(0, y0); cy < Math.min(a.rows, y1); cy++) {
                for (let cx = Math.max(0, x0); cx < Math.min(a.cols, x1); cx++) {
                    luma += a.luma[cy * a.cols + cx];
                    n++;
                }
            }
            dark = n > 0 && luma / n > 0.62;
        }
        return { x: Number(x.toFixed(4)), y: Number(y.toFixed(4)), dark };
    }

    // Beste Stelle fuer ein Widget der Groesse `cells` (in Einheiten, s.
    // DesktopWidgets.size) * size. Liefert { x, y, dark } (Mittelpunkt) oder
    // null ohne Analyse. Meidet das obere Band (Notch) und andere Widgets.
    function place(cells: var, size: real, others: var): var {
        const a = root.analysis;
        if (!a)
            return null;
        // Einheit 16 px bei 2560x1440 -> Anteil am Bildschirm
        const fw = Math.min(0.9, cells[0] * 16 * size / 2560);
        const fh = Math.min(0.9, cells[1] * 16 * size / 1440);
        const cw = Math.max(1, Math.ceil(fw * a.cols));
        const ch = Math.max(1, Math.ceil(fh * a.rows));

        const boxes = others.map(o => {
            const s = DesktopWidgets.info(o.type)?.size ?? [10, 6];
            const ow = s[0] * 16 * (o.size ?? 1) / 2560;
            const oh = s[1] * 16 * (o.size ?? 1) / 1440;
            return { x0: o.x - ow / 2, x1: o.x + ow / 2, y0: o.y - oh / 2, y1: o.y + oh / 2 };
        });

        let best = null;
        for (let cy = 2; cy + ch <= a.rows - 1; cy++) {
            for (let cx = 1; cx + cw <= a.cols - 1; cx++) {
                let busy = 0, luma = 0;
                for (let y = cy; y < cy + ch; y++) {
                    for (let x = cx; x < cx + cw; x++) {
                        busy += a.busy[y * a.cols + x];
                        luma += a.luma[y * a.cols + x];
                    }
                }
                const n = cw * ch;
                const x = (cx + cw / 2) / a.cols;
                const y = (cy + ch / 2) / a.rows;
                let overlap = 0;
                for (const b of boxes) {
                    const ox = Math.max(0, Math.min(x + fw / 2, b.x1) - Math.max(x - fw / 2, b.x0));
                    const oy = Math.max(0, Math.min(y + fh / 2, b.y1) - Math.max(y - fh / 2, b.y0));
                    overlap += (ox * oy) / (fw * fh);
                }
                // Leichte Vorliebe fuer die Drittel-Linien
                const thirds = Math.min(Math.abs(x - 1 / 3), Math.abs(x - 2 / 3), Math.abs(x - 0.5)) * 0.15;
                const score = busy / n + overlap * 2 + thirds;
                if (!best || score < best.score)
                    best = { score: score, x: x, y: y, dark: luma / n > 0.62 };
            }
        }
        return best ? { x: Number(best.x.toFixed(3)), y: Number(best.y.toFixed(3)), dark: best.dark } : null;
    }

    // ---- Datei ----

    function save(): void {
        saveDelay.restart();
    }

    function flush(): void {
        if (!saveDelay.running)
            return;
        saveDelay.stop();
        const text = JSON.stringify(root.data, null, 2) + "\n";
        root.lastWritten = text;
        file.setText(text);
    }

    property string lastWritten: ""

    // Ziehen schreibt bei jedem Loslassen; gesammelt auf die Platte
    Timer {
        id: saveDelay

        interval: 400
        onTriggered: {
            saveDelay.stop();
            const text = JSON.stringify(root.data, null, 2) + "\n";
            root.lastWritten = text;
            file.setText(text);
        }
    }

    Component.onDestruction: root.flush()

    FileView {
        id: file

        path: root.path
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const text = file.text();
            // Echo des eigenen Schreibens: nichts neu setzen
            if (text === root.lastWritten)
                return;
            try {
                const parsed = JSON.parse(text);
                if (parsed && typeof parsed.scenes === "object")
                    root.data = parsed;
            } catch (e) {
                // Oft nur halb geschrieben (Editor, Skript) – gleich nochmal
                if (retry.tries++ < 5)
                    retry.restart();
                else
                    console.warn("Scenes: scenes.json nicht lesbar:", e);
                return;
            }
            retry.tries = 0;
        }
    }

    Timer {
        id: retry

        property int tries: 0

        interval: 250
        onTriggered: file.reload()
    }
}
