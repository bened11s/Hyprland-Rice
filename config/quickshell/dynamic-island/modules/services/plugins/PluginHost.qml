pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.config

// Ein gefundenes Plugin: liest plugin.json, prueft es, haelt die Werte der
// Einstellungen und – solange das Plugin an ist – das Objekt aus `main`.
// Entsteht je Ordner unter plugins/ (Variants in Plugins.qml).
Scope {
    id: root

    required property string modelData

    readonly property string pluginId: root.modelData
    readonly property string dir: Plugins.dir + "/" + root.pluginId

    // Geparstes Manifest oder null; `problem` sagt warum nicht
    property var manifest: null
    property string problem: ""
    readonly property bool valid: root.manifest !== null

    readonly property string name: root.manifest?.name ?? root.pluginId
    readonly property string icon: root.manifest?.icon ?? "extension"
    readonly property string version: root.manifest?.version ?? "?"
    // Komponente eines anderen Plugins (Manifest `parent`): laeuft nur, wenn
    // das Eltern-Plugin an ist, und erscheint in der Verwaltung in dessen
    // Untermenue. Nur eine Ebene – ein Eltern-Plugin mit eigenem `parent`
    // zaehlt nicht (sonst koennten sich zwei gegenseitig festhalten).
    readonly property string parentId: root.manifest?.parent ?? ""
    readonly property var parentHost: root.parentId !== "" ? Plugins.host(root.parentId) : null
    readonly property bool parentMissing: root.parentId !== "" && (!root.parentHost?.valid || root.parentHost.parentId !== "")
    // Eigener Schalter (plugins.json) – bei Komponenten zaehlt zusaetzlich
    // das Eltern-Plugin
    readonly property bool selfEnabled: root.valid && Plugins.stateLoaded && Plugins.isEnabled(root.pluginId)
    readonly property bool enabled: root.selfEnabled
                                    && (root.parentId === "" || (!root.parentMissing && root.parentHost.enabled))

    readonly property var settingKeys: Object.keys(root.manifest?.settings ?? {})

    // Werte = Vorgaben aus dem Manifest, ueberschrieben von plugins.json
    readonly property var settings: {
        const out = {};
        const spec = root.manifest?.settings ?? {};
        const stored = Plugins.state.settings?.[root.pluginId] ?? {};
        for (const key in spec)
            out[key] = stored[key] !== undefined ? stored[key] : spec[key].default;
        return out;
    }

    function settingMeta(key: string): var {
        const m = root.manifest.settings[key];
        const qualify = id => id.includes(".") ? id : `${Plugins.sectionPrefix}${root.pluginId}.${id}`;
        let requires = m.requires ?? null;
        if (typeof requires === "string")
            requires = qualify(requires);
        else if (requires) {
            const r = {};
            for (const id in requires)
                r[qualify(id)] = requires[id];
            requires = r;
        }
        return {
            title: m.title ?? key,
            desc: m.desc ?? "",
            options: m.options,
            min: m.min,
            max: m.max,
            step: m.step,
            unit: m.unit,
            editor: m.editor,
            hidden: m.hidden === true,
            requires
        };
    }

    // QML-Dateien bekommen den Ladezeitpunkt als Query: Qt haelt kompilierte
    // Komponenten pro URL im Cache, Qt.createComponent/Loader lieferten sonst
    // bis zum Shell-Neustart den alten Stand – auch nach Hot-Reload und
    // `plugins reload`. Zeitstempel statt Zaehler, weil ein Hot-Reload alle
    // Objekte neu baut (ein Zaehler finge wieder bei 0 an = alte URL).
    property string stamp: String(Date.now())

    function url(rel: string): string {
        const path = root.dir + "/" + rel;
        return rel.endsWith(".qml") ? `${path}?v=${root.stamp}` : path;
    }

    // ---- Main-Objekt --------------------------------------------------------

    property QtObject instance: null
    property string loadError: ""
    property bool loading: false
    property var component: null

    // "blocked": selbst an, aber das Eltern-Plugin ist aus
    readonly property string status: !root.valid ? "invalid"
                                     : !root.selfEnabled ? "off"
                                     : !root.enabled ? "blocked"
                                     : root.loadError !== "" ? "error"
                                     : root.loading ? "loading" : "ready"

    readonly property var info: ({
        id: root.pluginId,
        name: root.name,
        version: root.version,
        author: root.manifest?.author ?? "",
        description: root.manifest?.description ?? "",
        icon: root.icon,
        homepage: root.manifest?.homepage ?? "",
        enabled: root.enabled,
        selfEnabled: root.selfEnabled,
        status: root.status,
        parent: root.parentId,
        parentMissing: root.parentMissing,
        builtin: root.manifest?.builtin === true,
        // Untermenue fuer Komponenten (Manifest `components`): { title, icon, desc }
        components: root.manifest?.components ?? null,
        // Desktop-Widgets: [{ type, title, icon }]
        widgets: Object.keys(root.manifest?.widgets ?? {}).map(t => ({
            type: t,
            title: root.manifest.widgets[t].title ?? t,
            icon: root.manifest.widgets[t].icon ?? root.icon
        })),
        error: root.problem || root.loadError,
        hasSettings: root.settingKeys.length > 0,
        settingsCount: root.settingKeys.length,
        tiles: Object.keys(root.manifest?.tiles ?? {}),
        panels: Object.keys(root.manifest?.panels ?? {}),
        pages: Object.keys(root.manifest?.pages ?? {}),
        // Tastenkuerzel: [{ id, keys, title }]
        keybinds: Object.keys(root.manifest?.keybinds ?? {}).map(k => ({
            id: k,
            keys: root.manifest.keybinds[k].keys,
            title: root.manifest.keybinds[k].title
        })),
        actions: root.instance?.actions?.length ?? 0,
        files: (root.manifest?.files ?? []).length,
        main: root.manifest?.main ?? "",
        dir: root.dir
    })

    function unload(): void {
        if (root.instance)
            root.instance.destroy();
        root.instance = null;
        root.component = null;
        root.loading = false;
        root.loadError = "";
    }

    function load(): void {
        root.unload();
        root.stamp = String(Date.now());
        const main = root.manifest?.main;
        if (!root.enabled || !main)
            return;
        root.loading = true;
        const c = Qt.createComponent(root.url(main), Component.Asynchronous);
        root.component = c;
        if (c.status === Component.Loading)
            c.statusChanged.connect(() => root.finishLoad(c));
        else
            root.finishLoad(c);
    }

    function finishLoad(c: var): void {
        // Inzwischen neu geladen oder ausgeschaltet
        if (c !== root.component || c.status === Component.Loading)
            return;
        root.loading = false;
        if (c.status === Component.Error) {
            root.loadError = c.errorString().trim();
            console.warn(`plugin ${root.pluginId}: ${root.loadError}`);
            return;
        }
        const obj = c.createObject(root, { plugin: root.context });
        if (!obj) {
            root.loadError = "Main-Objekt liess sich nicht erzeugen (required property plugin?)";
            return;
        }
        root.instance = obj;
    }

    function reload(): void {
        manifestFile.reload();
        root.load();
    }

    // Echtes Ausschalten (nicht Shell-Ende/Reload): dem Plugin Bescheid geben,
    // damit es nach aussen sichtbare Spuren zuruecknehmen kann – sonst
    // wirkt z.B. eine geschriebene Modus-Datei einfach weiter
    onEnabledChanged: {
        if (!root.enabled && root.instance && typeof root.instance.onDisable === "function") {
            try {
                root.instance.onDisable();
            } catch (e) {
                console.warn(`plugin ${root.pluginId}: onDisable: ${e}`);
            }
        }
        Qt.callLater(root.load);
    }
    Component.onDestruction: root.unload()

    // ---- Manifest -----------------------------------------------------------

    function parseManifest(text: string): void {
        let m;
        try {
            m = JSON.parse(text);
        } catch (e) {
            root.fail(`plugin.json ist kein gueltiges JSON: ${e.message}`);
            return;
        }
        const problem = root.check(m);
        if (problem !== "") {
            root.fail(problem);
            return;
        }
        const before = JSON.stringify(root.manifest);
        root.problem = "";
        root.manifest = m;
        if (before !== JSON.stringify(m)) {
            root.migrate();
            Qt.callLater(root.load);
        }
    }

    function fail(problem: string): void {
        console.warn(`plugin ${root.pluginId}: ${problem}`);
        root.unload();
        root.problem = problem;
        root.manifest = null;
    }

    // Leerer String = alles gut
    function check(m: var): string {
        if (typeof m !== "object" || m === null)
            return "Manifest ist kein Objekt";
        if (m.id !== root.pluginId)
            return `id "${m.id}" passt nicht zum Ordnernamen "${root.pluginId}"`;
        if (!/^[a-z0-9][a-z0-9-]{0,47}$/.test(m.id))
            return "id: nur a-z, 0-9 und -";
        if (typeof m.name !== "string" || m.name === "")
            return "name fehlt";
        if (typeof m.api !== "number" || m.api > Plugins.apiVersion)
            return `braucht Plugin-API ${m.api}, die Shell kann ${Plugins.apiVersion}`;
        if (m.parent !== undefined && (typeof m.parent !== "string" || !/^[a-z0-9][a-z0-9-]{0,47}$/.test(m.parent) || m.parent === m.id))
            return "parent: id eines anderen Plugins erwartet";
        if (m.main !== undefined && (typeof m.main !== "string" || m.main.includes("..") || m.main.startsWith("/")))
            return "main: relativer Pfad im Plugin-Ordner erwartet";
        for (const key in m.settings ?? {}) {
            const s = m.settings[key];
            if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(key))
                return `settings.${key}: ungueltiger Schluessel`;
            if (typeof s !== "object" || s === null || s.default === undefined)
                return `settings.${key}: "default" fehlt`;
        }
        for (const tid in m.tiles ?? {}) {
            const t = m.tiles[tid];
            if (!/^[a-z0-9][a-z0-9-]*$/.test(tid) || typeof t?.component !== "string" || t.component.includes(".."))
                return `tiles.${tid}: id oder component ungueltig`;
        }
        for (const name in m.panels ?? {}) {
            const p = m.panels[name];
            if (!/^[a-z][a-z0-9-]*$/.test(name) || typeof p?.component !== "string" || p.component.includes(".."))
                return `panels.${name}: Ansicht oder component ungueltig`;
        }
        for (const type in m.widgets ?? {}) {
            const w = m.widgets[type];
            if (!/^[a-z][a-z0-9-]*$/.test(type) || typeof w?.component !== "string" || w.component.includes(".."))
                return `widgets.${type}: Typ oder component ungueltig`;
        }
        for (const name in m.pages ?? {}) {
            const p = m.pages[name];
            if (!/^[a-z][a-z0-9-]*$/.test(name) || typeof p?.component !== "string" || p.component.includes(".."))
                return `pages.${name}: Schluessel oder component ungueltig`;
        }
        for (const bid in m.keybinds ?? {}) {
            const b = m.keybinds[bid];
            if (!/^[a-z0-9][a-z0-9-]*$/.test(bid) || typeof b !== "object" || b === null)
                return `keybinds.${bid}: id ungueltig`;
            if (typeof b.keys !== "string" || b.keys.trim() === "")
                return `keybinds.${bid}: keys fehlt`;
            if (typeof b.title !== "string" || b.title === "" || b.title.includes("|"))
                return `keybinds.${bid}: title fehlt oder enthaelt |`;
            if (b.group !== undefined && (typeof b.group !== "string" || b.group === "" || b.group.includes("|")))
                return `keybinds.${bid}: group darf kein | enthalten`;
            if ((typeof b.ipc === "string") === (typeof b.exec === "string"))
                return `keybinds.${bid}: genau eins von ipc oder exec`;
        }
        return "";
    }

    // Einmalige Uebernahme alter Werte aus shell.json (`migrateFrom`: Gruppe),
    // solange plugins.json fuer dieses Plugin noch nichts hat
    function migrate(): void {
        const from = root.manifest?.migrateFrom;
        if (!from || !Plugins.stateLoaded || Plugins.state.settings?.[root.pluginId] !== undefined)
            return;
        const old = Config.raw[from];
        if (typeof old !== "object" || old === null)
            return;
        const values = {};
        for (const key of root.settingKeys)
            if (old[key] !== undefined)
                values[key] = old[key];
        const next = Plugins.copyState();
        next.settings[root.pluginId] = values;
        // War die alte Gruppe per `enabled: false` aus, bleibt das Plugin aus
        if (old.enabled === false && next.enabled[root.pluginId] === undefined)
            next.enabled[root.pluginId] = false;
        Plugins.commit(next);
        // Die alte Gruppe aus shell.json werfen: writeAdapter schreibt nur,
        // was Config noch kennt
        Config.save();
        console.info(`plugin ${root.pluginId}: Werte aus shell.json/${from} uebernommen`);
    }

    FileView {
        id: manifestFile

        path: root.dir + "/plugin.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.parseManifest(manifestFile.text())
        onLoadFailed: root.fail("plugin.json fehlt")
        onFileChanged: reload()
    }

    // ---- Was das Plugin zu sehen bekommt ------------------------------------

    // Als `plugin` an Main.qml und an Kachel-Komponenten uebergeben
    readonly property QtObject context: QtObject {
        readonly property string id: root.pluginId
        readonly property string name: root.name
        readonly property string version: root.version
        readonly property string dir: root.dir
        readonly property var manifest: root.manifest
        // Aktuelle Werte, bei jeder Aenderung ein neues Objekt (bindbar)
        readonly property var settings: root.settings
        readonly property bool enabled: root.enabled
        // Das Objekt aus `main`, solange es laeuft (sonst null) – fuer
        // Kacheln und Sektionen, die seinen Zustand brauchen
        readonly property QtObject main: root.instance

        function setting(key: string): var {
            return root.settings[key];
        }
        function set(key: string, value: var): void {
            Plugins.set(Plugins.sectionPrefix + root.pluginId, key, value);
        }
        function url(rel: string): string {
            return root.url(rel);
        }
        // Eigene Ordner fuer Zustand und Cache (werden nicht angelegt)
        function statePath(rel: string): string {
            return `${Plugins.stateDir}/${root.pluginId}/${rel}`;
        }
        function cachePath(rel: string): string {
            return `${Plugins.cacheDir}/${root.pluginId}/${rel}`;
        }
        function log(msg: string): void {
            console.info(`[${root.pluginId}] ${msg}`);
        }
    }
}
