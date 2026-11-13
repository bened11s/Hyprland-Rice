//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import Quickshell
import "modules/settings"
import qs

ShellRoot {
    Window {
        visible: true
        id: win
        width: Number(Quickshell.env("W") || 1400)
        height: Number(Quickshell.env("H") || 860)
        color: "#101418"
        SettingsCard {
            id: card
            anchors.fill: parent
            anchors.margins: 0
            Component.onCompleted: {
                const s = Quickshell.env("SECTION") ?? "";
                if (s !== "") card.section = s;
            }
        }
    }
    Timer {
        interval: Number(Quickshell.env("DELAY") || 3500); running: true
        onTriggered: card.grabToImage(r => { r.saveToFile(Quickshell.env("OUT")); Quickshell.execDetached(["pkill","-x","qs"]); })
    }
}
