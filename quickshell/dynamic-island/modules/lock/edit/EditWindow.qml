pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.modules.lock

// Das Fenster des Anordnungs-Editors: eine Ebene ueber allem auf dem
// Monitor, auf dem LockLayout.edit() gestartet wurde, mit Maus und Tastatur.
// Alles Sichtbare steht in EditStage.qml, damit es sich auch ohne
// Layer-Shell rendern laesst (Tests).
PanelWindow {
    id: win

    readonly property ShellScreen target: Quickshell.screens.find(s => s.name === LockLayout.editScreen)
                                          ?? Quickshell.screens[0] ?? null

    screen: win.target
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dynamic-island-lockedit"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"

    EditStage {
        anchors.fill: parent
    }
}
