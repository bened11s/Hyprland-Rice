pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.modules.services.idle

// Abdunkeln vor dem automatischen Sperren (Idle.warning). Dunkelt ueber die
// ganze Warnzeit langsam ab; jede Bewegung bricht ab und hellt schnell auf.
// Nimmt keine Eingaben an, Maus und Tastatur gehen durch.
Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "dynamic-island-idle"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}
            visible: shade.opacity > 0

            // Erst die Dauer, dann das Ziel umstellen – haengen beide direkt
            // an Idle.warning, startet die Animation evtl. mit der alten Dauer
            property bool fadingIn: false
            property bool dimmed: false

            Connections {
                target: Idle
                function onWarningChanged(): void {
                    win.fadingIn = Idle.warning;
                    win.dimmed = Idle.warning;
                }
            }

            Rectangle {
                id: shade

                anchors.fill: parent
                color: "black"
                opacity: win.dimmed ? 0.6 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: win.fadingIn ? Idle.warnSeconds * 1000 : 250
                        easing.type: win.fadingIn ? Easing.InQuad : Easing.OutCubic
                    }
                }
            }
        }
    }
}
