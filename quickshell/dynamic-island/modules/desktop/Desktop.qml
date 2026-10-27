pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.modules.services.config
import qs.modules.services.desktop
// Widgets (auch aus Plugins) werden per Loader-URL geladen und duerfen nur
// qs-Module importieren, die die Shell schon statisch kennt – deshalb hier
// alles, was Widgets typischerweise brauchen, einmal importieren.
import qs
import qs.modules.services.audio
import qs.modules.services.core
import qs.modules.services.media
import qs.modules.services.plugins
import qs.modules.services.system
import qs.modules.widgets
import qs.modules.widgets.clock

// Desktop-Widgets: je Monitor eine durchsichtige Ebene zwischen Wallpaper und
// Fenstern (DesktopScreen.qml). Was dort steht, sagt die Szene des aktuellen
// Wallpapers (Scenes.qml, ~/.config/dynamic-island/scenes.json).
//
// Gestartet vom Plugin `desktop` (plugins/desktop/Main.qml): ist es aus,
// gibt es weder die Fenster noch das IPC-Ziel.
//
// IPC:  qs -c dynamic-island ipc call desktop edit|done|toggle
//       … desktop add <typ>        Widget ins Bearbeitungsziel legen
//       … desktop hide|show|visibility   "Nur im Editor" an/aus/umschalten
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        DesktopScreen {}
    }

    IpcHandler {
        target: "desktop"

        function edit(): void {
            Scenes.edit(Hyprland.focusedMonitor?.name ?? "");
        }
        function done(): void {
            Scenes.done();
        }
        function toggle(): void {
            if (Scenes.editing)
                Scenes.done();
            else
                edit();
        }
        function add(type: string): void {
            if (!Scenes.editing)
                edit();
            Scenes.add(type);
        }
        function hide(): void {
            DesktopWidgets.setHidden(true);
        }
        function show(): void {
            DesktopWidgets.setHidden(false);
        }
        function visibility(): string {
            const hidden = !DesktopWidgets.settings.hidden;
            DesktopWidgets.setHidden(hidden);
            return hidden ? "hidden" : "shown";
        }
        function scene(): string {
            return JSON.stringify({ key: Scenes.currentKey, widgets: Scenes.widgets });
        }
    }
}
