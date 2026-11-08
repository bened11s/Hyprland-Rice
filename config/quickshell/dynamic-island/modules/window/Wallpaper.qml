pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs

// Hintergrund-Layer (Wallpaper) – enthält selbst die Pro-Monitor-Logik.
// Die `required property modelData` im Delegaten wird von `Variants`
// automatisch mit dem jeweiligen Screen befüllt.
// Bewusst nicht "Window.qml" genannt – der Name würde den QML-Typ `Window`
// aus QtQuick überdecken.
//
// Welches Bild gilt und wie es wechselt, steht in WallpaperStage.qml.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData

        screen: win.modelData
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "dynamic-island-background"
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: Colors.background

        // Bild samt Uebergangsanimation (WallpaperStage.qml)
        WallpaperStage {
            anchors.fill: parent
            decodeSize: Qt.size(win.modelData.width, win.modelData.height)
        }
    }
}
