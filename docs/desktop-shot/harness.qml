//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import Quickshell
import "modules/desktop"
import qs
import qs.modules.services.desktop

// Bearbeitungs-Oberflaeche der Desktop-Widgets offscreen: Optionsfelder
// (Uhr, Visualiser, Sperrbildschirm-Variante), Widget-Auswahl und Leiste.
// Widgets stammen aus der echten scenes.json (nur gelesen, $HOME ist Overlay).
ShellRoot {
    Window {
        id: win

        // Erstes Widget eines Typs aus irgendeiner Szene
        function sample(type: string): var {
            for (const key in Scenes.scenes) {
                const w = Scenes.scenes[key].find(w => w.type === type);
                if (w)
                    return w;
            }
            return { id: "x" + type, type: type, x: 0.5, y: 0.5, size: 1, monitor: "*", opts: {} };
        }

        visible: true
        width: Number(Quickshell.env("W") || 1500)
        height: Number(Quickshell.env("H") || 900)
        color: "#101418"

        // CONFIRM=1: die Rueckfragen (Widget loeschen, Szene loeschen)
        readonly property bool confirm: Quickshell.env("CONFIRM") === "1"

        Component.onCompleted: Scenes.edit("DP-1")

        Rectangle {
            anchors.fill: parent
            color: "#2a3340"
        }

        WidgetOptions {
            x: 30
            y: 30
            radius: 14
            width: implicitWidth
            height: implicitHeight
            screenName: "DP-1"
            widget: win.sample("clock")
            confirmDelete: win.confirm
        }

        WidgetOptions {
            x: 30
            y: 470
            radius: 14
            width: implicitWidth
            height: implicitHeight
            screenName: "DP-1"
            widget: Object.assign({}, win.sample("visualizer"), { monitor: "DP-2", hidden: true })
        }

        // wie im Sperrbildschirm-Editor
        WidgetOptions {
            x: 380
            y: 30
            radius: 14
            width: implicitWidth
            height: implicitHeight
            monitors: false
            widget: win.sample("lyrics")
        }

        WidgetPicker {
            x: parent.width - width - 36
            y: 30
        }

        EditBar {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 36
            screenName: "DP-1"
            Component.onCompleted: confirmDrop = win.confirm
        }
    }

    Timer {
        interval: Number(Quickshell.env("DELAY") || 6000)
        running: true
        onTriggered: win.contentItem.grabToImage(r => {
            r.saveToFile(Quickshell.env("OUT"));
            Quickshell.execDetached(["pkill", "-x", "qs"]);
        })
    }
}
