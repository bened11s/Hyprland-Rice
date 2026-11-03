pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services.config
import qs.modules.services.wallpaper
import qs.modules.widgets

import qs
import "lookmodel.js" as LookModel

// Looks-Editor – die Seite "Looks bearbeiten" des Terminal-Plugins im
// Einstellungs-Fenster (Manifest `pages`, geladen von SettingsCard).
//
// Oben die Look-Auswahl, der Titel und Speichern; darunter links (bzw. in
// schmalen Fenstern oben) die echte fastfetch-Ausgabe (looks.py preview,
// entprellt) mit der Logo-Karte daneben wie im Terminal, rechts der Editor
// in Reitern: Farben, Zeilen, Darstellung, Karten, Datei.
//
// Das Datenmodell ist lookmodel.js (reine Funktionen, jede Aenderung eine
// neue Zuweisung an `look`); looks.py (ueber plugin.main.call) liest und
// schreibt die Dateien. Nichts wird still gespeichert: `dirty` zeigt den
// Knopf, Rueckfragen (Look-Wechsel, erstes Speichern, Konflikt, Loeschen)
// stehen als Leiste unter dem Kopf. Popover (Listen, Farbwaehler, Neu)
// werden in der Seite gezeichnet – Fenster ausserhalb gibt es nicht.
Item {
    id: page

    required property var plugin
    // Von aussen (SettingsState.openPage): { look: id } oder { create: Ordnername }
    property var args: ({})

    readonly property var svc: page.plugin.main
    readonly property string fastfetchDir: Quickshell.env("DYNAMIC_ISLAND_FASTFETCH_DIR") || (Quickshell.env("HOME") + "/.config/fastfetch")

    // ---- Zustand ----
    property string lookId: ""
    property var look: null
    property bool managed: true
    property string savedJson: ""
    readonly property bool dirty: page.look !== null && JSON.stringify(page.look) !== page.savedJson
    readonly property var info: page.svc?.looks.find(l => l.id === page.lookId) ?? null
    readonly property string title: page.look?.title ?? page.info?.title ?? page.lookId

    property string size: "config"
    property string tab: "rows"
    property var preview: null
    property bool previewPending: false
    property string error: ""

    // Rueckfrage-Leiste: "" | "switch" | "first" | "conflict" | "delete"
    property string ask: ""
    property var pending: null          // Funktion, laeuft nach Speichern/Verwerfen
    property var conflictSizes: []

    // Zeilen-Editor
    property int selected: -1
    property string scope: "all"
    property var segs: []
    property string segSource: "\u0000"
    property int dragFrom: -1
    property int dragTo: -1
    // Einfuegelinie beim Hover: -2 keine, -1 vor der ersten Zeile, sonst nach Zeile n
    property int gapIndex: -2
    // Frisch eingefuegte Zeile, blinkt kurz auf
    property int flashRow: -1
    property string moduleFilter: ""

    // Palette
    property string renaming: ""
    property string renameText: ""
    property var colorTarget: null      // { kind: "palette", name } | { kind: "segment", index }
    property color pickColor: "#808080"

    // Karten
    property var cards: []
    property string cardSelected: ""
    property bool cardArmed: false
    property string cardImage: ""

    // Eigene Datei
    property bool rawEditing: false
    property string rawText: ""
    property string rawLoaded: ""
    property string rawError: ""

    // Popover: "" | looks | new | more | rowmenu | modules | scope | color | segcolor | palette | suggest | images | folders | percent | cardadd | cardcolor | palmenu
    property string menu: ""
    property real menuX: 0
    property real menuY: 0
    property var menuData: null
    property string imagesFolder: ""
    property string imagesFor: ""       // "palette" | "card"

    property bool titleEditing: false

    // Neu-Formular
    property string newName: ""
    property string newTitle: ""
    property string newFrom: ""

    readonly property var sizes: LookModel.SIZES
    readonly property var pal: page.look?.palette ?? ({})
    readonly property var paletteNames: Object.keys(page.pal)
    readonly property var conf: page.look ? LookModel.sizeConf(page.look, page.size) : ({})
    readonly property var budget: ({ config: [64, 23], compact: [50, 19], mini: [32, 7] })[page.size]
    readonly property bool wide: page.width >= 1000
    // Breit stehen die Zeilen als eigene Spalte, der Reiter entfaellt
    readonly property string editTab: page.wide && page.tab === "rows" ? "palette" : page.tab
    readonly property bool busy: page.svc?.busy ?? false
    readonly property bool rawOn: page.look?.sizes?.[page.size]?.raw === true
    readonly property bool overflowing: page.preview?.tooTall || (page.preview?.overflow?.length ?? 0) > 0

    // Deckt Nerd-Icons und Balkenzeichen (▰▱) ab; fehlt sie, nimmt Qt monospace
    readonly property string monoFont: Qt.fontFamilies().includes("CaskaydiaCove Nerd Font Mono")
        ? "CaskaydiaCove Nerd Font Mono" : "monospace"

    // ---- Hilfen ----
    function tr(s: string): string {
        return I18n.tr(s);
    }

    function typeTitle(type: string): string {
        return I18n.tr(LookModel.MODULES.find(m => m.type === type)?.title ?? type);
    }

    function colorOf(spec: string): string {
        return LookModel.resolveColor(spec, page.pal, "");
    }

    // Wallpaper-Ordner zum Look (Ordnername klein = Look-ID)
    function folderFor(id: string): string {
        return WallManager.folders.find(f => f.split("/").pop().toLowerCase() === id) ?? "";
    }

    function imagesIn(folder: string): var {
        return folder === "" ? [] : WallManager.imagesIn(folder);
    }

    function setLook(next: var): void {
        page.look = next;
        page.error = "";
        previewTimer.restart();
    }

    function cardFor(id: string): string {
        return page.svc?.looks.find(l => l.id === id)?.card ?? "";
    }

    // ---- Aufrufe an looks.py ----
    // Eigene Warteschlange vor plugin.main.call: immer nur ein Auftrag
    // unterwegs, Ergebnisse kommen ueber einen Timer (nicht im Callback des
    // Prozesses – ein dort gestarteter naechster Aufruf kaeme dem Dienst in
    // die Quere, der nach Schreibvorgaengen selbst `list` nachschiebt).
    // Wartende Vorschauen ersetzt die neueste.
    property var jobs: []
    property var done: []
    property bool inflight: false

    function run(op: string, args: var, cb: var): void {
        let list = page.jobs;
        if (op === "preview")
            list = list.filter(j => j.op !== "preview");
        page.jobs = list.concat([{ op, args: args ?? [], cb: cb ?? null }]);
        page.pump();
    }

    function pump(): void {
        if (page.inflight || page.jobs.length === 0 || !page.svc || page.svc.busy)
            return;
        const job = page.jobs[0];
        page.jobs = page.jobs.slice(1);
        page.inflight = true;
        page.svc.call(job.op, job.args, r => {
            // Die Seite kann inzwischen weg sein (Gruppe gewechselt)
            try {
                page.inflight = false;
                page.done = page.done.concat([{ job, result: r }]);
                pumpTimer.restart();
            } catch (e) {}
        });
    }

    // Zwei Schritte Abstand: der Dienst schiebt nach jedem Prozess per
    // Qt.callLater seinen naechsten Auftrag an, ohne zu pruefen, ob schon
    // einer laeuft. Ein Timer feuert davor, ein callLater aus dem Timer
    // danach – erst dann ist es sicher, selbst etwas zu starten.
    Timer {
        id: pumpTimer

        interval: 0
        onTriggered: Qt.callLater(page.pumpNow)
    }

    function pumpNow(): void {
        const list = page.done;
        page.done = [];
        for (const d of list) {
            try {
                if (d.job.cb)
                    d.job.cb(d.result);
            } catch (e) {
                console.warn(`[terminal] LooksPage ${d.job.op}: ${e}`);
            }
        }
        page.pump();
    }

    Connections {
        target: page.svc

        // Nicht sofort: busy faellt noch im Beenden-Handler des Prozesses,
        // ein dort gestarteter Prozess bekaeme dessen Ausgabe zugeordnet
        function onBusyChanged(): void {
            if (!page.svc.busy)
                pumpTimer.restart();
        }
    }

    // ---- Laden / Speichern ----
    function loadLook(id: string, after: var): void {
        page.run("get", [id], r => {
            if (!r.ok) {
                page.error = r.error ?? "";
                return;
            }
            if (id !== page.lookId)
                page.rawPreviews = {};
            page.lookId = id;
            page.look = r.look;
            page.managed = r.managed;
            page.savedJson = JSON.stringify(r.look);
            page.selected = -1;
            page.segSource = "\u0000";
            page.ask = "";
            page.error = "";
            page.rawEditing = false;
            page.titleEditing = false;
            page.cardSelected = "";
            // Das Neu-Formular bleibt offen (es laedt im Hintergrund einen Look)
            if (page.menu !== "new")
                page.menu = "";
            page.loadCards();
            page.requestPreview();
            if (after)
                after();
        });
    }

    function openLook(id: string): void {
        if (id === page.lookId)
            return;
        if (page.dirty) {
            page.pending = () => page.loadLook(id, null);
            page.ask = "switch";
            return;
        }
        page.loadLook(id, null);
    }

    // Etwas tun, das einen gespeicherten Stand braucht (Datei-Reiter)
    function ensureSaved(fn: var): void {
        if (!page.dirty) {
            fn();
            return;
        }
        page.pending = fn;
        page.ask = "switch";
    }

    function save(force: bool): void {
        if (!page.look)
            return;
        if (!page.managed && !force && page.ask !== "first") {
            page.ask = "first";
            return;
        }
        page.ask = "";
        page.run("save", [page.lookId, "--json", JSON.stringify(page.look)].concat(force ? ["--force"] : []), r => {
            if (r.ok) {
                const next = page.pending;
                page.pending = null;
                page.loadLook(page.lookId, next);
                return;
            }
            const err = r.error ?? "";
            const sizes = (err.match(/(config|compact|mini)\.jsonc/g) ?? []).map(m => m.replace(".jsonc", ""));
            if (sizes.length > 0) {
                page.conflictSizes = sizes;
                page.ask = "conflict";
            } else
                page.error = err;
        });
    }

    // Konflikt: die von Hand geaenderten Dateien als eigene Dateien behalten
    // (raw-get -> raw-set markiert sie in look.json), dann noch einmal
    // speichern – die eigenen Groessen werden dabei nicht mehr erzeugt
    function keepRaw(): void {
        const sizes = page.conflictSizes.slice();
        page.ask = "";
        const step = () => {
            if (sizes.length === 0) {
                const next = LookModel.clone(page.look);
                next.sizes = next.sizes || {};
                for (const s of page.conflictSizes)
                    next.sizes[s] = Object.assign({}, next.sizes[s] || {}, { raw: true });
                page.look = next;
                page.save(false);
                return;
            }
            const s = sizes.shift();
            page.run("raw-get", [page.lookId, s], r => {
                if (!r.ok) {
                    page.error = r.error ?? "";
                    return;
                }
                page.run("raw-set", [page.lookId, s, "--text", r.text], r2 => {
                    if (!r2.ok) {
                        page.error = r2.error ?? "";
                        return;
                    }
                    step();
                });
            });
        };
        step();
    }

    function discard(): void {
        const next = page.pending;
        page.pending = null;
        page.ask = "";
        page.look = JSON.parse(page.savedJson);
        if (next)
            next();
    }

    function cancelAsk(): void {
        page.ask = "";
        page.pending = null;
    }

    function deleteLook(): void {
        const id = page.lookId;
        page.ask = "";
        page.run("delete", [id], r => {
            if (!r.ok) {
                page.error = r.error ?? "";
                return;
            }
            page.look = null;
            page.lookId = "";
            page.savedJson = "";
            page.preview = null;
            const first = page.svc.looks.find(l => l.id !== id);
            if (first)
                page.loadLook(first.id, null);
        });
    }

    function createLook(): void {
        const id = page.cleanId(page.newName);
        if (!/^[a-z0-9][a-z0-9._-]{0,63}$/.test(id))
            return;
        const args = [id, "--from", page.newFrom || "miku"];
        if (page.newTitle.trim() !== "")
            args.push("--title", page.newTitle.trim());
        page.menu = "";
        page.run("new", args, r => {
            if (!r.ok) {
                page.error = r.error ?? "";
                return;
            }
            page.loadLook(id, () => {
                page.tab = "palette";
                // Farben aus dem Wallpaper anbieten, wenn ein Ordner passt
                const folder = page.folderFor(id);
                if (folder !== "" && page.imagesIn(folder).length > 0) {
                    page.imagesFolder = folder;
                    page.imagesFor = "palette";
                    page.openAt("images", suggestButton);
                }
            });
        });
    }

    function cleanId(name: string): string {
        return name.toLowerCase().trim().replace(/\s+/g, "-").replace(/[^a-z0-9._-]/g, "").replace(/^[^a-z0-9]+/, "");
    }

    function openNew(name: string): void {
        page.newName = page.cleanId(name);
        page.newTitle = name === "" ? "" : page.prettyTitle(page.cleanId(name));
        page.newFrom = page.lookId || "miku";
        page.openAt("new", lookButton);
    }

    function prettyTitle(id: string): string {
        return id.split(/[-_.]+/).filter(p => p).map(p => p[0].toUpperCase() + p.slice(1)).join(" ");
    }

    // ---- Vorschau ----
    // Eigene Dateien rendert looks.py direkt von der Platte (preview --raw);
    // raw-set liefert nach "Datei speichern" ebenfalls eine (Cache je Groesse)
    property var rawPreviews: ({})

    function requestPreview(): void {
        if (!page.look || !page.svc)
            return;
        if (page.rawOn) {
            const cached = page.rawPreviews[page.size];
            if (cached) {
                page.preview = cached;
                return;
            }
            const size = page.size;
            page.previewPending = true;
            page.run("preview", [size, "--raw", page.lookId], r => {
                page.previewPending = false;
                if (r.ok) {
                    const next = Object.assign({}, page.rawPreviews);
                    next[size] = r;
                    page.rawPreviews = next;
                    if (page.size === size)
                        page.preview = r;
                }
            });
            return;
        }
        page.previewPending = true;
        page.run("preview", [page.size, "--json", JSON.stringify(page.look)], r => {
            page.previewPending = false;
            if (r.ok)
                page.preview = r;
            else
                page.preview = { lines: [[{ t: r.error ?? "", fg: Colors.error.toString() }]], width: 0, height: 1, budget: { cols: page.budget[0], rows: page.budget[1] }, overflow: [], tooTall: false, failed: true };
        });
    }

    Timer {
        id: previewTimer

        interval: 150
        onTriggered: page.requestPreview()
    }

    onSizeChanged: {
        page.segSource = "\u0000";
        page.rawEditing = false;
        previewTimer.restart();
    }

    // ---- Zeilen ----
    readonly property var selectedRow: page.look && page.selected >= 0 && page.selected < page.look.rows.length ? page.look.rows[page.selected] : null
    readonly property var selectedValue: page.selectedRow ? LookModel.rowValue(page.selectedRow, page.size) : null
    readonly property bool selectedIsModule: LookModel.isObj(page.selectedValue)
    readonly property string selectedFormat: page.selectedIsModule ? (page.selectedValue.format ?? "") : ""

    onSelectedFormatChanged: page.syncSegs()
    onSelectedChanged: page.syncSegs()

    function syncSegs(): void {
        if (page.selectedFormat === page.segSource)
            return;
        page.segSource = page.selectedFormat;
        page.segs = page.tidySegs(LookModel.parse(page.selectedFormat));
    }

    // Leerzeichen zwischen zwei Abschnitten (ohne eigenen Stil) gehoeren zum
    // vorigen Abschnitt – als eigene Zeile waeren sie unsichtbar
    function tidySegs(segs: var): var {
        const out = [];
        for (const seg of segs) {
            const blank = seg.text.trim() === "" && !seg.color && !seg.bold && !seg.italic && !seg.dim && !seg.underline && !(seg.extra ?? []).length;
            if (blank && out.length > 0)
                out[out.length - 1] = Object.assign({}, out[out.length - 1], { text: out[out.length - 1].text + seg.text });
            else
                out.push(seg);
        }
        return out;
    }

    function setRowField(field: string, value: var): void {
        if (!page.selectedRow)
            return;
        const row = LookModel.setField(page.selectedRow, page.size, field, value, page.scope);
        page.setLook(LookModel.replaceRow(page.look, page.selected, row));
    }

    function writeSegs(next: var): void {
        page.segs = next;
        const markup = LookModel.format(next);
        page.segSource = markup;
        page.setRowField("format", markup === "" ? undefined : markup);
    }

    function setSeg(index: int, patch: var): void {
        const next = page.segs.map((s, i) => i === index ? Object.assign({}, s, patch) : s);
        page.writeSegs(next);
    }

    function addSeg(): void {
        const last = page.segs[page.segs.length - 1];
        const seg = Object.assign(LookModel.emptyStyle(), { text: " " });
        if (last)
            seg.color = last.color;
        page.writeSegs(page.segs.concat([seg]));
    }

    function removeSeg(index: int): void {
        page.writeSegs(page.segs.filter((s, i) => i !== index));
    }

    function togglePresent(index: int, s: string): void {
        const row = page.look.rows[index];
        page.setLook(LookModel.replaceRow(page.look, index, LookModel.setPresent(row, s, !LookModel.present(row, s))));
    }

    function removeRow(index: int): void {
        page.setLook(LookModel.removeRow(page.look, index));
        if (page.selected === index)
            page.selected = -1;
        else if (page.selected > index)
            page.selected--;
    }

    function moveRow(from: int, to: int): void {
        if (from === to)
            return;
        page.setLook(LookModel.moveRow(page.look, from, to));
        if (page.selected === from)
            page.selected = to;
    }

    // Modul-Popover oeffnen; `after` = Zeile, hinter der eingefuegt wird
    // (-1 = ganz oben), sonst hinter der Auswahl bzw. am Ende
    function insertAt(after: int, x: real, y: real): void {
        page.moduleFilter = "";
        page.openMenuAt("modules", x, y, after);
    }

    function addModule(type: string): void {
        const m = LookModel.makeModule(type, page.look, page.size);
        const after = typeof page.menuData === "number" ? page.menuData
                    : page.selected >= 0 ? page.selected : page.look.rows.length - 1;
        // Nicht in mini, ausser mini ist gerade gewaehlt – mini bleibt knapp
        const only = page.size === "mini" ? ["mini"] : page.sizes.filter(s => s !== "mini");
        page.setLook(LookModel.addRow(page.look, after, m, only));
        page.selected = after + 1;
        page.flashRow = after + 1;
        flashTimer.restart();
        revealTimer.restart();
        Qt.callLater(() => page.revealRow(after + 1));
    }

    function revealRow(i: int): void {
        const it = rowsRepeater.itemAt(i);
        if (!it)
            return;
        const max = Math.max(0, rowsFlick.contentHeight - rowsFlick.height);
        const top = rowsTab.y + it.y, bottom = top + it.height;
        if (top - 4 < rowsFlick.contentY)
            rowsFlick.contentY = Math.max(0, top - 4);
        else if (bottom + 4 > rowsFlick.contentY + rowsFlick.height)
            rowsFlick.contentY = Math.min(max, bottom + 4 - rowsFlick.height);
    }

    Timer {
        id: flashTimer

        interval: 900
        onTriggered: page.flashRow = -1
    }

    Timer {
        id: revealTimer

        interval: Appearance.fadeDuration + 40
        onTriggered: page.revealRow(page.selected)
    }

    // Einfuegelinie zur Mausposition (y relativ zur Zeilenliste)
    function updateGap(y: real): void {
        if (page.dragFrom >= 0) {
            page.gapIndex = -2;
            return;
        }
        let best = -2;
        for (let i = 0; i < rowsRepeater.count; i++) {
            const it = rowsRepeater.itemAt(i);
            if (!it)
                continue;
            if (i === 0 && Math.abs(y - it.y) <= 5) {
                best = -1;
                break;
            }
            if (Math.abs(y - (it.y + it.height)) <= 5) {
                best = i;
                break;
            }
        }
        page.gapIndex = best;
    }

    // HTML einer Zeile fuer die Liste (Key, Trenner, Format)
    function rowHtml(value: var): string {
        if (value === null)
            return "";
        if (typeof value === "string")
            return value === "break" ? "" : LookModel.escapeHtml(page.typeTitle(value));
        const keyColor = page.colorOf(page.conf.display?.color?.keys ?? "") || Colors.fgSurface.toString();
        const sepColor = page.colorOf(page.conf.display?.color?.separator ?? "") || Colors.fgSurfaceVariant.toString();
        const fg = Colors.fgSurface.toString();
        let out = "";
        if (typeof value.key === "string") {
            out += LookModel.html(value.key, page.pal, keyColor);
            out += LookModel.segHtml(page.conf.display?.separator ?? " : ", sepColor, false, false, false, false);
        }
        if (typeof value.format === "string")
            out += LookModel.html(value.format, page.pal, fg);
        else if (typeof value.key !== "string")
            out += LookModel.escapeHtml(page.typeTitle(value.type ?? ""));
        else
            out += LookModel.segHtml("{" + (value.type ?? "") + "}", Colors.fgSurfaceVariant.toString(), false, false, true, false);
        return out;
    }

    // ---- Palette ----
    function setPaletteColor(name: string, hex: string): void {
        const next = LookModel.clone(page.look);
        next.palette[name] = hex;
        page.setLook(next);
    }

    function addPaletteColor(): void {
        let name = "neu", n = 2;
        while (name in page.pal)
            name = "neu" + n++;
        const next = LookModel.clone(page.look);
        next.palette[name] = "#808080";
        page.setLook(next);
        page.renaming = name;
        page.renameText = name;
    }

    function removePaletteColor(name: string): void {
        const next = LookModel.clone(page.look);
        delete next.palette[name];
        page.setLook(next);
    }

    function finishRename(): void {
        const from = page.renaming;
        const to = page.renameText.trim();
        page.renaming = "";
        if (from === "" || to === "" || to === from)
            return;
        const next = LookModel.renamePalette(page.look, from, to);
        if (next !== page.look)
            page.setLook(next);
    }

    function applyRoles(roles: var): void {
        const next = LookModel.clone(page.look);
        for (const role in roles)
            next.palette[role] = roles[role];
        page.setLook(next);
    }

    function suggestFromImage(path: string): void {
        page.run("palette", [path], r => {
            if (r.ok)
                page.applyRoles(r.roles ?? {});
            else
                page.error = r.error ?? "";
        });
    }

    function suggestFromScheme(): void {
        page.run("scheme-palette", [], r => {
            if (r.ok)
                page.applyRoles(r.palette ?? {});
            else
                page.error = r.error ?? "";
        });
    }

    // ---- Darstellung ----
    function setConf(path: var, value: var): void {
        page.setLook(LookModel.setConf(page.look, page.size, path, value));
    }

    function confValue(path: var): var {
        return LookModel.getPath(page.conf, path);
    }

    readonly property var percentOptions: [
        { title: "Balken und Zahl", value: ["bar", "num"] },
        { title: "Balken", value: ["bar"] },
        { title: "Zahl", value: ["num"] },
        { title: "Keine", value: null }
    ]

    function percentLabel(): string {
        const v = page.confValue(["display", "percent", "type"]);
        const found = page.percentOptions.find(o => LookModel.equal(o.value, v ?? null));
        return I18n.tr(found?.title ?? "Keine");
    }

    // ---- Karten ----
    function loadCards(): void {
        if (page.lookId === "")
            return;
        page.run("cards", [page.lookId], r => {
            if (r.ok)
                page.cards = r.cards ?? [];
        });
    }

    function makeCard(path: string, color: string): void {
        page.menu = "";
        page.run("card-make", [page.lookId, path].concat(color !== "" ? [color] : []), r => {
            if (!r.ok)
                page.error = r.error ?? "";
            page.loadCards();
        });
    }

    function removeCard(): void {
        const name = page.cardSelected;
        page.cardArmed = false;
        page.cardSelected = "";
        page.run("card-remove", [page.lookId, name], r => {
            if (!r.ok)
                page.error = r.error ?? "";
            page.loadCards();
        });
    }

    // ---- Eigene Datei ----
    function rawLoad(): void {
        page.run("raw-get", [page.lookId, page.size], r => {
            if (!r.ok) {
                page.error = r.error ?? "";
                return;
            }
            page.rawText = r.text;
            page.rawLoaded = r.text;
            page.rawError = "";
            page.rawEditing = true;
        });
    }

    function rawSave(): void {
        const text = page.rawText;
        page.run("raw-set", [page.lookId, page.size, "--text", text], r => {
            if (!r.ok) {
                page.rawError = r.error ?? "";
                return;
            }
            page.rawError = "";
            if (r.preview) {
                const next = Object.assign({}, page.rawPreviews);
                next[page.size] = r.preview;
                page.rawPreviews = next;
            }
            page.loadLook(page.lookId, () => {
                page.rawText = text;
                page.rawLoaded = text;
                page.rawEditing = true;
            });
        });
    }

    function rawOff(adopt: bool): void {
        page.rawEditing = false;
        const next = Object.assign({}, page.rawPreviews);
        delete next[page.size];
        page.rawPreviews = next;
        page.run("raw-off", [page.lookId, page.size].concat(adopt ? ["--adopt"] : []), r => {
            if (!r.ok) {
                page.error = r.error ?? "";
                return;
            }
            page.loadLook(page.lookId, null);
        });
    }

    // ---- Popover ----
    function openAt(kind: string, item: Item): void {
        const pos = item.mapToItem(page, 0, item.height);
        page.menuX = pos.x;
        page.menuY = pos.y + 4;
        page.menu = kind;
    }

    function openMenuAt(kind: string, x: real, y: real, data: var): void {
        page.menuData = data;
        page.menuX = x;
        page.menuY = y;
        page.menu = kind;
    }

    function closeMenu(): void {
        page.menu = "";
    }

    // Eintraege der Listen-Popover: { title, desc, icon, swatch, thumb, current, danger, sub, action }
    readonly property var popRows: {
        const m = page.menu;
        const looks = page.svc?.looks ?? [];
        if (m === "looks") {
            const out = looks.map(l => ({
                title: I18n.tr(l.title), desc: l.id, card: l.card, current: l.id === page.lookId,
                action: () => { page.closeMenu(); page.openLook(l.id); }
            }));
            out.push({ title: I18n.tr("Neu…"), icon: "add", action: () => page.openNew("") });
            return out;
        }
        if (m === "more") {
            return [
                { title: I18n.tr("Titel ändern"), icon: "edit", action: () => { page.closeMenu(); page.titleEditing = true; } },
                { title: I18n.tr("Ordner öffnen"), icon: "folder_open", action: () => {
                    page.closeMenu();
                    Quickshell.execDetached(["xdg-open", page.info?.dir ?? page.fastfetchDir]);
                } },
                { title: I18n.tr("Look löschen"), icon: "delete", danger: true, enabled: page.lookId !== "miku",
                  action: () => { page.closeMenu(); page.ask = "delete"; } }
            ];
        }
        if (m === "rowmenu") {
            const i = page.menuData ?? -1;
            const row = page.look?.rows[i];
            if (!row)
                return [];
            const on = LookModel.present(row, page.size);
            const x = page.menuX, y = page.menuY;
            return [
                { title: on ? I18n.tr("In %1 ausblenden").arg(page.size) : I18n.tr("In %1 einblenden").arg(page.size),
                  icon: on ? "visibility_off" : "visibility", action: () => { page.closeMenu(); page.togglePresent(i, page.size); } },
                { title: I18n.tr("Darüber einfügen"), icon: "add", sub: true, action: () => page.insertAt(i - 1, x, y) },
                { title: I18n.tr("Darunter einfügen"), icon: "add", sub: true, action: () => page.insertAt(i, x, y) },
                { title: I18n.tr("Nach oben"), icon: "arrow_upward", enabled: i > 0, action: () => { page.closeMenu(); page.moveRow(i, i - 1); } },
                { title: I18n.tr("Nach unten"), icon: "arrow_downward", enabled: i < page.look.rows.length - 1, action: () => { page.closeMenu(); page.moveRow(i, i + 1); } },
                { title: I18n.tr("Löschen"), icon: "delete", danger: true, action: () => { page.closeMenu(); page.removeRow(i); } }
            ];
        }
        if (m === "modules") {
            const q = page.moduleFilter.trim().toLowerCase();
            return LookModel.MODULES.filter(d => q === "" || I18n.tr(d.title).toLowerCase().includes(q) || d.type.includes(q)).map(d => ({
                title: I18n.tr(d.title), desc: d.type === "break" || d.type === "custom" ? "" : d.type,
                action: () => { page.closeMenu(); page.addModule(d.type); }
            }));
        }
        if (m === "scope")
            return [
                { title: I18n.tr("Alle Größen"), current: page.scope === "all", action: () => { page.closeMenu(); page.scope = "all"; } },
                { title: I18n.tr("Nur %1").arg(page.size), current: page.scope === "size", action: () => { page.closeMenu(); page.scope = "size"; } }
            ];
        if (m === "segcolor") {
            const i = page.menuData ?? -1;
            const cur = page.segs[i]?.color ?? "";
            const out = [{ title: I18n.tr("Standard"), current: cur === "", action: () => { page.closeMenu(); page.setSeg(i, { color: "" }); } }];
            for (const n of page.paletteNames)
                out.push({ title: n, swatch: page.pal[n], current: cur === "@" + n, action: () => { page.closeMenu(); page.setSeg(i, { color: "@" + n }); } });
            out.push({ title: I18n.tr("Eigene Farbe…"), swatch: cur.startsWith("#") ? cur : "", current: cur.startsWith("#"), sub: true, action: () => {
                page.colorTarget = { kind: "segment", index: i };
                page.pickColor = cur.startsWith("#") ? cur : (page.colorOf(cur) || "#808080");
                page.menu = "color";
            } });
            return out;
        }
        if (m === "palette") {
            // Farbfeld der Darstellung (menuData = Pfad)
            const path = page.menuData ?? [];
            const cur = page.confValue(path) ?? "";
            const out = [{ title: I18n.tr("Standard"), current: cur === "" || cur === "default", action: () => { page.closeMenu(); page.setConf(path, "default"); } }];
            for (const n of page.paletteNames)
                out.push({ title: n, swatch: page.pal[n], current: cur === "@" + n, action: () => { page.closeMenu(); page.setConf(path, "@" + n); } });
            return out;
        }
        if (m === "palmenu") {
            const n = page.menuData ?? "";
            const used = page.look ? LookModel.paletteUses(page.look, n) : false;
            return [
                { title: I18n.tr("Umbenennen"), icon: "edit", action: () => { page.closeMenu(); page.renaming = n; page.renameText = n; } },
                { title: used ? I18n.tr("Entfernen – wird noch benutzt") : I18n.tr("Entfernen"), icon: "delete", danger: true, enabled: !used,
                  action: () => { page.closeMenu(); page.removePaletteColor(n); } }
            ];
        }
        if (m === "suggest") {
            const folder = page.folderFor(page.lookId);
            return [
                { title: I18n.tr("Aus dem Wallpaper"), icon: "image", sub: true, action: () => {
                    page.imagesFolder = folder !== "" ? folder : (WallManager.folders[0] ?? "");
                    page.imagesFor = "palette";
                    page.menu = page.imagesFolder === "" ? "folders" : "images";
                } },
                { title: I18n.tr("Aus dem Farbschema"), icon: "palette", action: () => { page.closeMenu(); page.suggestFromScheme(); } }
            ];
        }
        if (m === "folders")
            return WallManager.folders.map(f => ({
                title: f.split("/").pop(), icon: "folder", current: f === page.imagesFolder,
                action: () => { page.imagesFolder = f; page.menu = "images"; }
            }));
        if (m === "images") {
            const out = [{ title: page.imagesFolder.split("/").pop(), icon: "folder", sub: true, action: () => page.menu = "folders" }];
            for (const img of page.imagesIn(page.imagesFolder))
                out.push({
                    title: img.name.split("/").pop(), thumb: Wallpapers.thumbFor(img.name),
                    action: () => {
                        if (page.imagesFor === "card") {
                            page.cardImage = img.path;
                            page.menu = "cardcolor";
                        } else {
                            page.closeMenu();
                            page.suggestFromImage(img.path);
                        }
                    }
                });
            return out;
        }
        if (m === "cardcolor") {
            const out = page.paletteNames.map(n => ({
                title: n, swatch: page.pal[n], current: n === "primary",
                action: () => page.makeCard(page.cardImage, "@" + n)
            }));
            return out;
        }
        if (m === "percent")
            return page.percentOptions.map(o => ({
                title: I18n.tr(o.title), current: LookModel.equal(o.value, page.confValue(["display", "percent", "type"]) ?? null),
                action: () => { page.closeMenu(); page.setConf(["display", "percent", "type"], o.value); }
            }));
        return [];
    }

    readonly property string popTitle: I18n.tr(({
        looks: "Look", new: "Neuer Look", rowmenu: "", modules: "Modul hinzufügen", scope: "Gilt für", color: "Farbe",
        segcolor: "Farbe", palette: "Farbe", suggest: "Vorschläge", folders: "Ordner", images: "Bild", percent: "Prozentanzeige",
        cardcolor: "Rahmenfarbe", palmenu: "", more: ""
    })[page.menu] ?? "")

    readonly property bool popSub: ["color", "folders", "images", "cardcolor"].includes(page.menu)

    function popBack(): void {
        if (page.menu === "color")
            page.menu = page.colorTarget?.kind === "segment" ? "segcolor" : "";
        else if (page.menu === "folders")
            page.menu = page.imagesFor === "card" ? "" : "suggest";
        else if (page.menu === "images")
            page.menu = "folders";
        else if (page.menu === "cardcolor")
            page.menu = "images";
        else
            page.menu = "";
    }

    // ---- Start ----
    function applyArgs(): void {
        const a = page.args ?? {};
        if (typeof a.create === "string" && a.create !== "") {
            if (page.lookId === "" && (page.svc?.looks.length ?? 0) > 0)
                page.loadLook(page.svc.looks[0].id, null);
            page.openNew(a.create.split("/").pop());
        } else if (typeof a.look === "string" && a.look !== "")
            page.openLook(a.look);
        else if (page.lookId === "" && (page.svc?.looks.length ?? 0) > 0)
            page.loadLook(page.svc.looks[0].id, null);
    }

    onArgsChanged: page.applyArgs()

    Component.onCompleted: {
        if (!page.svc)
            return;
        WallManager.ensureLoaded();
        Wallpapers.ensureLoaded();
        // Die Liste holt der Dienst erst auf Anforderung; danach haelt er sie
        // selbst aktuell (nach jedem Schreiben)
        if (page.svc.looks.length === 0)
            page.svc.refresh();
        page.applyArgs();
    }

    // Liste da: ersten Look laden, falls noch keiner gewaehlt
    Connections {
        target: page.svc

        function onLooksChanged(): void {
            if (page.lookId === "" && page.look === null && page.svc.looks.length > 0 && !page.args?.look)
                page.loadLook(page.svc.looks[0].id, null);
        }
    }

    // ================= Bausteine =================

    component Quiet: Rectangle {
        id: button

        property string icon: ""
        property string label: ""
        property bool filled: false
        property bool chevron: false
        property bool active: false
        property color tint: Colors.fgSurface
        signal clicked()

        implicitWidth: buttonRow.implicitWidth + (button.label === "" ? 14 : 20)
        implicitHeight: 28
        radius: 9
        opacity: enabled ? 1 : 0.4
        color: button.filled ? (buttonHover.hovered ? Colors.alpha(Colors.primary, 0.85) : Colors.primary)
             : button.active ? Colors.alpha(Colors.primary, 0.16)
             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Row {
            id: buttonRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.icon !== ""
                text: button.icon
                color: button.filled ? Colors.fgPrimary : button.tint
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.label !== ""
                font.family: Config.font
                text: button.label
                color: button.filled ? Colors.fgPrimary : button.tint
                font.pixelSize: 11
                font.weight: button.filled ? Font.DemiBold : Font.Medium
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.chevron
                text: "expand_more"
                color: Colors.alpha(button.tint, 0.7)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 14
            }
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

    // Reiter-Text (Groessen, Editor-Reiter)
    component Tab: Item {
        id: tabItem

        property string label: ""
        property bool current: false
        property bool mono: false
        signal clicked()

        implicitWidth: tabLabel.implicitWidth + 16
        implicitHeight: 28

        Text {
            id: tabLabel

            anchors.centerIn: parent
            font.family: tabItem.mono ? "monospace" : Config.font
            text: tabItem.label
            color: tabItem.current ? Colors.fgBackground : tabHover.hovered ? Colors.fgSurface : Colors.fgSurfaceVariant
            font.pixelSize: 11
            font.weight: tabItem.current ? Font.DemiBold : Font.Normal

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 8
                rightMargin: 8
            }
            height: 2
            radius: 1
            color: Colors.primary
            opacity: tabItem.current ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration }
            }
        }

        HoverHandler {
            id: tabHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: tabItem.clicked()
        }
    }

    // Textfeld mit Rahmen; `value` von aussen, `edited(text)` bei jeder Eingabe
    component Field: Rectangle {
        id: field

        property string value: ""
        property bool mono: false
        property string placeholder: ""
        property bool number: false
        signal edited(string text)
        signal finished()
        signal accepted()

        implicitHeight: 28
        implicitWidth: 120
        radius: 8
        color: Colors.alpha(Colors.fgSurface, 0.06)
        border.width: 1
        border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

        // Von aussen gesetzter Wert, solange niemand tippt
        onValueChanged: if (!input.activeFocus && input.text !== field.value) input.text = field.value

        function focusInput(): void {
            input.forceActiveFocus();
            input.selectAll();
        }

        Behavior on border.color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        TextInput {
            id: input

            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 9
                rightMargin: 9
                verticalCenter: parent.verticalCenter
            }
            font.family: field.mono ? "monospace" : Config.font
            font.pixelSize: field.mono ? 11 : 12
            color: Colors.fgBackground
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            clip: true
            text: field.value
            onTextEdited: field.edited(text)
            onEditingFinished: field.finished()
            onAccepted: field.accepted()
            Keys.onEscapePressed: event => {
                input.text = field.value;
                field.edited(input.text);
                focus = false;
                event.accepted = true;
            }

            Text {
                anchors.fill: parent
                visible: input.text === ""
                text: field.placeholder
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font: input.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    // Zeile der Darstellung: Beschriftung links, Bedienelement rechts
    component Setting: Item {
        id: setting

        property string label: ""
        default property alias control: controlSlot.data

        width: parent.width
        height: 36

        Text {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            font.family: Config.font
            text: setting.label
            color: Colors.fgSurface
            font.pixelSize: 12
        }

        Row {
            id: controlSlot

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 6
        }
    }

    // Farbfeld + Name (Palettenwahl in der Darstellung)
    component ColorPick: Rectangle {
        id: pick

        property var path: []
        readonly property string value: page.confValue(pick.path) ?? ""
        readonly property string hex: page.colorOf(pick.value)

        implicitWidth: pickRow.implicitWidth + 18
        implicitHeight: 28
        radius: 8
        color: pickHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1) : Colors.alpha(Colors.fgSurface, 0.05)

        Row {
            id: pickRow

            anchors.centerIn: parent
            spacing: 7

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 4
                color: pick.hex !== "" ? pick.hex : "transparent"
                border.width: 1
                border.color: Colors.alpha(Colors.outline, 0.5)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.font
                text: pick.value === "" || pick.value === "default" ? I18n.tr("Standard") : pick.value.replace(/^@/, "")
                color: Colors.fgSurface
                font.pixelSize: 11
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "expand_more"
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 14
            }
        }

        HoverHandler {
            id: pickHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: page.openMenuAt("palette", pick.mapToItem(page, 0, pick.height).x, pick.mapToItem(page, 0, pick.height).y + 4, pick.path)
        }
    }

    // Groessen-Reiter und Masse der Vorschau (Kopf, sonst unter der Vorschau)
    component SizeTabs: Row {
        spacing: 2

        Repeater {
            model: page.sizes

            Tab {
                required property string modelData

                label: modelData
                mono: true
                current: page.size === modelData
                onClicked: page.size = modelData
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 12
            font.family: page.monoFont
            visible: page.preview !== null && !page.preview.failed
            text: `${page.preview?.width ?? 0}×${page.preview?.height ?? 0} / ${previewPanel.cols}×${previewPanel.rows}`
            color: page.overflowing ? Colors.error : Colors.fgSurfaceVariant
            font.pixelSize: 10
        }
    }

    // ================= Kopf =================
    Item {
        id: header

        // Reiter nur im Kopf, wenn sie neben Look-Auswahl und Knoepfen Platz haben
        readonly property bool hasSizes: page.look !== null && !page.titleEditing
            && lookButton.width + 14 + headerSizes.implicitWidth + 16 + headerRight.implicitWidth <= header.width

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 34

        SizeTabs {
            id: headerSizes

            anchors {
                left: lookButton.right
                leftMargin: 14
                verticalCenter: parent.verticalCenter
            }
            visible: header.hasSizes
        }

        // Look-Auswahl: Karte, Titel, Pfeil
        Rectangle {
            id: lookButton

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            width: lookRow.implicitWidth + 20
            height: 32
            radius: 10
            color: page.menu === "looks" ? Colors.alpha(Colors.primary, 0.16)
                 : lookHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1) : Colors.alpha(Colors.fgSurface, 0.05)

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }

            Row {
                id: lookRow

                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 24
                    radius: 4
                    color: Colors.alpha(Colors.fgSurface, 0.08)
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: page.cardFor(page.lookId) !== "" ? "file://" + page.cardFor(page.lookId) : ""
                        sourceSize: Qt.size(36, 48)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Config.font
                    text: page.look ? I18n.tr(page.title) : I18n.tr("Look wählen")
                    color: Colors.fgBackground
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "expand_more"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 16
                }
            }

            HoverHandler {
                id: lookHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: page.menu === "looks" ? page.closeMenu() : page.openAt("looks", lookButton)
            }
        }

        // Titel bearbeiten
        Field {
            id: titleField

            anchors {
                left: lookButton.right
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            width: Math.max(120, Math.min(220, header.width - lookButton.width - headerRight.width - 24))
            visible: page.look !== null && page.titleEditing
            value: page.look?.title ?? ""
            placeholder: I18n.tr("Titel")
            onVisibleChanged: if (visible) focusInput()
            onEdited: text => {
                const next = LookModel.clone(page.look);
                next.title = text;
                page.setLook(next);
            }
            onFinished: page.titleEditing = false
        }

        Row {
            id: headerRight

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.busy
                rightPadding: 4
                text: "progress_activity"
                color: Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15

                RotationAnimation on rotation {
                    running: page.busy
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                    duration: Appearance.morphDuration * 3
                }
            }

            Quiet {
                visible: page.dirty && page.ask === ""
                icon: "save"
                label: I18n.tr("Speichern")
                filled: true
                onClicked: page.save(false)
            }

            Quiet {
                id: moreButton

                visible: page.look !== null
                icon: "more_horiz"
                tint: Colors.fgSurfaceVariant
                active: page.menu === "more"
                onClicked: page.menu === "more" ? page.closeMenu() : page.openMenuAt("more", moreButton.mapToItem(page, moreButton.width - 220, moreButton.height).x, moreButton.mapToItem(page, 0, moreButton.height).y + 4, null)
            }
        }
    }

    // ---- Rueckfrage-Leiste ----
    Rectangle {
        id: askBar

        readonly property string text: {
            switch (page.ask) {
            case "switch": return I18n.tr("Ungespeicherte Änderungen an „%1“").arg(page.title);
            case "first": return I18n.tr("„%1“ hat noch keine look.json – die handgeschriebenen Dateien werden ersetzt (Original in .orig/)").arg(page.title);
            case "conflict": return I18n.tr("Von Hand geändert seit dem letzten Speichern: %1").arg(page.conflictSizes.map(s => s + ".jsonc").join(", "));
            case "delete": return I18n.tr("„%1“ in den Papierkorb?").arg(page.title);
            default: return "";
            }
        }

        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            topMargin: page.ask !== "" ? 8 : 0
        }
        height: page.ask !== "" ? askColumn.implicitHeight + 16 : 0
        visible: height > 0
        clip: true
        radius: 10
        color: Colors.alpha(page.ask === "delete" ? Colors.error : Colors.primary, 0.1)
        border.width: 1
        border.color: Colors.alpha(page.ask === "delete" ? Colors.error : Colors.primary, 0.3)

        Behavior on height {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        Column {
            id: askColumn

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
            }
            spacing: 6

            Text {
                width: parent.width
                leftPadding: 4
                font.family: Config.font
                text: askBar.text
                color: Colors.fgBackground
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: 4

                Quiet {
                    visible: page.ask === "switch"
                    label: I18n.tr("Speichern")
                    filled: true
                    onClicked: page.save(false)
                }
                Quiet {
                    visible: page.ask === "switch"
                    label: I18n.tr("Verwerfen")
                    tint: Colors.error
                    onClicked: page.discard()
                }
                Quiet {
                    visible: page.ask === "first"
                    label: I18n.tr("Ersetzen und speichern")
                    filled: true
                    onClicked: page.save(true)
                }
                Quiet {
                    visible: page.ask === "conflict"
                    label: I18n.tr("Als eigene Datei behalten")
                    filled: true
                    onClicked: page.keepRaw()
                }
                Quiet {
                    visible: page.ask === "conflict"
                    label: I18n.tr("Überschreiben")
                    tint: Colors.error
                    onClicked: page.save(true)
                }
                Quiet {
                    visible: page.ask === "delete"
                    label: I18n.tr("Löschen")
                    tint: Colors.error
                    onClicked: page.deleteLook()
                }
                Quiet {
                    label: I18n.tr("Abbrechen")
                    tint: Colors.fgSurfaceVariant
                    onClicked: page.cancelAsk()
                }
            }
        }
    }

    // ---- Fehler ----
    Item {
        id: errorRow

        anchors {
            left: parent.left
            right: parent.right
            top: askBar.bottom
        }
        height: page.error !== "" ? errorText.implicitHeight + 12 : 0
        visible: height > 0
        clip: true

        Text {
            id: errorText

            anchors {
                left: parent.left
                right: dismiss.left
                leftMargin: 4
                verticalCenter: parent.verticalCenter
            }
            font.family: Config.font
            text: page.error
            color: Colors.error
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Quiet {
            id: dismiss

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            icon: "close"
            tint: Colors.error
            onClicked: page.error = ""
        }
    }

    // ================= Vorschau =================
    Item {
        id: previewPanel

        // Natuerliche Masse des Terminal-Blocks (Monospace 12 px, aus
        // TerminalPreview.qml), skaliert in die verfuegbare Breite
        readonly property int cols: page.preview?.budget?.cols ?? page.budget[0]
        readonly property int rows: page.preview?.budget?.rows ?? page.budget[1]
        readonly property bool withCard: page.size !== "mini" && page.cardFor(page.lookId) !== ""
        readonly property real naturalW: screen.item?.naturalW ?? 1
        readonly property real naturalH: screen.item?.naturalH ?? 1
        readonly property real fit: Math.min(page.wide ? 1.25 : 1, previewPanel.width / previewPanel.naturalW,
                                             page.wide ? 1.25 : Math.max(0.35, (page.height * 0.42) / previewPanel.naturalH))

        anchors {
            left: parent.left
            top: errorRow.bottom
            topMargin: 12
        }
        // Breit: die linke Spalte bleibt mindestens 440 breit (Reiter darunter)
        width: page.wide ? Math.max(Math.min(440, page.width - 460), Math.min(page.width - 460, previewPanel.naturalW * 1.25)) : page.width
        height: Math.round(previewPanel.naturalH * previewPanel.fit) + (sizeBar.visible ? sizeBar.height + 6 : 0)

        // Der Terminal-Block (TerminalPreview.qml, geteilt mit der Sektion in
        // der Wallpaper-Auswahl). Plugin-Dateien sehen sich nicht als Typen,
        // deshalb ueber den Pfad; die Werte werden nach dem Laden gebunden.
        Loader {
            id: screen

            scale: previewPanel.fit
            transformOrigin: Item.TopLeft
            opacity: page.preview ? 1 : 0.4

            source: page.plugin.url("TerminalPreview.qml")
            onLoaded: {
                screen.item.monoFont = Qt.binding(() => page.monoFont);
                screen.item.preview = Qt.binding(() => page.preview);
                screen.item.cols = Qt.binding(() => page.budget[0]);
                screen.item.rows = Qt.binding(() => page.budget[1]);
                screen.item.card = Qt.binding(() => previewPanel.withCard ? page.cardFor(page.lookId) : "");
            }
            onStatusChanged: if (screen.status === Loader.Error) page.plugin.log("TerminalPreview.qml laedt nicht")
        }

        // Groessen und Masse – nur, wenn sie im Kopf keinen Platz haben
        Item {
            id: sizeBar

            anchors {
                left: parent.left
                bottom: parent.bottom
            }
            height: visible ? 28 : 0
            visible: page.look !== null && !header.hasSizes

            SizeTabs {
                id: sizeTabs

                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ================= Editor =================
    // Breit: linke Spalte unter der Vorschau (Farben, Darstellung, Karten,
    // Datei); schmal: alles untereinander, die Zeilen als weiterer Reiter
    Item {
        id: editor

        anchors {
            left: parent.left
            right: page.wide ? previewPanel.right : parent.right
            top: previewPanel.bottom
            topMargin: page.wide ? 12 : 10
            bottom: parent.bottom
        }
        visible: page.look !== null

        Row {
            id: tabs

            anchors {
                left: parent.left
                top: parent.top
            }
            spacing: 2

            Repeater {
                model: [
                    { key: "palette", title: "Farben" },
                    { key: "rows", title: "Zeilen", narrow: true },
                    { key: "display", title: "Darstellung" },
                    { key: "cards", title: "Karten" },
                    { key: "raw", title: "Datei" }
                ].filter(t => !t.narrow || !page.wide)

                Tab {
                    required property var modelData

                    label: I18n.tr(modelData.title)
                    current: page.editTab === modelData.key
                    onClicked: page.tab = modelData.key
                }
            }
        }

        Flickable {
            id: flick

            anchors {
                left: parent.left
                right: parent.right
                top: tabs.bottom
                bottom: parent.bottom
                topMargin: 8
            }
            visible: page.editTab !== "rows"
            clip: true
            contentWidth: width
            contentHeight: content.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            onContentHeightChanged: flick.contentY = Math.max(0, Math.min(flick.contentY, flick.contentHeight - flick.height))

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 40;
                    const max = Math.max(0, flick.contentHeight - flick.height);
                    flick.contentY = Math.max(0, Math.min(max, flick.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            Item {
                id: content

                width: flick.width
                implicitHeight: paletteTab.visible ? paletteTab.implicitHeight
                              : displayTab.visible ? displayTab.implicitHeight
                              : cardsTab.visible ? cardsTab.implicitHeight
                              : rawTab.implicitHeight

                // ---------- Farben ----------
                Column {
                    id: paletteTab

                    width: parent.width
                    visible: page.editTab === "palette"
                    spacing: 2

                    Repeater {
                        model: page.paletteNames

                        Rectangle {
                            id: palRow

                            required property string modelData
                            readonly property string hex: page.pal[palRow.modelData] ?? ""
                            readonly property bool editing: page.renaming === palRow.modelData

                            width: parent.width
                            height: 34
                            radius: 9
                            color: palHover.hovered ? Colors.alpha(Colors.fgSurface, 0.06) : "transparent"

                            Rectangle {
                                id: swatch

                                anchors {
                                    left: parent.left
                                    leftMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 24
                                height: 24
                                radius: 7
                                color: palRow.hex
                                border.width: 1
                                border.color: Colors.alpha("#ffffff", 0.18)

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: {
                                        page.colorTarget = { kind: "palette", name: palRow.modelData };
                                        page.pickColor = palRow.hex;
                                        page.openAt("color", swatch);
                                    }
                                }
                            }

                            Text {
                                anchors {
                                    left: swatch.right
                                    leftMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: !palRow.editing
                                font.family: Config.font
                                text: palRow.modelData
                                color: Colors.fgBackground
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            Field {
                                anchors {
                                    left: swatch.right
                                    leftMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 160
                                visible: palRow.editing
                                value: page.renameText
                                onEdited: text => page.renameText = text
                                onFinished: page.finishRename()
                                onVisibleChanged: if (visible) focusInput()
                            }

                            Text {
                                anchors {
                                    right: parent.right
                                    rightMargin: 10
                                    verticalCenter: parent.verticalCenter
                                }
                                font.family: page.monoFont
                                text: palRow.hex
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 11
                            }

                            HoverHandler {
                                id: palHover
                            }

                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: (ev, button) => page.openMenuAt("palmenu", palRow.mapToItem(page, ev.position.x, ev.position.y).x, palRow.mapToItem(page, ev.position.x, ev.position.y).y, palRow.modelData)
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 8
                    }

                    Row {
                        spacing: 4

                        Quiet {
                            icon: "add"
                            label: I18n.tr("Hinzufügen")
                            tint: Colors.fgSurfaceVariant
                            onClicked: page.addPaletteColor()
                        }

                        Quiet {
                            id: suggestButton

                            label: I18n.tr("Vorschläge")
                            chevron: true
                            tint: Colors.fgSurfaceVariant
                            active: ["suggest", "folders", "images"].includes(page.menu) && page.imagesFor === "palette"
                            onClicked: page.menu === "suggest" ? page.closeMenu() : page.openAt("suggest", suggestButton)
                        }
                    }
                }

                // ---------- Darstellung ----------
                Column {
                    id: displayTab

                    width: parent.width
                    visible: page.editTab === "display"
                    spacing: 2

                    Text {
                        font.family: Config.font
                        text: I18n.tr("Für %1").arg(page.size)
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 10
                        bottomPadding: 6
                    }

                    Setting {
                        label: I18n.tr("Trenner")

                        Field {
                            width: 90
                            mono: true
                            value: page.confValue(["display", "separator"]) ?? ""
                            onEdited: text => page.setConf(["display", "separator"], text === "" ? null : text)
                        }
                    }

                    Setting {
                        label: I18n.tr("Farbe der Keys")

                        ColorPick {
                            path: ["display", "color", "keys"]
                        }
                    }

                    Setting {
                        label: I18n.tr("Farbe des Trenners")

                        ColorPick {
                            path: ["display", "color", "separator"]
                        }
                    }

                    Setting {
                        label: I18n.tr("Prozentanzeige")

                        Quiet {
                            id: percentButton

                            label: page.percentLabel()
                            chevron: true
                            active: page.menu === "percent"
                            onClicked: page.menu === "percent" ? page.closeMenu() : page.openAt("percent", percentButton)
                        }
                    }

                    Setting {
                        label: I18n.tr("Balkenzeichen")

                        Field {
                            width: 44
                            mono: true
                            value: page.confValue(["display", "bar", "char", "elapsed"]) ?? ""
                            onEdited: text => page.setConf(["display", "bar", "char", "elapsed"], text === "" ? null : text)
                        }

                        Field {
                            width: 44
                            mono: true
                            value: page.confValue(["display", "bar", "char", "total"]) ?? ""
                            onEdited: text => page.setConf(["display", "bar", "char", "total"], text === "" ? null : text)
                        }
                    }

                    Setting {
                        label: I18n.tr("Balkenbreite")

                        Field {
                            width: 54
                            mono: true
                            value: String(page.confValue(["display", "bar", "width"]) ?? "")
                            onEdited: text => {
                                const n = parseInt(text, 10);
                                page.setConf(["display", "bar", "width"], isNaN(n) ? null : n);
                            }
                        }
                    }

                    Setting {
                        label: I18n.tr("Balken, gefüllt")

                        ColorPick {
                            path: ["display", "bar", "color", "elapsed"]
                        }
                    }

                    Setting {
                        label: I18n.tr("Balken, Rest")

                        ColorPick {
                            path: ["display", "bar", "color", "total"]
                        }
                    }
                }

                // ---------- Karten ----------
                Column {
                    id: cardsTab

                    width: parent.width
                    visible: page.editTab === "cards"
                    spacing: 8

                    Flow {
                        id: cardFlow

                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: page.cards

                            Rectangle {
                                id: cardTile

                                required property var modelData

                                readonly property bool current: page.cardSelected === cardTile.modelData.name
                                readonly property bool inUse: page.cardFor(page.lookId) === cardTile.modelData.path

                                width: 84
                                height: 112
                                radius: 8
                                color: Colors.alpha(Colors.fgSurface, 0.06)
                                border.width: cardTile.current ? 2 : 0
                                border.color: Colors.primary
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: cardTile.current ? 2 : 0
                                    source: "file://" + cardTile.modelData.path
                                    sourceSize: Qt.size(168, 224)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }

                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    onTapped: {
                                        page.cardArmed = false;
                                        page.cardSelected = cardTile.current ? "" : cardTile.modelData.name;
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        spacing: 4

                        Quiet {
                            id: cardAddButton

                            icon: "add"
                            label: I18n.tr("Neue Karte")
                            chevron: true
                            tint: Colors.fgSurfaceVariant
                            active: ["folders", "images", "cardcolor"].includes(page.menu) && page.imagesFor === "card"
                            onClicked: {
                                if (page.menu !== "") {
                                    page.closeMenu();
                                    return;
                                }
                                const folder = page.folderFor(page.lookId);
                                page.imagesFolder = folder !== "" ? folder : (WallManager.folders[0] ?? "");
                                page.imagesFor = "card";
                                page.openAt(page.imagesFolder === "" ? "folders" : "images", cardAddButton);
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: page.cardSelected !== ""
                            leftPadding: 8
                            rightPadding: 4
                            font.family: Config.font
                            text: page.cardSelected
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 11
                        }

                        Quiet {
                            visible: page.cardSelected !== ""
                            icon: page.cardArmed ? "check" : "delete"
                            label: page.cardArmed ? I18n.tr("Wirklich entfernen?") : I18n.tr("Entfernen")
                            tint: Colors.error
                            onClicked: {
                                if (page.cardArmed)
                                    page.removeCard();
                                else {
                                    page.cardArmed = true;
                                    disarmCard.restart();
                                }
                            }
                        }
                    }

                    Timer {
                        id: disarmCard

                        interval: 3000
                        onTriggered: page.cardArmed = false
                    }
                }

                // ---------- Datei ----------
                Column {
                    id: rawTab

                    width: parent.width
                    visible: page.editTab === "raw"
                    spacing: 8

                    Flow {
                        width: parent.width
                        spacing: 4

                        Text {
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            rightPadding: 8
                            font.family: Config.font
                            text: page.rawOn ? I18n.tr("%1.jsonc – eigene Datei").arg(page.size) : I18n.tr("%1.jsonc – erzeugt").arg(page.size)
                            color: Colors.fgSurface
                            font.pixelSize: 12
                        }

                        Quiet {
                            visible: !page.rawOn && !page.rawEditing
                            icon: "edit"
                            label: I18n.tr("Als eigene Datei bearbeiten")
                            onClicked: page.ensureSaved(() => page.rawLoad())
                        }

                        Quiet {
                            visible: page.rawOn && !page.rawEditing
                            icon: "edit"
                            label: I18n.tr("Bearbeiten")
                            onClicked: page.rawLoad()
                        }

                        Quiet {
                            visible: page.rawEditing
                            icon: "save"
                            label: I18n.tr("Datei speichern")
                            filled: true
                            enabled: page.rawText !== page.rawLoaded || !page.rawOn
                            onClicked: page.rawSave()
                        }

                        Quiet {
                            visible: page.rawEditing
                            label: I18n.tr("Abbrechen")
                            tint: Colors.fgSurfaceVariant
                            onClicked: {
                                page.rawEditing = false;
                                page.rawError = "";
                            }
                        }

                        Quiet {
                            visible: page.rawOn
                            label: I18n.tr("Übernehmen")
                            tint: Colors.fgSurfaceVariant
                            onClicked: page.ensureSaved(() => page.rawOff(true))
                        }

                        Quiet {
                            visible: page.rawOn
                            label: I18n.tr("Verwerfen")
                            tint: Colors.error
                            onClicked: page.ensureSaved(() => page.rawOff(false))
                        }
                    }

                    Text {
                        width: parent.width
                        visible: page.rawError !== ""
                        font.family: Config.font
                        text: page.rawError
                        color: Colors.error
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        width: parent.width
                        // Fuellt den Rest der Seite, der Text scrollt darin
                        height: Math.max(200, flick.height - 60 - (page.rawError !== "" ? 24 : 0))
                        visible: page.rawEditing
                        radius: 10
                        color: "#0f0f12"
                        border.width: 1
                        border.color: rawEdit.activeFocus ? Colors.alpha(Colors.primary, 0.5) : Colors.alpha(Colors.outline, 0.3)
                        clip: true

                        Flickable {
                            id: rawFlick

                            anchors.fill: parent
                            anchors.margins: 10
                            contentWidth: Math.max(width, rawEdit.implicitWidth)
                            contentHeight: rawEdit.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: false

                            function ensureVisible(r: rect): void {
                                if (contentY >= r.y)
                                    contentY = r.y;
                                else if (contentY + height <= r.y + r.height)
                                    contentY = r.y + r.height - height;
                            }

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                                onWheel: event => {
                                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 40;
                                    const max = Math.max(0, rawFlick.contentHeight - rawFlick.height);
                                    rawFlick.contentY = Math.max(0, Math.min(max, rawFlick.contentY - delta * 60));
                                    event.accepted = true;
                                }
                            }

                            TextEdit {
                                id: rawEdit

                                width: Math.max(rawFlick.width, implicitWidth)
                                font.family: page.monoFont
                                font.pixelSize: 11
                                color: "#d8d8dc"
                                selectionColor: Colors.alpha(Colors.primary, 0.35)
                                wrapMode: TextEdit.NoWrap
                                tabStopDistance: 32
                                text: page.rawText
                                onTextChanged: if (text !== page.rawText) page.rawText = text
                                onCursorRectangleChanged: rawFlick.ensureVisible(cursorRectangle)
                            }
                        }
                    }
                }
            }
        }

        // Weiche Kante unten
        Rectangle {
            anchors {
                left: flick.left
                right: flick.right
                bottom: flick.bottom
            }
            height: 24
            visible: flick.visible && flick.contentHeight - flick.contentY - flick.height > 2
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                GradientStop { position: 1; color: Colors.background }
            }
        }
    }

    // ================= Zeilen =================
    // Breit: eigene Spalte rechts ueber die volle Hoehe; schmal: Reiter "Zeilen"
    Item {
        id: rowsPanel

        anchors {
            left: page.wide ? previewPanel.right : parent.left
            leftMargin: page.wide ? 20 : 0
            right: parent.right
            top: page.wide ? previewPanel.top : editor.top
            topMargin: page.wide ? 0 : tabs.height + 8
            bottom: parent.bottom
        }
        visible: page.look !== null && (page.wide || page.tab === "rows")

        // Kopf der Spalte: Titel (nur breit), Status "Eigene Datei" fuehrt zum Reiter Datei
        Item {
            id: rowsHead

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: visible ? 28 : 0
            visible: page.wide || page.rawOn

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                visible: page.wide
                font.family: Config.font
                text: I18n.tr("Zeilen")
                color: Colors.fgBackground
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Quiet {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                visible: page.rawOn
                label: I18n.tr("Eigene Datei")
                icon: "description"
                tint: Colors.fgSurfaceVariant
                onClicked: page.tab = "raw"
            }
        }

        Flickable {
            id: rowsFlick

            anchors {
                left: parent.left
                right: parent.right
                top: rowsHead.bottom
                bottom: parent.bottom
                topMargin: page.wide ? 2 : 0
            }
            clip: true
            contentWidth: width
            contentHeight: rowsContent.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            onContentHeightChanged: rowsFlick.contentY = Math.max(0, Math.min(rowsFlick.contentY, rowsFlick.contentHeight - rowsFlick.height))

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 40;
                    const max = Math.max(0, rowsFlick.contentHeight - rowsFlick.height);
                    rowsFlick.contentY = Math.max(0, Math.min(max, rowsFlick.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            Item {
                id: rowsContent

                width: rowsFlick.width
                implicitHeight: rowsTab.y + rowsTab.implicitHeight
                // Eigene Datei fuer diese Groesse: die Liste gilt dann nicht
                opacity: page.rawOn ? 0.35 : 1
                enabled: !page.rawOn

                Behavior on opacity {
                    NumberAnimation { duration: Appearance.fadeDuration }
                }

                HoverHandler {
                    id: gapHover

                    enabled: !page.rawOn
                    onPointChanged: page.updateGap(point.position.y - rowsTab.y)
                    onHoveredChanged: if (!hovered) page.gapIndex = -2
                }

                Column {
                    id: rowsTab

                    // Platz fuer die Einfuegelinie ueber der ersten Zeile
                    y: 6
                    width: parent.width
                    spacing: 1

                    Repeater {
                        id: rowsRepeater

                        // Anzahl statt Liste: jede Aenderung ist ein neues rows-Array,
                        // die Zeilen laesen sich sonst bei jedem Tastendruck neu auf
                        model: page.look?.rows.length ?? 0

                        Rectangle {
                            id: rowItem

                            required property int index

                            readonly property var modelData: page.look?.rows[rowItem.index] ?? ({ m: "break" })
                            readonly property var value: LookModel.rowValue(rowItem.modelData, page.size)
                            readonly property bool present: LookModel.present(rowItem.modelData, page.size)
                            readonly property bool isBreak: rowItem.value === "break" || (rowItem.value === null && rowItem.modelData.m === "break")
                            readonly property bool current: page.selected === rowItem.index
                            readonly property bool dropBefore: page.dragFrom >= 0 && page.dragTo === rowItem.index && page.dragTo < page.dragFrom
                            readonly property bool dropAfter: page.dragFrom >= 0 && page.dragTo === rowItem.index && page.dragTo > page.dragFrom

                            width: parent.width
                            height: 30 + (rowItem.current ? rowEditor.implicitHeight + 10 : 0)
                            radius: 9
                            color: rowItem.current ? Colors.alpha(Colors.primary, 0.1)
                                 : rowHover.hovered ? Colors.alpha(Colors.fgSurface, 0.06) : "transparent"

                            Behavior on height {
                                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                            }

                            // Frisch eingefuegt: kurz aufleuchten, dann ausblenden
                            Rectangle {
                                id: flash

                                readonly property bool flashing: page.flashRow === rowItem.index

                                anchors.fill: parent
                                radius: parent.radius
                                color: Colors.alpha(Colors.primary, 0.35)
                                opacity: flash.flashing ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: flash.flashing ? 120 : 700; easing.type: Easing.OutCubic }
                                }
                            }

                            // Einfuegemarke beim Ziehen
                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 8
                                    rightMargin: 8
                                }
                                y: rowItem.dropBefore ? -1 : rowItem.height - 1
                                height: 2
                                radius: 1
                                visible: rowItem.dropBefore || rowItem.dropAfter
                                color: Colors.primary
                            }

                            Item {
                                id: rowLine

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                height: 30
                                opacity: rowItem.present ? 1 : 0.4

                                // Griff
                                Text {
                                    id: grip

                                    anchors {
                                        left: parent.left
                                        leftMargin: 4
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "drag_indicator"
                                    color: Colors.alpha(Colors.fgSurfaceVariant, rowHover.hovered || rowItem.current ? 0.9 : 0.35)
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.SizeVerCursor
                                        preventStealing: true
                                        onPressed: {
                                            page.dragFrom = rowItem.index;
                                            page.dragTo = rowItem.index;
                                        }
                                        onPositionChanged: mouse => {
                                            if (page.dragFrom < 0)
                                                return;
                                            const y = grip.mapToItem(rowsTab, mouse.x, mouse.y).y;
                                            let target = page.dragFrom;
                                            for (let i = 0; i < rowsRepeater.count; i++) {
                                                const it = rowsRepeater.itemAt(i);
                                                if (!it)
                                                    continue;
                                                if (y >= it.y && y < it.y + it.height)
                                                    target = i;
                                                else if (y >= it.y + it.height)
                                                    target = Math.min(i + 1, rowsRepeater.count - 1);
                                            }
                                            page.dragTo = target;
                                        }
                                        onReleased: {
                                            if (page.dragFrom >= 0 && page.dragTo >= 0)
                                                page.moveRow(page.dragFrom, page.dragTo);
                                            page.dragFrom = -1;
                                            page.dragTo = -1;
                                        }
                                        onCanceled: {
                                            page.dragFrom = -1;
                                            page.dragTo = -1;
                                        }
                                    }
                                }

                                Text {
                                    anchors {
                                        left: grip.right
                                        leftMargin: 6
                                        right: rowMeta.left
                                        rightMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    font.family: rowItem.isBreak ? Config.font : page.monoFont
                                    font.pixelSize: 11
                                    font.italic: rowItem.isBreak
                                    color: rowItem.isBreak ? Colors.fgSurfaceVariant : Colors.fgSurface
                                    textFormat: rowItem.isBreak ? Text.PlainText : Text.StyledText
                                    text: rowItem.isBreak ? I18n.tr("Leerzeile") : page.rowHtml(rowItem.value ?? LookModel.rowValue({ m: rowItem.modelData.m }, page.size))
                                    elide: Text.ElideRight
                                    clip: true
                                }

                                Row {
                                    id: rowMeta

                                    anchors {
                                        right: parent.right
                                        rightMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !rowItem.present
                                        text: "visibility_off"
                                        color: Colors.fgSurfaceVariant
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !rowItem.isBreak && LookModel.isObj(rowItem.modelData.m)
                                        font.family: Config.font
                                        text: page.typeTitle(rowItem.modelData.m?.type ?? "")
                                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                                        font.pixelSize: 10
                                    }
                                }

                                HoverHandler {
                                    id: rowHover
                                }

                                TapHandler {
                                    acceptedButtons: Qt.LeftButton
                                    onTapped: page.selected = rowItem.current ? -1 : rowItem.index
                                }

                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: ev => page.openMenuAt("rowmenu", rowLine.mapToItem(page, ev.position.x, ev.position.y).x, rowLine.mapToItem(page, ev.position.x, ev.position.y).y, rowItem.index)
                                }
                            }

                            // ---- Zeilen-Editor (aufgeklappt) ----
                            Column {
                                id: rowEditor

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: rowLine.bottom
                                    leftMargin: 26
                                    rightMargin: 10
                                }
                                visible: rowItem.current
                                spacing: 6

                                // Umfang und Sichtbarkeit
                                Row {
                                    spacing: 4

                                    Quiet {
                                        id: scopeButton

                                        visible: !rowItem.isBreak
                                        label: page.scope === "all" ? I18n.tr("Alle Größen") : I18n.tr("Nur %1").arg(page.size)
                                        chevron: true
                                        tint: Colors.fgSurfaceVariant
                                        active: page.menu === "scope"
                                        onClicked: page.menu === "scope" ? page.closeMenu() : page.openAt("scope", scopeButton)
                                    }

                                    Item {
                                        width: 6
                                        height: 1
                                    }

                                    Repeater {
                                        model: page.sizes

                                        Quiet {
                                            required property string modelData

                                            label: modelData
                                            active: LookModel.present(rowItem.modelData, modelData)
                                            tint: active ? Colors.fgBackground : Colors.fgSurfaceVariant
                                            onClicked: page.togglePresent(rowItem.index, modelData)
                                        }
                                    }

                                    Item {
                                        width: 6
                                        height: 1
                                    }

                                    Quiet {
                                        icon: "delete"
                                        tint: Colors.error
                                        onClicked: page.removeRow(rowItem.index)
                                    }
                                }

                                // Key
                                Row {
                                    visible: !rowItem.isBreak && page.selectedIsModule && (typeof page.selectedValue.key === "string" || page.selectedValue.type !== "custom")
                                    spacing: 8

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 48
                                        font.family: Config.font
                                        text: "Key"
                                        color: Colors.fgSurfaceVariant
                                        font.pixelSize: 11
                                    }

                                    Field {
                                        width: Math.min(300, rowEditor.width - 60)
                                        mono: true
                                        value: page.selectedValue?.key ?? ""
                                        onEdited: text => page.setRowField("key", text === "" ? undefined : text)
                                    }
                                }

                                // Format als Abschnitte
                                Column {
                                    visible: !rowItem.isBreak && page.selectedIsModule && rowItem.current
                                    width: parent.width
                                    spacing: 3

                                    Text {
                                        font.family: Config.font
                                        text: page.selectedValue?.type === "custom" ? I18n.tr("Text") : "Format"
                                        color: Colors.fgSurfaceVariant
                                        font.pixelSize: 11
                                        bottomPadding: 2
                                    }

                                    Repeater {
                                        model: rowItem.current ? page.segs.length : 0

                                        Row {
                                            id: segRow

                                            required property int index

                                            readonly property var modelData: page.segs[segRow.index] ?? LookModel.emptyStyle()

                                            spacing: 3

                                            Rectangle {
                                                id: segSwatch

                                                width: 28
                                                height: 28
                                                radius: 8
                                                color: page.colorOf(segRow.modelData?.color ?? "") || Colors.alpha(Colors.fgSurface, 0.08)
                                                border.width: 1
                                                border.color: Colors.alpha("#ffffff", 0.18)

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: !segRow.modelData?.color
                                                    text: "format_color_text"
                                                    color: Colors.fgSurfaceVariant
                                                    font.family: "Material Symbols Outlined"
                                                    font.pixelSize: 14
                                                }

                                                HoverHandler {
                                                    cursorShape: Qt.PointingHandCursor
                                                }

                                                TapHandler {
                                                    onTapped: page.openMenuAt("segcolor", segSwatch.mapToItem(page, 0, segSwatch.height).x, segSwatch.mapToItem(page, 0, segSwatch.height).y + 4, segRow.index)
                                                }
                                            }

                                            Repeater {
                                                model: [
                                                    { key: "bold", icon: "format_bold" },
                                                    { key: "italic", icon: "format_italic" },
                                                    { key: "dim", icon: "opacity" },
                                                    { key: "underline", icon: "format_underlined" }
                                                ]

                                                Quiet {
                                                    required property var modelData

                                                        icon: modelData.icon
                                                    active: segRow.modelData?.[modelData.key] === true
                                                    tint: active ? Colors.fgBackground : Colors.fgSurfaceVariant
                                                    onClicked: {
                                                        const p = {};
                                                        p[modelData.key] = !active;
                                                        page.setSeg(segRow.index, p);
                                                    }
                                                }
                                            }

                                            Field {
                                                width: Math.max(80, rowEditor.width - 26 - 4 * 30 - 30 - 24)
                                                mono: true
                                                value: segRow.modelData?.text ?? ""
                                                onEdited: text => page.setSeg(segRow.index, { text: text })
                                            }

                                            Quiet {
                                                icon: "close"
                                                tint: Colors.fgSurfaceVariant
                                                onClicked: page.removeSeg(segRow.index)
                                            }
                                        }
                                    }

                                    Quiet {
                                        icon: "add"
                                        label: I18n.tr("Abschnitt")
                                        tint: Colors.fgSurfaceVariant
                                        onClicked: page.addSeg()
                                    }
                                }

                                // Weitere Textfelder des Moduls (text, folders, …)
                                Repeater {
                                    model: rowItem.current && page.selectedIsModule
                                        ? Object.keys(page.selectedValue).filter(k => !["type", "key", "format"].includes(k) && typeof page.selectedValue[k] === "string")
                                        : []

                                    Row {
                                        id: extraRow

                                        required property string modelData

                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 48
                                            font.family: Config.font
                                            text: extraRow.modelData
                                            color: Colors.fgSurfaceVariant
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }

                                        Field {
                                            width: Math.min(300, rowEditor.width - 60)
                                            mono: true
                                            value: page.selectedValue?.[extraRow.modelData] ?? ""
                                            onEdited: text => page.setRowField(extraRow.modelData, text)
                                        }
                                    }
                                }

                                Item {
                                    width: 1
                                    height: 2
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 8
                    }

                    Quiet {
                        id: addButton

                        icon: "add"
                        label: I18n.tr("Hinzufügen")
                        chevron: true
                        tint: Colors.fgSurfaceVariant
                        active: page.menu === "modules"
                        onClicked: {
                            if (page.menu === "modules") {
                                page.closeMenu();
                                return;
                            }
                            const pos = addButton.mapToItem(page, 0, addButton.height);
                            page.insertAt(page.selected >= 0 ? page.selected : page.look.rows.length - 1, pos.x, pos.y + 4);
                        }
                    }
                }


                // Einfuegelinie zwischen zwei Zeilen (Hover), Klick oeffnet die Module
                Item {
                    id: gapLine

                    readonly property Item anchorRow: page.gapIndex >= -1 ? rowsRepeater.itemAt(Math.max(0, page.gapIndex)) : null

                    width: parent.width
                    height: 12
                    y: gapLine.anchorRow ? rowsTab.y + (page.gapIndex < 0 ? gapLine.anchorRow.y : gapLine.anchorRow.y + gapLine.anchorRow.height) - 6 : 0
                    z: 2
                    visible: page.gapIndex >= -1 && page.dragFrom < 0 && gapLine.anchorRow !== null

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 20
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        height: 2
                        radius: 1
                        color: Colors.primary
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            leftMargin: 2
                            verticalCenter: parent.verticalCenter
                        }
                        width: 16
                        height: 16
                        radius: 8
                        color: Colors.primary

                        Text {
                            anchors.centerIn: parent
                            text: "add"
                            color: Colors.fgPrimary
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            const pos = gapLine.mapToItem(page, 0, gapLine.height);
                            page.insertAt(page.gapIndex, pos.x + 20, pos.y);
                        }
                    }
                }
            }
        }

        // Weiche Kante unten
        Rectangle {
            anchors {
                left: rowsFlick.left
                right: rowsFlick.right
                bottom: rowsFlick.bottom
            }
            height: 24
            visible: rowsFlick.contentHeight - rowsFlick.contentY - rowsFlick.height > 2
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                GradientStop { position: 1; color: Colors.background }
            }
        }
    }

    // ================= Popover =================
    MouseArea {
        anchors.fill: parent
        visible: page.menu !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: page.closeMenu()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: popover

        readonly property bool isColor: page.menu === "color"
        readonly property bool isNew: page.menu === "new"
        readonly property bool hasCards: page.menu === "looks"
        readonly property bool hasThumbs: page.menu === "images"
        readonly property real pad: 6

        visible: page.menu !== ""
        width: popover.isColor ? 232 : popover.isNew ? 300 : popover.hasCards || popover.hasThumbs ? 280 : 230
        height: Math.min(page.height - 8, popoverColumn.implicitHeight + popover.pad * 2)
        x: Math.max(0, Math.min(page.width - popover.width, page.menuX))
        y: Math.max(0, Math.min(page.height - popover.height, page.menuY))
        radius: 14
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.outlineVariant
        clip: true

        opacity: page.menu !== "" ? 1 : 0
        scale: page.menu !== "" ? 1 : 0.96
        transformOrigin: Item.Top

        Behavior on opacity {
            NumberAnimation { duration: Appearance.fadeDuration }
        }
        Behavior on scale {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        Flickable {
            id: popFlick

            anchors.fill: parent
            anchors.margins: popover.pad
            clip: true
            contentHeight: popoverColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 40;
                    const max = Math.max(0, popFlick.contentHeight - popFlick.height);
                    popFlick.contentY = Math.max(0, Math.min(max, popFlick.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            Column {
                id: popoverColumn

                width: parent.width
                spacing: 1

                // Kopf
                Item {
                    width: parent.width
                    height: page.popTitle !== "" ? 30 : 0
                    visible: page.popTitle !== ""

                    Quiet {
                        id: backButton

                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        visible: page.popSub
                        icon: "arrow_back"
                        tint: Colors.fgSurfaceVariant
                        onClicked: page.popBack()
                    }

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: page.popSub ? backButton.width + 2 : 10
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        font.family: Config.font
                        text: page.popTitle
                        color: Colors.fgBackground
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                // ---- Suche (Module) ----
                Item {
                    width: parent.width
                    height: 34
                    visible: page.menu === "modules"

                    Field {
                        id: moduleSearch

                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 4
                            rightMargin: 4
                            verticalCenter: parent.verticalCenter
                        }
                        value: page.moduleFilter
                        placeholder: I18n.tr("Suchen…")
                        onVisibleChanged: if (visible) focusInput()
                        onEdited: text => page.moduleFilter = text
                        // Eingabe nimmt den ersten Treffer
                        onAccepted: if (page.popRows.length > 0) page.popRows[0].action()
                    }
                }

                // ---- Listen ----
                Repeater {
                    model: popover.isColor || popover.isNew ? [] : page.popRows

                    Rectangle {
                        id: prow

                        required property var modelData

                        readonly property bool current: prow.modelData.current === true
                        readonly property bool on: prow.modelData.enabled !== false
                        readonly property bool big: (prow.modelData.card ?? "") !== "" || (prow.modelData.thumb ?? "") !== "" || popover.hasCards
                        readonly property color fg: prow.modelData.danger === true ? Colors.error : prow.current ? Colors.fgBackground : Colors.fgSurface

                        width: parent.width
                        height: prow.big ? 44 : 30
                        radius: 9
                        opacity: prow.on ? 1 : 0.45
                        color: prow.current ? Colors.alpha(Colors.primary, 0.14)
                             : prowHover.hovered && prow.on ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }

                        Item {
                            id: lead

                            anchors {
                                left: parent.left
                                leftMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            width: prow.big ? ((prow.modelData.thumb ?? "") !== "" ? 48 : 27) : 18
                            height: prow.big ? 36 : 18

                            Rectangle {
                                anchors.fill: parent
                                visible: prow.big && ((prow.modelData.card ?? "") !== "" || (prow.modelData.thumb ?? "") !== "")
                                radius: 5
                                color: Colors.alpha(Colors.fgSurface, 0.08)
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: (prow.modelData.thumb ?? "") !== "" ? prow.modelData.thumb
                                          : (prow.modelData.card ?? "") !== "" ? "file://" + prow.modelData.card : ""
                                    sourceSize: Qt.size(96, 72)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: (prow.modelData.swatch ?? "") !== ""
                                width: 16
                                height: 16
                                radius: 5
                                color: prow.modelData.swatch ?? "transparent"
                                border.width: 1
                                border.color: Colors.alpha("#ffffff", 0.18)
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: (prow.modelData.icon ?? "") !== "" && (prow.modelData.card ?? "") === "" && (prow.modelData.thumb ?? "") === ""
                                text: prow.modelData.icon ?? ""
                                color: prow.modelData.danger === true ? Colors.error : prow.current ? Colors.primary : Colors.fgSurfaceVariant
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 16
                            }
                        }

                        Column {
                            anchors {
                                left: lead.right
                                right: trailing.left
                                leftMargin: 9
                                rightMargin: 4
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            Text {
                                width: parent.width
                                font.family: Config.font
                                text: prow.modelData.title ?? ""
                                color: prow.fg
                                font.pixelSize: 11
                                font.weight: prow.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: prow.big && (prow.modelData.desc ?? "") !== ""
                                font.family: page.monoFont
                                text: prow.modelData.desc ?? ""
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            id: trailing

                            anchors {
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !prow.big && (prow.modelData.desc ?? "") !== ""
                                font.family: page.monoFont
                                text: prow.modelData.desc ?? ""
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 10
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: prow.current || prow.modelData.sub === true
                                text: prow.current && prow.modelData.sub !== true ? "check" : "chevron_right"
                                color: prow.current ? Colors.primary : Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 15
                            }
                        }

                        HoverHandler {
                            id: prowHover

                            cursorShape: prow.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }

                        TapHandler {
                            enabled: prow.on
                            onTapped: prow.modelData.action()
                        }
                    }
                }

                // ---- Farbwaehler ----
                Column {
                    id: picker

                    readonly property real hue: picker.h
                    property real h: 0
                    property real s: 0
                    property real v: 0

                    width: parent.width
                    visible: popover.isColor
                    spacing: 8
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 6

                    function load(c: color): void {
                        picker.h = Math.max(0, c.hsvHue);
                        picker.s = c.hsvSaturation;
                        picker.v = c.hsvValue;
                    }

                    function apply(): void {
                        const c = Qt.hsva(picker.h, picker.s, picker.v, 1);
                        const hex = c.toString();
                        page.pickColor = hex;
                        const t = page.colorTarget;
                        if (!t)
                            return;
                        if (t.kind === "palette")
                            page.setPaletteColor(t.name, hex);
                        else if (t.kind === "segment")
                            page.setSeg(t.index, { color: hex });
                    }

                    Connections {
                        target: page

                        function onMenuChanged(): void {
                            if (page.menu === "color")
                                picker.load(page.pickColor);
                        }
                    }

                    // Saettigung / Helligkeit
                    Rectangle {
                        id: svArea

                        width: parent.width - 12
                        height: 140
                        radius: 8
                        color: Qt.hsva(picker.h, 1, 1, 1)
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#ffffff" }
                                GradientStop { position: 1; color: "#00ffffff" }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#00000000" }
                                GradientStop { position: 1; color: "#000000" }
                            }
                        }

                        Rectangle {
                            x: picker.s * svArea.width - 6
                            y: (1 - picker.v) * svArea.height - 6
                            width: 12
                            height: 12
                            radius: 6
                            color: "transparent"
                            border.width: 2
                            border.color: picker.v > 0.6 && picker.s < 0.5 ? "#000000" : "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            preventStealing: true
                            function pick(mx: real, my: real): void {
                                picker.s = Math.max(0, Math.min(1, mx / svArea.width));
                                picker.v = Math.max(0, Math.min(1, 1 - my / svArea.height));
                                picker.apply();
                            }
                            onPressed: mouse => pick(mouse.x, mouse.y)
                            onPositionChanged: mouse => { if (pressed) pick(mouse.x, mouse.y); }
                        }
                    }

                    // Farbton
                    Rectangle {
                        id: hueBar

                        width: parent.width - 12
                        height: 14
                        radius: 7
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#ff0000" }
                            GradientStop { position: 1 / 6; color: "#ffff00" }
                            GradientStop { position: 2 / 6; color: "#00ff00" }
                            GradientStop { position: 3 / 6; color: "#00ffff" }
                            GradientStop { position: 4 / 6; color: "#0000ff" }
                            GradientStop { position: 5 / 6; color: "#ff00ff" }
                            GradientStop { position: 1; color: "#ff0000" }
                        }

                        Rectangle {
                            x: picker.h * hueBar.width - 4
                            y: -2
                            width: 8
                            height: 18
                            radius: 4
                            color: "transparent"
                            border.width: 2
                            border.color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            preventStealing: true
                            function pick(mx: real): void {
                                picker.h = Math.max(0, Math.min(0.9999, (mx - 4) / hueBar.width));
                                picker.apply();
                            }
                            onPressed: mouse => pick(mouse.x)
                            onPositionChanged: mouse => { if (pressed) pick(mouse.x); }
                        }
                    }

                    Row {
                        spacing: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: 8
                            color: page.pickColor
                            border.width: 1
                            border.color: Colors.alpha("#ffffff", 0.18)
                        }

                        Field {
                            id: hexField

                            anchors.verticalCenter: parent.verticalCenter
                            width: 110
                            mono: true
                            value: page.pickColor.toString()
                            onEdited: text => {
                                if (/^#[0-9a-fA-F]{6}$/.test(text.trim())) {
                                    picker.load(text.trim());
                                    picker.apply();
                                }
                            }
                        }
                    }
                }

                // ---- Neuer Look ----
                Column {
                    id: newForm

                    readonly property bool valid: /^[a-z0-9][a-z0-9._-]{0,63}$/.test(page.cleanId(page.newName))
                                                  && !(page.svc?.looks ?? []).some(l => l.id === page.cleanId(page.newName))
                    // Wallpaper-Ordner ohne eigenen Look
                    readonly property var free: WallManager.folders.filter(f => !(page.svc?.looks ?? []).some(l => l.id === f.split("/").pop().toLowerCase()))

                    width: parent.width
                    visible: popover.isNew
                    spacing: 6
                    leftPadding: 6
                    rightPadding: 6
                    bottomPadding: 6

                    Field {
                        width: parent.width - 12
                        value: page.newName
                        mono: true
                        placeholder: I18n.tr("Ordnername (klein)")
                        onEdited: text => {
                            page.newName = page.cleanId(text);
                            page.newTitle = page.prettyTitle(page.newName);
                        }
                    }

                    // Vorschlaege: Ordner ohne Look
                    Flow {
                        width: parent.width - 12
                        spacing: 2
                        visible: newForm.free.length > 0 && page.newName.trim() === ""

                        Repeater {
                            model: newForm.free

                            Quiet {
                                required property string modelData

                                icon: "folder"
                                label: modelData.split("/").pop()
                                tint: Colors.fgSurfaceVariant
                                onClicked: {
                                    page.newName = modelData.split("/").pop().toLowerCase();
                                    page.newTitle = modelData.split("/").pop();
                                }
                            }
                        }
                    }

                    Field {
                        width: parent.width - 12
                        value: page.newTitle
                        placeholder: I18n.tr("Titel")
                        onEdited: text => page.newTitle = text
                    }

                    Flow {
                        width: parent.width - 12
                        spacing: 2

                        Text {
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 4
                            rightPadding: 4
                            font.family: Config.font
                            text: I18n.tr("Vorlage")
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 11
                        }

                        Repeater {
                            model: page.svc?.looks ?? []

                            Quiet {
                                required property var modelData

                                label: I18n.tr(modelData.title)
                                active: page.newFrom === modelData.id
                                tint: active ? Colors.fgBackground : Colors.fgSurfaceVariant
                                onClicked: page.newFrom = modelData.id
                            }
                        }
                    }

                    Row {
                        spacing: 4

                        Quiet {
                            label: I18n.tr("Anlegen")
                            filled: true
                            enabled: newForm.valid
                            onClicked: page.createLook()
                        }

                        Quiet {
                            label: I18n.tr("Abbrechen")
                            tint: Colors.fgSurfaceVariant
                            onClicked: page.closeMenu()
                        }
                    }
                }
            }
        }
    }
}
