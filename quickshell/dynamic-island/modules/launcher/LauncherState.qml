pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

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
    property string mode: "apps"

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
    readonly property var views: ["overview", "media", "control", "notifications", "system"]
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
            if (root.open && (root.mode === "power" || root.mode === "keys" || root.mode === "clipboard") && name && name !== root.screen?.name)
                root.close();
        }
    }

    // ---- Fullscreen-Sperre ----------------------------------------------
    // simple.lua bindet SUPER allein (beim Loslassen) auf
    // `ipc call launcher toggle`. Ein Fullscreen-Fenster – typisch ein Spiel –
    // greift sich die Tastatur; die SUPER-Freigabe erreicht Hyprland dann
    // erst, wenn das Fenster schon steht, und der Bind feuert, ohne dass in
    // dem Moment jemand etwas gedrückt hat. Der Launcher ging so über dem
    // Spiel von selbst auf.
    //
    // Deshalb fragt jede Anfrage von außen erst nach, ob gerade ein Fenster
    // im Vollbild den Fokus hat, und wird dann fallen gelassen. Betroffen
    // sind nur IPC und Tastenkürzel für das App-Menü; der Zug an der Notch
    // und die gezielten Wege (Wallpaper, Theme, Power) laufen direkt durch –
    // die löst niemand versehentlich aus.
    property bool blockOnFullscreen: true

    // Modus, der auf die Antwort von hyprctl wartet ("" = keine Anfrage offen)
    property string pendingMode: ""

    function request(mode: string, asToggle: bool): void {
        // Zumachen darf immer, das kostet keine Prüfung
        if (asToggle && root.open) {
            root.close();
            return;
        }

        if (!root.blockOnFullscreen) {
            root.showMode(root.focusedScreen(), mode);
            return;
        }

        root.pendingMode = mode;
        if (!fullscreenProbe.running)
            fullscreenProbe.running = true;
    }

    Process {
        id: fullscreenProbe

        command: ["hyprctl", "activewindow", "-j"]

        stdout: StdioCollector {
            id: probeCollector

            onStreamFinished: {
                const mode = root.pendingMode;
                root.pendingMode = "";
                if (!mode)
                    return;

                let win = null;
                try {
                    win = JSON.parse(probeCollector.text);
                } catch (e) {
                    // Ohne fokussiertes Fenster liefert hyprctl nichts
                    // Brauchbares – im Zweifel aufmachen.
                }

                // Hyprlands Modus: 0 = normal, 1 = maximiert, 2 = Vollbild.
                // Maximierte Fenster sind Alltag und sollen nicht sperren.
                const fs = Math.max(win?.fullscreen ?? 0, win?.fullscreenClient ?? 0);
                if (fs >= 2) {
                    console.log("Launcher: Anfrage verworfen –",
                                win?.title ?? "ein Fenster", "läuft im Vollbild");
                    return;
                }

                root.showMode(root.focusedScreen(), mode);
            }
        }
    }

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

        function wallpaper(): void {
            root.showWallpapers(root.focusedScreen());
        }

        function theme(): void {
            root.showThemes(root.focusedScreen());
        }

        function power(): void {
            root.toggleMode(root.focusedScreen(), "power");
        }

        // Tastenkuerzel-Uebersicht (SUPER+K)
        function keys(): void {
            root.toggleMode(root.focusedScreen(), "keys");
        }

        // Zwischenablage-Verlauf (SUPER+V)
        function clipboard(): void {
            root.toggleMode(root.focusedScreen(), "clipboard");
        }

        // Untermenues der Notch (Tastenkuerzel in hypr/profiles/simple.lua)
        function media(): void {
            root.toggleMode(root.focusedScreen(), "media");
        }

        function control(): void {
            root.toggleMode(root.focusedScreen(), "control");
        }

        function notifications(): void {
            root.toggleMode(root.focusedScreen(), "notifications");
        }

        function system(): void {
            root.toggleMode(root.focusedScreen(), "system");
        }
    }
}
