//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import Quickshell
import "modules/lock/edit"
import qs
import qs.modules.lock

// Anordnungs-Editor des Sperrbildschirms offscreen: die ganze Buehne
// (EditStage: Vorschau, Griffe, Optionsfeld, Leiste). Anordnung stammt aus
// der echten shell.json (nur gelesen, $HOME ist Overlay).
// SELECT waehlt ein Element (clock, media, widget = erstes Widget, leer = nichts),
// CONFIRM=1 zeigt die Rueckfrage der Leiste.
ShellRoot {
    Window {
        id: win

        visible: true
        width: Number(Quickshell.env("W") || 1500)
        height: Number(Quickshell.env("H") || 900)
        color: "#101418"

        Component.onCompleted: LockLayout.edit("DP-1")

        EditStage {
            id: stage

            anchors.fill: parent
        }
    }

    // Erst waehlen, wenn die Vorschau steht
    Timer {
        interval: 2500
        running: true
        onTriggered: {
            const sel = Quickshell.env("SELECT") ?? "clock";
            LockLayout.selected = sel === "widget" ? (LockLayout.widgets[0]?.id ?? "") : sel;
            if (Quickshell.env("CONFIRM") === "1")
                stage.confirmReset = true;
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
