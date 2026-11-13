import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.launcher
import qs.modules.services.wallpaper

import qs

// Dienst der Workspace-Uebersicht (SUPER+Tab). Zwei Ansichten, umschaltbar
// in den Einstellungen (`style`):
//   "vollbild"  Overview.qml – eigenes Overlay je Bildschirm, Tabs oben,
//               grosse Kacheln
//   "notch"     NotchView.qml – als Ansicht in der Notch (panels.notch),
//               eine Reihe kleiner Kacheln
// Beide lesen Daten und Aktionen von hier (plugin.main), damit es sie nur
// einmal gibt.
//
// Das Vollbild gibt es nur, solange es offen ist: geschlossen kostet das
// Plugin nichts – keine Fenster, keine Screencopys, und die Listen unten
// rechnen nur, solange eine Ansicht offen ist (`active`).
//
// Overview.qml wird per URL geladen (plugin.url), nicht als Typ: Dateien im
// Plugin-Ordner sehen sich nicht gegenseitig (README, "Imports").
//
// Taste: SUPER+Tab loest den Hyprland-Global-Shortcut dynamic-island:overview
// aus (plugin.json, `hyprctl dispatch hl.dsp.global(...)`) statt `qs ipc call`
// – hyprctl startet in ~6 ms, qs ipc in ~25 ms. IPC geht trotzdem:
//   qs -c dynamic-island ipc call plugins call overview toggle _
//
// Gemessen (2560x1440, 6 Fenster): Aufbauen 18 ms (erstes Mal ~100 ms, darum
// wird die Komponente kurz nach dem Start schon kompiliert), offen mit
// Live-Vorschau 4–8 % CPU, geschlossen 0.
Scope {
    id: root

    required property var plugin

    readonly property var settings: root.plugin.settings ?? ({})
    readonly property string style: root.settings.style === "notch" ? "notch" : "vollbild"
    // Vorschau der Fenster:
    //   "auswahl"  die Kachel unter Auswahl/Maus mit 30 fps, der Rest 1x/s –
    //              selbst getaktet per captureFrame()
    //   "alle"     alle per ScreencopyView.live
    //   "aus"      ein Standbild beim Oeffnen
    // Gemessen (2x 2560x1440, 180 Hz, 6 Fenster; Leerlauf qs 2 %, Hyprland
    // 3 %, GPU 6 %):
    //   alle live      qs +10–14 %  Hyprland +7 %  GPU +10–15 %
    //   auswahl        qs  +0–2 %   Hyprland +0–1 % GPU  +0–3 %
    //   aus            nichts messbar
    // `live` kopiert schon ein einziges, ruhiges Fenster je Monitor-Frame
    // (~8 % CPU fuer EIN Fenster); alle Fenster selbst mit 30 fps zu takten
    // war aber noch teurer (+17 %) – darum live nur fuer "alle".
    // (Alte Einstellung `live: false` gilt weiter als "aus".)
    readonly property string preview: ["auswahl", "alle", "aus"].includes(root.settings.preview)
        ? root.settings.preview : root.settings.live === false ? "aus" : "auswahl"

    // Takt fuer "auswahl": je Tick ein neues Bild – `fastTick` fuer die
    // Kachel unter Auswahl/Maus, `tick` fuer den Rest
    property int focusFps: 30
    signal tick
    signal fastTick

    Timer {
        running: root.active && root.preview === "auswahl"
        repeat: true
        interval: 1000
        onTriggered: root.tick()
    }

    Timer {
        running: root.active && root.preview === "auswahl" && root.focusFps > 0
        repeat: true
        interval: Math.round(1000 / Math.max(1, root.focusFps))
        onTriggered: root.fastTick()
    }
    readonly property bool allScreens: root.settings.allScreens !== false
    readonly property bool showEmpty: root.settings.empty === true

    // ---- Zustand ----
    property var view: null
    readonly property bool fullOpen: root.view !== null && !root.view.closing
    readonly property bool notchOpen: LauncherState.open && LauncherState.mode === "plugin"
        && LauncherState.pluginView === root.plugin.id
    readonly property bool open: root.fullOpen || root.notchOpen
    // Listen rechnen nur, solange eine Ansicht da ist (auch beim Ausblenden)
    readonly property bool active: root.view !== null || root.notchOpen

    property Component comp: null

    readonly property var actions: [
        {
            name: I18n.tr("Workspace-Übersicht"),
            desc: I18n.tr("Alle Workspaces gekachelt, je Bildschirm ein Tab"),
            icon: "grid_view",
            run: () => Qt.callLater(root.show)
        }
    ]

    function compile(): bool {
        if (root.comp === null)
            root.comp = Qt.createComponent(root.plugin.url("Overview.qml"));
        if (root.comp.status !== Component.Ready) {
            root.plugin.log(`Overview.qml laedt nicht: ${root.comp.errorString()}`);
            root.comp = null;
            return false;
        }
        return true;
    }

    // Vorkompilieren, sobald die Shell steht – nur das Parsen, noch keine
    // Fenster
    Timer {
        running: true
        interval: 3000
        onTriggered: root.compile()
    }

    GlobalShortcut {
        appid: "dynamic-island"
        name: "overview"
        description: "Workspace-Übersicht an/aus"
        onPressed: root.toggle()
    }

    function refreshAll(): void {
        // Fenster-Geometrien (lastIpcObject) sind sonst womoeglich alt
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
        root.rev++;
    }

    // Vollbild-Ansicht
    function showFull(): void {
        if (root.notchOpen)
            LauncherState.close();
        if (root.view !== null) {
            // Mitten im Ausblenden wieder auf: einfach zurueckholen
            root.view.reopen();
            return;
        }
        // Vor dem Refresh lesen: direkt danach ist focusedMonitor kurz leer –
        // dann galt kein Bildschirm als der fokussierte (keine Tastatur,
        // keine Auswahl)
        const start = Hyprland.focusedMonitor?.name ?? LauncherState.focusedScreen()?.name ?? "";
        root.refreshAll();
        if (!root.compile())
            return;
        const v = root.comp.createObject(root, { plugin: root.plugin, main: root, startMonitor: start });
        if (v === null) {
            root.plugin.log("Overview.qml: createObject fehlgeschlagen");
            return;
        }
        v.finished.connect(() => {
            if (root.view === v)
                root.view = null;
            v.destroy();
        });
        root.view = v;
    }

    // Notch-Ansicht
    function showNotch(): void {
        root.view?.close();
        root.refreshAll();
        LauncherState.showPluginView(LauncherState.focusedScreen(), root.plugin.id);
    }

    function show(): void {
        if (root.style === "notch")
            root.showNotch();
        else
            root.showFull();
    }

    // Von aussen (SUPER+Tab, IPC): erst die Vollbild-Sperre fragen – liegt
    // auf dem fokussierten Monitor ein Vollbild-Fenster vorne, bleibt zu
    function request(open: var): void {
        LauncherState.whenAllowed(open, null);
    }

    function hide(): void {
        root.view?.close();
        if (root.notchOpen)
            LauncherState.close();
    }

    function toggle(): void {
        if (root.open)
            root.hide();
        else
            root.request(root.show);
    }

    // qs -c dynamic-island ipc call plugins call overview toggle _
    // arg (optional): "vollbild" | "notch" erzwingt die Ansicht
    function ipc(cmd: string, arg: string): string {
        const want = arg === "notch" ? root.showNotch : arg === "vollbild" ? root.showFull : root.show;
        if (cmd === "toggle") {
            if (root.open)
                root.hide();
            else
                root.request(want);
            return root.open ? "open" : "closed";
        }
        if (cmd === "open") {
            root.request(want);
            return "open";
        }
        if (cmd === "close") {
            root.hide();
            return "closed";
        }
        if (cmd === "state")
            return root.fullOpen ? "vollbild" : root.notchOpen ? "notch" : "closed";
        return "unbekannt: toggle | open | close | state  [vollbild|notch]";
    }

    function onDisable(): void {
        root.view?.destroy();
        root.view = null;
        if (root.notchOpen)
            LauncherState.close();
    }

    // ================= Daten =================
    // Workspaces je Bildschirm am Stueck (hypr: wsMonitorOffset, 10er-Gruppen)
    readonly property int groupSize: 10

    // Hochzaehlen = Listen neu auswerten (lastIpcObject meldet nicht jede
    // Aenderung einzeln)
    property int rev: 0

    Connections {
        target: root.active ? Hyprland : null

        function onRawEvent(event: HyprlandEvent): void {
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "changefloatingmode":
            case "windowtitlev2":
            case "workspacev2":
            case "createworkspacev2":
            case "destroyworkspacev2":
            case "focusedmonv2":
            case "activespecialv2":
            case "fullscreen":
                refresh.restart();
                break;
            }
        }
    }

    Timer {
        id: refresh

        interval: 40
        onTriggered: root.refreshAll()
    }

    readonly property var monitors: root.active
        ? Hyprland.monitors.values.slice().sort((a, b) => a.x - b.x || a.y - b.y) : []

    // { wsId: [HyprlandToplevel] } – von hinten nach vorn: gekachelte vor
    // schwebenden, innerhalb davon der zuletzt benutzte oben
    readonly property var byWs: {
        root.rev;
        const map = {};
        if (!root.active)
            return map;
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject ?? {};
            if (!o.at || !o.size || o.hidden === true || o.mapped === false)
                continue;
            // Special-WS haben seit Hyprland 0.57 keine id mehr -> über den Namen
            const name = t.workspace?.name ?? o.workspace?.name ?? "";
            const id = name.startsWith("special:") ? name : (t.workspace?.id ?? o.workspace?.id);
            if (id === undefined)
                continue;
            if (!map[id])
                map[id] = [];
            map[id].push(t);
        }
        for (const id in map) {
            map[id].sort((a, b) => {
                const fa = a.lastIpcObject.floating ? 1 : 0, fb = b.lastIpcObject.floating ? 1 : 0;
                if (fa !== fb)
                    return fa - fb;
                return (b.lastIpcObject.focusHistoryID ?? 0) - (a.lastIpcObject.focusHistoryID ?? 0);
            });
        }
        return map;
    }

    function windowsOn(id: var): var {
        return root.byWs[id] ?? [];
    }

    function groupOffset(m: HyprlandMonitor): int {
        const active = m?.activeWorkspace?.id ?? 1;
        return Math.floor((Math.max(1, active) - 1) / root.groupSize) * root.groupSize;
    }

    // Kacheln eines Bildschirms: belegte Workspaces + der aktive, danach "+"
    function entriesFor(m: HyprlandMonitor): var {
        root.rev;
        if (!m || !root.active)
            return [];
        const active = m.activeWorkspace?.id ?? -1;
        const offset = root.groupOffset(m);
        const ids = new Set();
        for (const ws of Hyprland.workspaces.values) {
            if (ws.id <= 0 || ws.monitor?.name !== m.name)
                continue;
            if (root.windowsOn(ws.id).length > 0 || ws.id === active)
                ids.add(ws.id);
        }
        if (root.showEmpty)
            for (let i = 1; i <= root.groupSize; i++)
                ids.add(offset + i);

        const out = [...ids].sort((a, b) => a - b).map(id => ({
            kind: "ws",
            id,
            name: `${id}`,
            label: id > offset && id <= offset + root.groupSize ? `${id - offset}` : `${id}`,
            special: false,
            active: id === active,
            monitor: m
        }));

        if (!root.showEmpty) {
            // Frei = gibt es nirgends (auch nicht leer auf einem anderen
            // Bildschirm – sonst sprang "+" dorthin)
            const taken = new Set(Hyprland.workspaces.values.map(ws => ws.id));
            for (let i = 1; i <= root.groupSize; i++) {
                const id = offset + i;
                if (!ids.has(id) && !taken.has(id)) {
                    out.push({ kind: "new", id, name: `${id}`, label: `${i}`, special: false, active: false, monitor: m });
                    break;
                }
            }
        }
        return out;
    }

    // Scratchpads mit Fenstern
    readonly property var specialEntries: {
        root.rev;
        if (!root.active)
            return [];
        const opened = new Set(Hyprland.monitors.values.map(m => m.lastIpcObject?.specialWorkspace?.name ?? ""));
        return Hyprland.workspaces.values
            .filter(ws => ws.name.startsWith("special:") && root.windowsOn(ws.name).length > 0)
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(ws => ({
                kind: "ws",
                id: ws.name,
                name: ws.name,
                label: ws.name.slice(8),
                special: true,
                active: opened.has(ws.name),
                open: opened.has(ws.name),
                monitor: ws.monitor ?? Hyprland.focusedMonitor
            }));
    }

    // Tabs: je Bildschirm einer, dazu die Scratchpads (wenn es welche gibt)
    readonly property var tabs: {
        const t = root.monitors.map(m => ({ kind: "monitor", key: m.name, monitor: m }));
        if (root.specialEntries.length > 0)
            t.push({ kind: "special", key: "special:", monitor: null });
        return t;
    }

    function entriesForTab(tab: var): var {
        if (!tab)
            return [];
        return tab.kind === "special" ? root.specialEntries : root.entriesFor(tab.monitor);
    }

    // App-Symbol je Fensterklasse (gemerkt, die Suche ist nicht ganz billig)
    property var iconCache: ({})

    function iconFor(cls: string): string {
        if (cls === "")
            return Quickshell.iconPath("application-x-executable", true);
        const hit = root.iconCache[cls];
        if (hit !== undefined)
            return hit;
        const entry = DesktopEntries.heuristicLookup(cls);
        const path = Quickshell.iconPath(entry?.icon ?? cls.toLowerCase(), "application-x-executable");
        root.iconCache[cls] = path;
        return path;
    }

    // Wallpaper als kleines Bild (Vorschau-Thumb, 480x270): reicht fuer die
    // Kacheln und den weichgezeichneten Hintergrund, dekodiert sofort
    readonly property string wallThumb: {
        const t = Wallpapers.thumbPathFor(Wallpapers.actualCurrent);
        return t !== "" ? `file://${t}` : Wallpapers.actualCurrent !== "" ? `file://${Wallpapers.actualCurrent}` : "";
    }

    // ================= Aktionen =================
    function dispatch(lua: string, legacy: string): void {
        Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
    }

    function addressOf(t: var): string {
        const a = t?.lastIpcObject?.address ?? "";
        if (a !== "")
            return a;
        const raw = t?.address ?? "";
        return raw.startsWith("0x") ? raw : `0x${raw}`;
    }

    // Fokus/Workspace-Wechsel erst, wenn die Ansicht die Tastatur abgegeben
    // hat: solange eine Layer-Surface sie exklusiv haelt (Vollbild-Overlay
    // wie Notch), ignoriert Hyprland jeden Fokuswechsel (getestet – das
    // Fenster blieb einfach das alte). Schliessen nimmt die Tastatur sofort
    // zurueck, der Compositor braucht einen Frame.
    property var pending: null

    function closeThen(action: var): void {
        root.pending = action;
        root.hide();
        actionTimer.restart();
    }

    Timer {
        id: actionTimer

        interval: 60
        onTriggered: {
            const action = root.pending;
            root.pending = null;
            if (action)
                action();
        }
    }

    function goTo(entry: var): void {
        root.closeThen(() => root.goNow(entry));
    }

    function goNow(entry: var): void {
        if (entry.special) {
            const short = entry.name.replace(/^special:/, "");
            // Schon offen? Dann nur zu (die Ansicht ist ja schon weg)
            if (entry.open)
                return;
            root.dispatch(`hl.dsp.workspace.toggle_special("${short}")`, `togglespecialworkspace ${short}`);
            return;
        }
        root.dispatch(`hl.dsp.focus({ workspace = ${entry.id} })`, `workspace ${entry.id}`);
    }

    function focusWindow(t: var): void {
        const addr = root.addressOf(t);
        root.closeThen(() => root.dispatch(`hl.dsp.focus({ window = "address:${addr}" })`, `focuswindow address:${addr}`));
    }

    // Schliessen und Verschieben gehen bei offener Ansicht (getestet)
    function closeWindow(t: var): void {
        const addr = root.addressOf(t);
        root.dispatch(`hl.dsp.window.close({ window = "address:${addr}" })`, `closewindow address:${addr}`);
        refresh.restart();
    }

    function moveWindow(t: var, entry: var): void {
        const addr = root.addressOf(t);
        const lua = entry.special ? `"${entry.name}"` : `${entry.id}`;
        const legacy = entry.special ? entry.name : `${entry.id}`;
        root.dispatch(`hl.dsp.window.move({ workspace = ${lua}, window = "address:${addr}", follow = false })`,
            `movetoworkspacesilent ${legacy},address:${addr}`);
        refresh.restart();
    }
}
