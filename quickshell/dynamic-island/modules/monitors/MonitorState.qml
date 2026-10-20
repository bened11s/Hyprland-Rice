pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.modules.services.monitors

// Zustand des Bildschirm-Fensters – derselbe Grund wie SettingsState:
// der Knopf sitzt in der Settings-Karte, das Fenster ist etwas anderes.
//
// Beim Oeffnen werden die Monitore neu gelesen, damit die Karte den
// aktuellen Stand zeigt (auch nach Ausstecken eines Geraetes).
Singleton {
    id: root

    property bool open: false
    property ShellScreen screen: null

    function show(target: ShellScreen): void {
        root.screen = target;
        root.open = true;
        Monitors.refresh();
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

    // Erreichbar ueber:  qs -c dynamic-island ipc call monitors toggle
    IpcHandler {
        target: "monitors"

        function toggle(): void {
            root.toggleOnFocused();
        }

        function open(): void {
            root.show(root.focusedScreen());
        }

        function close(): void {
            root.close();
        }

        // Fuer Tastenkuerzel im Stil von SettingsState.dismiss()
        function dismiss(): bool {
            if (!root.open)
                return false;
            root.close();
            return true;
        }
    }
}
