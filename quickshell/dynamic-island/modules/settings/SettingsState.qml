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
    property string requestedSection: ""
    property ShellScreen screen: null

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

        // Fuer SUPER + C (profiles/simple.lua): war das Fenster offen, wird es
        // geschlossen und "true" gemeldet – sonst "false", und die Taste
        // schliesst wie gewohnt das aktive Fenster.
        function dismiss(): bool {
            if (!root.open)
                return false;
            root.close();
            return true;
        }
    }
}
