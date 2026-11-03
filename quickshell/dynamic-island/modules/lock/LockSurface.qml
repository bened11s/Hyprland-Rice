pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Wayland

// Eine Sperr-Flaeche je Monitor. Alles Sichtbare steht in LockScreen.qml,
// damit es sich auch ohne echte Sperre (Vorschau, Tests) rendern laesst.
WlSessionLockSurface {
    id: surface

    required property LockContext context
    required property var lock

    color: "black"

    LockScreen {
        anchors.fill: parent
        context: surface.context
        leaving: surface.lock.leaving
        primary: surface.lock.primaryName === "" || surface.screen?.name === surface.lock.primaryName
        snapshot: surface.lock.snapshotFor(surface.screen?.name ?? "")
        exitDuration: surface.lock.exitDuration
        active: surface.lock.activeName === "" || surface.screen?.name === surface.lock.activeName
        onActivated: surface.lock.activeName = surface.screen?.name ?? ""
        focus: true
    }
}
