pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.modules.services.screenshot

// Screenshot-Overlay: ein Vollbildfenster je Monitor, solange
// Screenshot.active ist (davor und danach existiert nichts). Jedes Fenster
// zeigt das Standbild seines Monitors, der Ausschnitt lebt in der
// gemeinsamen Session und gehoert immer genau einem Monitor.
//
// Tastatur: jedes Fenster nimmt den Fokus exklusiv; Hyprland gibt ihn dem
// Fenster unter dem Zeiger. Die Tasten wirken ohnehin auf die gemeinsame
// Session, es ist also egal, welches Fenster sie bekommt.
//
// Oeffnen:  Screenshot.open("copy")  bzw.  IPC `screenshot region|…`
Scope {
    id: root

    ScreenshotSession {
        id: shared
    }

    // Jeder Start beginnt ohne Ausschnitt
    Connections {
        target: Screenshot

        function onActiveChanged(): void {
            shared.clear();
        }
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: loader

            required property ShellScreen modelData

            active: Screenshot.active

            PanelWindow {
                id: win

                readonly property string monitorName: loader.modelData.name

                screen: loader.modelData

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                exclusiveZone: -1
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "dynamic-island-screenshot"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                color: "black"

                ScreenshotView {
                    anchors.fill: parent
                    screenName: win.monitorName
                    session: shared
                    shot: Screenshot.shotFor(win.monitorName)
                    dpr: loader.modelData.devicePixelRatio
                    windows: Screenshot.windowsOn(win.monitorName)
                    preset: Screenshot.preset
                }
            }
        }
    }
}
