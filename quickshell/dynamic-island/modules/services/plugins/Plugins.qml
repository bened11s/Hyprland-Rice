pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

import qs.modules.services.config
import qs.modules.services.hypr

// Plugin-System der Shell.
//
// Ein Plugin ist ein Ordner unter `plugins/<id>/` (neben shell.qml) mit
// einem Manifest `plugin.json` und optional QML-Dateien. Format und API
// stehen in plugins/README.md; kurz:
//
//   plugin.json   id, name, version, api, description, icon, defaultEnabled,
//                 main (Dienst, laeuft solange das Plugin an ist),
//                 settings (Schluessel -> { default, title, desc, options,
//                 min/max/step/unit, requires }), tiles (Schnellkacheln),
//                 panels (Sektionen in Ansichten der Shell, z.B. der
//                 Wallpaper-Auswahl), files (externe Dateien, die zum Plugin
//                 gehoeren – fuer Export/Import ueber `dynamic-island plugin`),
//                 parent (Komponente eines anderen Plugins, laeuft nur mit
//                 diesem und steht in der Verwaltung in dessen Untermenue),
//                 keybinds (Tastenkuerzel in Hyprland, solange das Plugin an ist)
//
// Zustand (an/aus + Einstellungswerte) liegt pro Rechner in
//   ~/.config/dynamic-island/plugins.json
// – geschrieben nur hier und von der CLI; der Watcher liest Fremdaenderungen.
//
// Das Einstellungs-Fenster zeigt jedes aktive Plugin mit Einstellungen als
// eigene Gruppe "plugin:<id>". Damit es dafuer nichts Besonderes kennen
// muss, stehen hier get/set/reset/isDefault/satisfied/metaFor mit derselben
// Signatur wie in Config – sie leiten normale Gruppen an Config weiter.
//
// Benutzung:  import qs.modules.services.plugins
Singleton {
    id: root

    // Version der Plugin-API. Ein Plugin mit groesserem `api` wird nicht geladen.
    readonly property int apiVersion: 1
    readonly property string dir: Quickshell.shellPath("plugins")
    readonly property string statePath: Quickshell.env("DYNAMIC_ISLAND_PLUGINS_FILE")
                                        || Quickshell.env("HOME") + "/.config/dynamic-island/plugins.json"
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/dynamic-island/plugins"
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/dynamic-island/plugins"
    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/dynamic-island"

    // { format, enabled: { id: bool }, settings: { id: { key: value } } }
    property var state: ({ format: 1, enabled: {}, settings: {} })
    property bool stateLoaded: false

    // Alle gefundenen Plugins (PluginHost), nach Name sortiert
    readonly property var hosts: {
        const list = [];
        for (const h of hostVariants.instances)
            if (h)
                list.push(h);
        return list.sort((a, b) => a.name.localeCompare(b.name));
    }

    // Kurzinfo je Plugin fuer die Oberflaeche:
    // { id, name, version, author, description, icon, enabled, status, error,
    //   hasSettings, settingsCount, tiles: [ids], actions: n, files: n, dir, main }
    // status: "invalid" (Manifest kaputt) | "off" | "loading" | "ready" | "error"
    readonly property var plugins: root.hosts.map(h => h.info)

    // Was die Verwaltung oben zeigt: alles ausser Komponenten (Manifest
    // `parent`) – die stehen im Untermenue ihres Eltern-Plugins. Fehlt das
    // Eltern-Plugin, bleibt die Komponente oben, damit man sie findet.
    readonly property var topLevel: root.plugins.filter(p => p.parent === "" || p.parentMissing)

    function childrenOf(id: string): var {
        return root.plugins.filter(p => p.parent === id && !p.parentMissing);
    }

    function host(id: string): var {
        return root.hosts.find(h => h.pluginId === id) ?? null;
    }

    // ---- an / aus -----------------------------------------------------------

    function isEnabled(id: string): bool {
        const h = root.host(id);
        const on = root.state.enabled?.[id];
        return on === undefined ? !!h?.manifest?.defaultEnabled : !!on;
    }

    function setEnabled(id: string, on: bool): void {
        const next = root.copyState();
        next.enabled[id] = on;
        root.commit(next);
    }

    function toggle(id: string): void {
        root.setEnabled(id, !root.isEnabled(id));
    }

    // ---- Einstellungen ------------------------------------------------------

    readonly property string sectionPrefix: "plugin:"

    function isPluginSection(section: string): bool {
        return section.startsWith(root.sectionPrefix);
    }

    function idOf(section: string): string {
        return section.slice(root.sectionPrefix.length);
    }

    // Gruppen fuer das Menue: aktive, gueltige Plugins mit Einstellungen
    readonly property var sections: root.hosts.filter(h => h.enabled && h.valid && h.settingKeys.length > 0)
                                              .map(h => root.sectionPrefix + h.pluginId)

    function sectionTitle(section: string): string {
        return root.host(root.idOf(section))?.name ?? section;
    }

    function sectionIcon(section: string): string {
        return root.host(root.idOf(section))?.icon ?? "extension";
    }

    // Wie Config.raw, nur fuer die Plugin-Gruppen (Werte mit Vorgaben gefuellt)
    readonly property var raw: {
        const out = {};
        for (const h of root.hosts)
            if (h.valid && h.settingKeys.length > 0)
                out[root.sectionPrefix + h.pluginId] = h.settings;
        return out;
    }

    // Wie Config.meta: "plugin:<id>.<key>" -> { title, desc, options, ... }.
    // `requires` ist schon voll qualifiziert ("theme" -> "plugin:<id>.theme").
    readonly property var meta: {
        const out = {};
        for (const h of root.hosts) {
            if (!h.valid)
                continue;
            for (const key of h.settingKeys)
                out[`${root.sectionPrefix}${h.pluginId}.${key}`] = h.settingMeta(key);
        }
        return out;
    }

    function metaFor(id: string): var {
        return root.meta[id] ?? Config.meta[id] ?? null;
    }

    function get(section: string, key: string): var {
        if (!root.isPluginSection(section))
            return Config.get(section, key);
        return root.host(root.idOf(section))?.settings[key];
    }

    function set(section: string, key: string, value: var): void {
        if (!root.isPluginSection(section)) {
            Config.set(section, key, value);
            return;
        }
        const id = root.idOf(section);
        const next = root.copyState();
        next.settings[id] = Object.assign({}, next.settings[id] ?? {});
        next.settings[id][key] = value;
        root.commit(next);
    }

    function defaultOf(section: string, key: string): var {
        if (!root.isPluginSection(section))
            return Config.defaults[section]?.[key];
        return root.host(root.idOf(section))?.manifest?.settings?.[key]?.default;
    }

    function reset(section: string, key: string): void {
        if (!root.isPluginSection(section)) {
            Config.reset(section, key);
            return;
        }
        const id = root.idOf(section);
        const next = root.copyState();
        if (next.settings[id]) {
            next.settings[id] = Object.assign({}, next.settings[id]);
            delete next.settings[id][key];
        }
        root.commit(next);
    }

    function isDefault(section: string, key: string): bool {
        if (!root.isPluginSection(section))
            return Config.isDefault(section, key);
        const d = root.defaultOf(section, key);
        const v = root.get(section, key);
        return typeof d === "object" ? JSON.stringify(d) === JSON.stringify(v) : d === v;
    }

    // Alle Einstellungen eines Plugins auf die Vorgaben
    function resetPlugin(id: string): void {
        const next = root.copyState();
        delete next.settings[id];
        root.commit(next);
    }

    // Wie Config.satisfied, versteht aber auch "plugin:<id>.<key>"
    function satisfied(req: var): bool {
        if (!req)
            return true;
        const split = id => {
            const dot = id.lastIndexOf(".");
            return [id.slice(0, dot), id.slice(dot + 1)];
        };
        if (typeof req === "string") {
            const [s, k] = split(req);
            return !!root.get(s, k);
        }
        for (const id in req) {
            const [s, k] = split(id);
            if (root.get(s, k) !== req[id])
                return false;
        }
        return true;
    }

    // ---- Beitraege der Plugins ----------------------------------------------

    // Schnellkacheln aktiver Plugins: "<plugin>.<kachel>" -> { label, icon,
    // kind, url, plugin (PluginContext), pluginId }. QuickLayout haengt sie
    // an seine eingebauten Kacheln, SettingsTiles laedt `url`.
    readonly property var tiles: {
        const out = {};
        for (const h of root.hosts) {
            if (!h.enabled || !h.valid)
                continue;
            const tiles = h.manifest.tiles ?? {};
            for (const tid in tiles) {
                const t = tiles[tid];
                if (!t?.component)
                    continue;
                out[`${h.pluginId}.${tid}`] = {
                    label: t.label ?? tid,
                    icon: t.icon ?? h.icon,
                    kind: ["pill", "circle", "wide"].includes(t.kind) ? t.kind : "pill",
                    url: h.url(t.component),
                    plugin: h.context,
                    pluginId: h.pluginId
                };
            }
        }
        return out;
    }

    Binding {
        target: QuickLayout
        property: "extraTiles"
        value: root.tiles
    }

    // Sektionen in Ansichten der Shell: "<ansicht>" -> [{ pluginId, icon, url,
    // plugin (PluginContext) }], je Plugin hoechstens eine je Ansicht
    // (Manifest `panels`). Einzige Ansicht bisher: "wallpaper" – die
    // Wallpaper-Auswahl haengt sie unter ihre lokale Reihe (WallpaperPanel,
    // Vertrag in plugins/README.md). Hat das Plugin einen Dienst (`main`),
    // erscheint die Sektion erst, wenn er laeuft – sie greift ueber
    // plugin.main darauf zu.
    readonly property var panels: {
        const out = {};
        for (const h of root.hosts) {
            if (!h.enabled || !h.valid || (h.manifest.main && !h.instance))
                continue;
            const panels = h.manifest.panels ?? {};
            for (const name in panels) {
                const p = panels[name];
                if (!p?.component)
                    continue;
                if (!out[name])
                    out[name] = [];
                out[name].push({
                    pluginId: h.pluginId,
                    icon: p.icon ?? h.icon,
                    url: h.url(p.component),
                    plugin: h.context
                });
            }
        }
        return out;
    }

    // Seiten im Einstellungs-Fenster (Manifest `pages`): [{ key: "<plugin>/<seite>",
    // pluginId, pluginName, page, title, icon, url, plugin }]. SettingsCard
    // haengt sie als Unterpunkte an die Gruppe des Plugins und laedt `url`
    // mit { plugin, args } statt der Zeilenliste. Gleiche Regel wie bei
    // `panels`: mit Dienst erst, wenn er laeuft. Gruppen-Schluessel in der
    // Karte: pagePrefix + key ("@page:terminal/looks").
    readonly property string pagePrefix: "@page:"
    readonly property var pages: {
        const out = [];
        for (const h of root.hosts) {
            if (!h.enabled || !h.valid || (h.manifest.main && !h.instance))
                continue;
            const pages = h.manifest.pages ?? {};
            for (const name in pages) {
                const p = pages[name];
                if (!p?.component)
                    continue;
                out.push({
                    key: `${h.pluginId}/${name}`,
                    pluginId: h.pluginId,
                    pluginName: h.name,
                    page: name,
                    title: p.title ?? name,
                    icon: p.icon ?? h.icon,
                    url: h.url(p.component),
                    plugin: h.context
                });
            }
        }
        return out;
    }

    function pageSection(key: string): string {
        return root.pagePrefix + key;
    }

    function isPageSection(section: string): bool {
        return section.startsWith(root.pagePrefix);
    }

    // Seite zu einem Gruppen-Schluessel, null wenn es sie (gerade) nicht gibt
    function pageFor(section: string): var {
        if (!root.isPageSection(section))
            return null;
        const key = section.slice(root.pagePrefix.length);
        return root.pages.find(p => p.key === key) ?? null;
    }

    // Desktop-Widgets (Manifest `widgets`): "<typ>" -> { pluginId, pluginName,
    // title, desc, icon, url, size, options, plugin }. Gleiche Regel wie bei `panels`: mit Dienst
    // erst, wenn er laeuft. Die Liste der Typen fuehrt DesktopWidgets.qml
    // mit den eingebauten zusammen (Vertrag in plugins/README.md).
    readonly property var widgets: {
        const out = {};
        for (const h of root.hosts) {
            if (!h.enabled || !h.valid || (h.manifest.main && !h.instance))
                continue;
            const widgets = h.manifest.widgets ?? {};
            for (const type in widgets) {
                const w = widgets[type];
                if (!w?.component)
                    continue;
                out[type] = {
                    pluginId: h.pluginId,
                    pluginName: h.name,
                    title: w.title ?? type,
                    desc: w.desc ?? "",
                    icon: w.icon ?? h.icon,
                    url: h.url(w.component),
                    size: Array.isArray(w.size) ? w.size : [10, 6],
                    options: w.options ?? {},
                    plugin: h.context
                };
            }
        }
        return out;
    }

    // Tastenkuerzel aktiver Plugins (Manifest `keybinds`): Keybinds.qml
    // schreibt sie nach Hyprland und nimmt sie beim Ausschalten wieder raus.
    // `ipc` wird zum Aufruf von ipc(cmd, arg) im Main-Objekt, `exec` ist ein
    // Shell-Befehl.
    readonly property var keybinds: {
        const out = [];
        const quote = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
        for (const h of root.hosts) {
            if (!h.enabled || !h.valid)
                continue;
            const binds = h.manifest.keybinds ?? {};
            for (const bid in binds) {
                const b = binds[bid];
                const exec = b.exec ?? `qs -c dynamic-island ipc call plugins call ${h.pluginId} ${quote(b.ipc)} ${quote(b.arg ?? "_")}`;
                out.push({
                    ref: `plugin:${h.pluginId}.${bid}`,
                    pluginId: h.pluginId,
                    pluginName: h.name,
                    group: b.group ?? h.name,
                    title: b.title,
                    keys: b.keys,
                    exec,
                    release: b.release === true,
                    repeating: b.repeating === true,
                    locked: b.locked === true
                });
            }
        }
        return out;
    }

    Binding {
        target: Keybinds
        property: "pluginBinds"
        value: root.keybinds
    }

    Binding {
        target: Keybinds
        property: "pluginsReady"
        value: root.stateLoaded && root.folderNames.length > 0 && root.hosts.length === root.folderNames.length
    }

    // Launcher-Aktionen aus `actions` der Main-Objekte (gleiches Format wie
    // LauncherActions); ohne eigenes Symbol gilt das des Plugins
    readonly property var actions: {
        const out = [];
        for (const h of root.hosts) {
            const list = h.instance?.actions;
            if (!h.enabled || !list)
                continue;
            for (const a of list)
                out.push(Object.assign({ icon: h.icon, desc: h.name }, a));
        }
        return out;
    }

    // ---- Import / Export (ueber die CLI) ------------------------------------

    // Letztes Ergebnis eines CLI-Aufrufs: { op, ok, message, data }
    property var lastResult: null
    readonly property bool busy: cliProc.running

    function exportPlugin(id: string, target: string, withSettings: bool): void {
        const args = ["plugin", "export", id, "-o", target, "--json"];
        if (!withSettings)
            args.push("--no-settings");
        root.runCli("export", args);
    }

    // `parent`: nur Komponenten dieses Plugins annehmen (Import aus dessen
    // Untermenue)
    function importPlugin(file: string, enable: bool, parent: string): void {
        const args = ["plugin", "import", file, "--yes", "--json"];
        if (enable)
            args.push("--enable");
        if (parent)
            args.push("--parent", parent);
        root.runCli("import", args);
    }

    function removePlugin(id: string): void {
        root.runCli("remove", ["plugin", "remove", id, "--yes", "--json"]);
    }

    function runCli(op: string, args: var): void {
        if (cliProc.running)
            return;
        cliProc.op = op;
        cliProc.command = [root.cli].concat(args);
        cliProc.running = true;
    }

    Process {
        id: cliProc

        property string op: ""

        stdout: StdioCollector { id: cliOut }
        stderr: StdioCollector { id: cliErr }

        onExited: code => {
            let data = null;
            try {
                data = JSON.parse(cliOut.text);
            } catch (e) {}
            root.lastResult = {
                op: cliProc.op,
                ok: code === 0,
                message: data?.message ?? (cliErr.text.trim() || cliOut.text.trim()),
                data
            };
            folder.rescan();
        }
    }

    // ---- Aufrufe von aussen -------------------------------------------------

    // Freie Kommandos an ein Plugin: Main.qml kann `function ipc(cmd, arg): string`
    // anbieten. qs -c dynamic-island ipc call plugins call terminal status ""
    IpcHandler {
        target: "plugins"

        function list(): string {
            return JSON.stringify(root.plugins.map(p => ({
                id: p.id, name: p.name, version: p.version, parent: p.parent, enabled: p.enabled, status: p.status, error: p.error
            })), null, 2);
        }
        function enable(id: string): void { root.setEnabled(id, true); }
        function disable(id: string): void { root.setEnabled(id, false); }
        function toggle(id: string): void { root.toggle(id); }
        function rescan(): void { folder.rescan(); }
        function reload(id: string): void { root.host(id)?.reload(); }
        function call(id: string, cmd: string, arg: string): string {
            const inst = root.host(id)?.instance;
            if (!inst || typeof inst.ipc !== "function")
                return "error: plugin not running or has no ipc()";
            return String(inst.ipc(cmd, arg) ?? "");
        }
    }

    // ---- Zustand lesen / schreiben ------------------------------------------

    function copyState(): var {
        return {
            format: 1,
            enabled: Object.assign({}, root.state.enabled ?? {}),
            settings: Object.assign({}, root.state.settings ?? {})
        };
    }

    function commit(next: var): void {
        root.state = next;
        saveGuard.restart();
        stateFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function readState(): void {
        let parsed;
        try {
            parsed = JSON.parse(stateFile.text() || "{}");
        } catch (e) {
            // Halb geschrieben – beim naechsten Signal wieder
            return;
        }
        root.state = {
            format: 1,
            enabled: parsed.enabled ?? {},
            settings: parsed.settings ?? {}
        };
        root.stateLoaded = true;
    }

    // Nach setText meldet der Watcher kurz noch den alten Dateistand (siehe
    // QuickLayout.qml) – eigene Schreibvorgaenge deshalb kurz nicht einlesen
    Timer {
        id: saveGuard

        interval: 400
    }

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: if (!saveGuard.running) root.readState()
        onLoadFailed: root.stateLoaded = true
        onFileChanged: if (!saveGuard.running) reload()
    }

    // ---- Ordner finden ------------------------------------------------------

    // Ordnernamen unter plugins/ (ohne versteckte, "_"-Ordner sind Vorlagen)
    property var folderNames: []

    FolderListModel {
        id: folder

        function rescan(): void {
            const out = [];
            for (let i = 0; i < folder.count; i++) {
                const n = folder.get(i, "fileName");
                if (!n.startsWith("_") && !n.startsWith("."))
                    out.push(n);
            }
            if (JSON.stringify(out) !== JSON.stringify(root.folderNames))
                root.folderNames = out;
        }

        folder: "file://" + root.dir
        showFiles: false
        showDotAndDotDot: false
        showHidden: false
        onCountChanged: rescan()
        onStatusChanged: if (status === FolderListModel.Ready) rescan()
    }

    Variants {
        id: hostVariants

        model: root.folderNames

        PluginHost {}
    }
}
