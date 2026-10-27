pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Haelt die IPC-Objekte von Quickshells Hyprland-Modul frisch.
//
// Quickshell zieht `lastIpcObject` nicht bei jedem Event nach –
// specialWorkspace an den Monitoren und die Fensterzahlen der Workspaces
// bleiben sonst ewig stehen. Darum: bei den relevanten Events die Listen
// neu ziehen.
//
// Singleton, weil das frueher in WorkspaceSelector.qml hing: der wird im
// Notch-Layout nicht gebaut (Loader in Bar.qml), und die Specials in der
// Notch blieben unsichtbar. Ausserdem lief es so einmal pro Monitor.
// Wer die Werte liest, geht ueber die Funktionen hier – das zieht den
// Singleton hoch, und die Bindings haengen trotzdem an lastIpcObject.
Singleton {
    id: root

    // Offener Special-Workspace auf `monitor` ("" = keiner)
    function specialOn(monitor: HyprlandMonitor): string {
        return monitor?.lastIpcObject.specialWorkspace?.name ?? "";
    }

    function windowsOn(workspace: HyprlandWorkspace): int {
        return workspace?.lastIpcObject.windows ?? 0;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;

            // Special rein/raus -> Monitor-JSON (specialWorkspace) neu laden.
            // activespecialv2 kommt jedes Mal gleich hinterher, einmal reicht.
            if (n === "activespecial") {
                Hyprland.refreshMonitors();
                Hyprland.refreshWorkspaces();
            // Fenster oeffnen/schliessen/umziehen -> Belegung frisch halten
            } else if (n === "openwindow" || n === "closewindow" || n === "movewindow") {
                Hyprland.refreshWorkspaces();
            // Vollbild an/aus -> hasfullscreen (Desktop-Widgets pausieren)
            } else if (n === "fullscreen") {
                Hyprland.refreshWorkspaces();
            }
        }
    }
}
