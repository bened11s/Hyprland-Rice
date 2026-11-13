//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import Quickshell
import qs
import qs.modules.launcher
import qs.modules.bar.components.notch

// Notch offscreen: STATE = collapsed | overview | <LauncherState-Modus>
// | plugin:<id> (Notch-Ansicht eines Plugins) | wallpaper:<id> (Sektion der Wallpaper-Auswahl)
ShellRoot {
    Window {
        id: win
        visible: true
        width: Number(Quickshell.env("W") || 900)
        height: Number(Quickshell.env("H") || 520)
        color: "#3a4250"

        Item {
            id: row
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 40

            Notch {
                id: notch
                verticalMargin: 10
                borderWidth: Appearance.borderWidth
                borderColor: Appearance.borderColor
                cardRadius: Appearance.radius
            }
        }
    }
    Timer {
        interval: 1500; running: true
        onTriggered: {
            const s = Quickshell.env("STATE") || "collapsed";
            if (s === "overview") notch.expanded = true;
            else if (s.startsWith("plugin:")) LauncherState.showPluginView(null, s.slice(7));
            else if (s.startsWith("wallpaper:")) LauncherState.showWallpaperSection(null, s.slice(10));
            else if (s !== "collapsed") LauncherState.showMode(null, s);
        }
    }
    Timer {
        interval: Number(Quickshell.env("DELAY") || 5000); running: true
        onTriggered: win.contentItem.grabToImage(r => { r.saveToFile(Quickshell.env("OUT")); Quickshell.execDetached(["pkill","-x","qs"]); })
    }
}
