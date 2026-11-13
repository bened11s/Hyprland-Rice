pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.modules.services.config

// Gemeinsamer Zustand des Launchers. Die Notch (im Bar-Fenster) schaltet ihn
// an, das Launcher-Fenster hängt seine Sichtbarkeit daran – die beiden leben
// in verschiedenen Fenstern und können sich sonst nicht sehen.
Singleton {
    id: root

    property bool open: false
    property ShellScreen screen: null   // auf welchem Monitor er aufgeht
    // Welche Ansicht die Karte gerade zeigt. Beide teilen sich Fenster und
    // Fokus-Grab (siehe Bar.qml), deshalb ein gemeinsamer Zustand statt zweier
    // Singletons: offen ist immer genau eine davon.
    //   "apps"       Suchfeld + Trefferliste (LauncherPanel)
    //   "wallpaper"  eigenes Suchfeld + Bild-Karussell (WallpaperPanel)
    //   "theme"      eigenes Suchfeld + Farb-Karussell (ThemePanel)
    //   "power"      Sitzungs- und Energieaktionen (PowerPanel)
    //   "keys"       Tastenkuerzel-Uebersicht aus Hyprland (KeybindsPanel)
    //   "clipboard"  Zwischenablage-Verlauf (ClipboardPanel)
    //   "media"      Medien: Player-Auswahl, Cover mit Ring, Steuerung
    //   "control"    Steuerung: Kacheln, WLAN/BT/Audio, Tray
    //   "notifications"  Benachrichtigungsliste
    //   "system"     Auslastung und Temperaturen
    //   "plugin"     Notch-Ansicht eines Plugins (Manifest `panels.notch`),
    //                welches sagt `pluginView` (Plugin-id)
    property string mode: "apps"
    property string pluginView: ""

    // App-Liste fuer den Launcher als gesammelter Schnappschuss. DesktopEntries
    // scannt erst beim ersten Zugriff und meldet dann Eintrag fuer Eintrag;
    // direkt gebunden sortierte jeder davon die Treffer neu und setzte das
    // Modell zurueck (erstes Oeffnen nach dem Start: rund 130 Resets in
    // 330 ms, alle Zeilen flackerten mit ihrem Intro). Darum kurz nach dem
    // Start vorwaermen und Aenderungen 80 ms sammeln.
    property var apps: []
    property bool appsWarm: false

    function warmApps(): void {
        if (root.appsWarm)
            return;
        root.appsWarm = true;
        root.apps = DesktopEntries.applications.values.slice();
    }

    Timer {
        running: !root.appsWarm
        interval: 3000
        onTriggered: root.warmApps()
    }

    Timer {
        id: appsSettle

        interval: 80
        onTriggered: root.apps = DesktopEntries.applications.values.slice()
    }

    Connections {
        target: root.appsWarm ? DesktopEntries.applications : null

        function onValuesChanged(): void {
            appsSettle.restart();
        }
    }

    // Die Ansichten, durch die man in der Notch blaettert (Mausrad kippen,
    // Touchpad wischen). "overview" ist keine Launcher-Ansicht, sondern die
    // Hover-Karte der Notch selbst – Blaettern dorthin schliesst den Launcher.
    // Abgeschaltete Seiten (Config.notch.page*) fallen aus dem Blaettern,
    // ihre Kuerzel oeffnen sie weiter. Ebenso Seiten, deren Karten alle
    // aus sind (Steuerung behaelt immer die Kacheln, Benachrichtigungen die Liste).
    readonly property bool mediaHasCards: ["mediaSources", "mediaCover", "mediaTitle", "mediaProgress",
        "mediaControls", "mediaQueue"].some(k => Config.notch[k]) || Config.media.lyrics
    readonly property bool systemHasCards: ["sysCpu", "sysGpu", "sysVram", "sysRam", "sysDisk",
        "sysTemps", "sysThrottle"].some(k => Config.notch[k])
    readonly property var views: ["overview"].concat(
        [["media", Config.notch.pageMedia && root.mediaHasCards], ["control", Config.notch.pageControl],
         ["notifications", Config.notch.pageNotifications], ["system", Config.notch.pageSystem && root.systemHasCards]]
        .filter(v => v[1]).map(v => v[0]))
    readonly property int viewIndex: root.open ? root.views.indexOf(root.mode) : 0

    // Blaettern um `dir` (+1/-1). Liefert die neue Ansicht zurueck, damit die
    // Notch beim Ruecksprung auf die Uebersicht wieder aufklappen kann.
    function step(target: ShellScreen, dir: int): string {
        // Ueber den Rand hinaus: von der ersten auf die letzte und zurueck
        const n = root.views.length;
        const from = Math.max(0, root.viewIndex);
        const next = ((from + dir) % n + n) % n;
        const view = root.views[next];
        if (view === "overview")
            root.close();
        else
            root.showMode(target, view);
        return view;
    }

    // Fuer Tastenkuerzel: dieselbe Ansicht nochmal = zu
    function toggleMode(target: ShellScreen, mode: string): void {
        if (root.open && root.mode === mode)
            root.close();
        else
            root.showMode(target, mode);
    }

    function show(target: ShellScreen): void {
        root.showMode(target, "apps");
    }

    function showMode(target: ShellScreen, mode: string): void {
        // Vollbild-Sperre (siehe unten): auf einem Monitor mit Vollbild-
        // Fenster vorne geht nichts auf, egal woher der Wunsch kommt
        if (root.fullscreenOn(target)) {
            console.log("Launcher:", mode, "nicht geöffnet –", target?.name ?? "", "zeigt ein Vollbild-Fenster");
            return;
        }
        root.mode = mode;
        root.screen = target;
        root.open = true;
    }

    function close(): void {
        root.open = false;
    }

    function toggle(target: ShellScreen): void {
        if (root.open)
            root.close();
        else
            root.show(target);
    }

    // Direkt in die Wallpaper-Auswahl (Knopf in der Notch, IPC, Tastenkuerzel)
    function showWallpapers(target: ShellScreen): void {
        root.showMode(target, "wallpaper");
    }

    function toggleWallpapers(target: ShellScreen): void {
        if (root.open && root.mode === "wallpaper")
            root.close();
        else
            root.showWallpapers(target);
    }

    // ---- Plugin-Sektion der Wallpaper-Auswahl ----
    // Plugins koennen unter die lokale Reihe eine Sektion haengen (Manifest
    // `panels.wallpaper`, siehe WallpaperPanel). Welche aufgeklappt ist
    // (Plugin-id, "" = keine), lebt hier statt im Panel: das Panel entsteht
    // bei jedem Oeffnen neu, die Sektion soll aber offen bleiben, wie der
    // Suchtext darin. Die Tastatur faengt trotzdem in der lokalen Reihe an –
    // ausser `wallpaperSectionFocus` verlangt die Sektion (das Panel setzt
    // das Flag zurueck, sobald es die Tastatur dorthin gegeben hat).
    property string wallpaperSection: ""
    property bool wallpaperSectionFocus: false

    // Auswahl mit aufgeklappter Sektion und der Tastatur darin (IPC eines
    // Plugins, Tastenkuerzel)
    function showWallpaperSection(target: ShellScreen, section: string): void {
        root.wallpaperSection = section;
        root.wallpaperSectionFocus = true;
        root.showWallpapers(target);
    }

    // Genau so schon offen -> zu
    function toggleWallpaperSection(target: ShellScreen, section: string): void {
        if (root.open && root.mode === "wallpaper" && root.wallpaperSection === section)
            root.close();
        else
            root.showWallpaperSection(target, section);
    }

    // ---- Notch-Ansichten von Plugins ----
    // Ein Plugin kann eine eigene Ansicht in die Notch bringen (Manifest
    // `panels.notch`, Vertrag in plugins/README.md). Die Notch laedt sie wie
    // ihre eigenen Ansichten erst beim Oeffnen.
    function showPluginView(target: ShellScreen, id: string): void {
        root.pluginView = id;
        root.showMode(target, "plugin");
    }

    // Genau diese schon offen -> zu
    function togglePluginView(target: ShellScreen, id: string): void {
        if (root.open && root.mode === "plugin" && root.pluginView === id)
            root.close();
        else
            root.showPluginView(target, id);
    }

    // Farbschema-Auswahl. Anders als die Wallpaper hat sie keinen Knopf in der
    // Leiste – nur den Launcher-Befehl und diesen Weg hier.
    function showThemes(target: ShellScreen): void {
        root.showMode(target, "theme");
    }

    function showPower(target: ShellScreen): void {
        root.showMode(target, "power");
    }

    // Für Aufrufe von außen (Tastenkürzel): Monitor unter dem Fokus nehmen
    function focusedScreen(): ShellScreen {
        const name = Hyprland.focusedMonitor?.name ?? "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }

    function toggleOnFocused(): void {
        root.toggle(root.focusedScreen());
    }

    // Das Power-Menue und die Tastenkuerzel halten den Tastaturfokus
    // exklusiv, und der blockiert Klicks auf dem anderen Monitor. Wechselt
    // der Fokus dorthin, gehen sie deshalb zu.
    Connections {
        target: Hyprland

        function onFocusedMonitorChanged(): void {
            const name = Hyprland.focusedMonitor?.name ?? "";
            if (root.open && (root.mode === "power" || root.mode === "keys" || root.mode === "clipboard" || root.mode === "plugin") && name && name !== root.screen?.name)
                root.close();
        }
    }

    // ---- Vollbild-Sperre ------------------------------------------------
    // Liegt auf einem Monitor ein Fenster im Vollbild vorne (typisch ein
    // Spiel), geht dort kein Menü der Shell auf: weder Launcher noch
    // Untermenüs, Power, Tastenkürzel, Zwischenablage, Plugin-Ansichten oder
    // die Workspace-Übersicht. Scratchpads bleiben frei – sie laufen über
    // Hyprland (`dynamic-island toggle specialws`), nicht über die Shell. Ist
    // ein Scratchpad über dem Vollbild offen, zählt dessen Inhalt: dann
    // darf auf dem Monitor wieder etwas auf.
    //
    // Ursprung: simple.lua bindet SUPER allein (beim Loslassen) auf
    // `ipc call launcher toggle`. Ein Spiel greift sich die Tastatur; die
    // SUPER-Freigabe erreicht Hyprland erst, wenn das Fenster schon steht,
    // und der Bind feuert, ohne dass jemand etwas gedrückt hat.
    //
    // Zwei Wege:
    //  - `whenAllowed()` fragt hyprctl frisch (Tastenkürzel, IPC, Global
    //    Shortcuts von Plugins) – da zählt der Zustand genau jetzt.
    //  - `showMode()` prüft synchron gegen `fullscreenScreens`, den Stand der
    //    letzten Abfrage. Der wird bei Vollbild-Ereignissen erneuert und,
    //    solange irgendwo Vollbild läuft, auch bei Workspace-Wechseln.
    // Die Notch selbst liegt auf dem Top-Layer und damit unter einem
    // Vollbild-Fenster; per Maus kommt man dort ohnehin nicht hin.
    property bool blockOnFullscreen: true

    // Namen der Monitore, auf denen gerade ein Vollbild-Fenster vorne liegt
    property var fullscreenScreens: []

    function fullscreenOn(target: ShellScreen): bool {
        return root.blockOnFullscreen && !!target && root.fullscreenScreens.includes(target.name);
    }

    // Wartende Wünsche: { screen: Monitorname, run: Funktion }
    property var pendingRuns: []

    // `run` ausführen, sofern auf `target` (Vorgabe: fokussierter Monitor)
    // kein Vollbild-Fenster vorne liegt – nach frischer Abfrage
    function whenAllowed(run: var, target: ShellScreen): void {
        const screen = target ?? root.focusedScreen();
        if (!root.blockOnFullscreen) {
            run();
            return;
        }
        root.pendingRuns.push({ screen: screen?.name ?? "", run: run });
        root.probe();
    }

    function request(mode: string, asToggle: bool): void {
        // Zumachen darf immer, das kostet keine Prüfung
        if (asToggle && root.open && (mode === "apps" || root.mode === mode)) {
            root.close();
            return;
        }
        root.whenAllowed(() => root.showMode(root.focusedScreen(), mode), null);
    }

    function probe(): void {
        if (fullscreenProbe.running)
            fullscreenProbe.again = true;
        else
            fullscreenProbe.running = true;
    }

    // Aus `hyprctl -j monitors` und `-j clients`: welche Monitore zeigen vorne
    // ein Vollbild-Fenster? Vorne ist das offene Scratchpad, sonst der aktive
    // Workspace. Hyprlands Modus: 0 normal, 1 maximiert, 2 Vollbild (3 beides);
    // maximierte Fenster sind Alltag und sperren nicht. fullscreenClient
    // zählt mit (Fake-Fullscreen: das Spiel glaubt sich im Vollbild).
    function blockedFrom(monitors: var, clients: var): var {
        const out = [];
        for (const m of monitors) {
            // Über den Namen: seit Hyprland 0.57 fehlt "id" bei Spezial-Workspaces
            const special = m.specialWorkspace?.name ?? "";
            const ws = special !== "" ? special : (m.activeWorkspace?.name ?? "");
            const hit = clients.some(c => (c.workspace?.name ?? "") === ws && c.mapped !== false && !c.hidden
                && Math.max(c.fullscreen ?? 0, c.fullscreenClient ?? 0) >= 2);
            if (hit)
                out.push(m.name);
        }
        return out;
    }

    Process {
        id: fullscreenProbe

        // Noch eine Runde, weil während der laufenden etwas passiert ist
        property bool again: false

        command: ["sh", "-c", "hyprctl -j monitors; printf '\\036'; hyprctl -j clients"]

        stdout: StdioCollector {
            id: probeCollector

            onStreamFinished: {
                let blocked = [];
                try {
                    const parts = probeCollector.text.split("\u001e");
                    blocked = root.blockedFrom(JSON.parse(parts[0]), JSON.parse(parts[1]));
                } catch (e) {
                    // hyprctl nicht greifbar – im Zweifel nichts sperren
                    console.log("Launcher: Vollbild-Abfrage gescheitert:", e);
                }
                if (JSON.stringify(blocked) !== JSON.stringify(root.fullscreenScreens))
                    root.fullscreenScreens = blocked;

                const runs = root.pendingRuns;
                root.pendingRuns = [];
                for (const r of runs) {
                    if (root.blockOnFullscreen && blocked.includes(r.screen))
                        console.log("Launcher: Anfrage verworfen –", r.screen, "zeigt ein Vollbild-Fenster");
                    else
                        r.run();
                }

                // Der Prozess ist hier evtl. noch nicht beendet – die
                // Nachrunde deshalb ueber den Timer
                if (fullscreenProbe.again) {
                    fullscreenProbe.again = false;
                    refreshDelay.restart();
                }
            }
        }
    }

    // Geht ein Fenster unter einem offenen Menü ins Vollbild (Spiel startet
    // gerade), macht das Menü zu – es läge sonst unsichtbar unter dem Spiel
    // und hielte womöglich die Tastatur fest.
    onFullscreenScreensChanged: {
        if (root.open && root.fullscreenOn(root.screen))
            root.close();
    }

    // Stand nachziehen. Vollbild-Ereignisse immer; Workspace- und
    // Fenster-Ereignisse nur, solange irgendwo Vollbild läuft oder läufen
    // könnte – sonst kostet die Sperre im Alltag keinen einzigen Prozess.
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            switch (event.name) {
            case "fullscreen":
                refreshDelay.restart();
                break;
            case "workspacev2":
            case "activespecialv2":
            case "focusedmonv2":
            case "closewindow":
            case "movewindowv2":
                if (root.fullscreenScreens.length > 0
                        || Hyprland.monitors.values.some(m => m.activeWorkspace?.hasFullscreen))
                    refreshDelay.restart();
                break;
            }
        }
    }

    Timer {
        id: refreshDelay

        interval: 60
        onTriggered: root.probe()
    }

    // Einmal beim Start: läuft schon ein Spiel, wenn die Shell neu lädt
    Component.onCompleted: root.probe()

    // Erreichbar über:  qs -c dynamic-island ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.request("apps", true);
        }

        function open(): void {
            root.request("apps", false);
        }

        function close(): void {
            root.close();
        }

        // Alles Weitere laeuft durch die Vollbild-Sperre (request/whenAllowed)
        function wallpaper(): void {
            root.request("wallpaper", false);
        }

        function theme(): void {
            root.request("theme", false);
        }

        function power(): void {
            root.request("power", true);
        }

        // Tastenkuerzel-Uebersicht (SUPER+K)
        function keys(): void {
            root.request("keys", true);
        }

        // Zwischenablage-Verlauf (SUPER+V)
        function clipboard(): void {
            root.request("clipboard", true);
        }

        // Untermenues der Notch (Tastenkuerzel in hypr/profiles/simple.lua)
        function media(): void {
            root.request("media", true);
        }

        function control(): void {
            root.request("control", true);
        }

        function notifications(): void {
            root.request("notifications", true);
        }

        function system(): void {
            root.request("system", true);
        }

        // Fuer Skripte/Tests: welche Monitore gerade sperren
        function fullscreen(): string {
            return JSON.stringify(root.fullscreenScreens);
        }
    }
}
