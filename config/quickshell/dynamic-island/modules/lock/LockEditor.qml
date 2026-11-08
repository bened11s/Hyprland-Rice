pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.modules.lock.edit

// Anordnen von Uhr und Medien-Karte des Sperrbildschirms, direkt auf einer
// Vorschau in voller Groesse (edit/EditStage.qml) – auf dem Monitor, der
// beim Start den Fokus hatte. Gespeichert wird in Config.lock.layout
// (LockLayout.qml), Esc/Abbrechen stellt den Stand vom Anfang wieder her.
//
// Start: LockLayout.edit(), Einstellungen > Sperrbildschirm > Anordnung
//        oder  qs -c dynamic-island ipc call lockedit edit|done|cancel|toggle|add <typ>
Scope {
    LazyLoader {
        active: LockLayout.editing

        EditWindow {}
    }

    IpcHandler {
        target: "lockedit"

        function edit(): void {
            LockLayout.edit(Hyprland.focusedMonitor?.name ?? "");
        }
        function done(): void {
            LockLayout.done();
        }
        function cancel(): void {
            LockLayout.cancel();
        }
        function toggle(): void {
            LockLayout.toggleEdit(Hyprland.focusedMonitor?.name ?? "");
        }
        // Widget hinzufuegen (nur waehrend des Bearbeitens), z.B. "weather"
        function add(type: string): void {
            LockLayout.add(type);
        }
    }
}
