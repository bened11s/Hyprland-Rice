pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Zustand des Einstellungs-Fensters. Eigener Singleton aus demselben Grund
// wie bei LauncherState: der Knopf sitzt in der Leiste, das Fenster ist ein
// anderes – die beiden sehen sich sonst nicht.
Singleton {
    id: root

    property bool open: false
    property ShellScreen screen: null

    // Zuletzt gewaehlte Groesse der Karte (das Fenster laesst sich ziehen,
    // SettingsWindow.qml). Liegt hier statt im Fenster, weil das bei jedem
    // Schliessen verworfen wird – und muss schon gelesen sein, bevor es
    // beim Oeffnen seine Anfangsgroesse nimmt.
    readonly property size defaultSize: Qt.size(880, 640)
    // Schmal genug, dass die Leiste zur Symbolspalte wird (SettingsCard.compact)
    readonly property size minimumSize: Qt.size(520, 520)
    property size cardSize: root.defaultSize

    function rememberSize(size: size): void {
        const w = Math.round(Math.max(root.minimumSize.width, size.width));
        const h = Math.round(Math.max(root.minimumSize.height, size.height));
        if (w === root.cardSize.width && h === root.cardSize.height)
            return;
        root.cardSize = Qt.size(w, h);
        sizeFile.setText(JSON.stringify({ width: w, height: h }) + "\n");
    }

    FileView {
        id: sizeFile

        path: Quickshell.env("HOME") + "/.local/state/dynamic-island/settings-size.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (s.width > 0 && s.height > 0)
                    root.cardSize = Qt.size(Math.max(root.minimumSize.width, s.width),
                                            Math.max(root.minimumSize.height, s.height));
            } catch (e) {}
        }
    }

    function show(target: ShellScreen): void {
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

    function focusedScreen(): ShellScreen {
        const name = Hyprland.focusedMonitor?.name ?? "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }

    function toggleOnFocused(): void {
        root.toggle(root.focusedScreen());
    }

    // Sprung zu einer Gruppe oder Seite der Karte, mit Argumenten fuer die
    // Seite ("@page:terminal/looks" mit { look: "miku" }; auch "@wallpapers",
    // "@plugins" oder eine Gruppe wie "bar" gehen). Oeffnet das Fenster auf
    // dem fokussierten Bildschirm. Die Karte entsteht erst mit dem Fenster
    // und holt sich den Wunsch beim Entstehen (takeRequest) – ist sie schon
    // offen, reagiert sie auf die Aenderung von `request`.
    property var request: null

    function openPage(section: string, args: var): void {
        root.request = { section, args: args ?? {}, serial: (root.request?.serial ?? 0) + 1 };
        root.show(root.focusedScreen());
    }

    function takeRequest(): var {
        const r = root.request;
        root.request = null;
        return r;
    }

    // Erreichbar ueber:  qs -c dynamic-island ipc call settings toggle
    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.toggleOnFocused();
        }

        function open(): void {
            root.show(root.focusedScreen());
        }

        function close(): void {
            root.close();
        }

        // qs -c dynamic-island ipc call settings page "@page:terminal/looks"
        function page(section: string): void {
            root.openPage(section, {});
        }
    }
}
