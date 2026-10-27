pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Spiegelt general:gaps_out aus der laufenden Hyprland-Instanz, damit die
// Leiste mit den Fensterkanten fluchtet, statt dieselbe Zahl doppelt zu
// pflegen (hier und in ~/.config/hypr/variables.lua).
//
// Singleton, weil Bar.qml über `Variants` pro Monitor instanziiert wird –
// als Kind der Leiste liefe hyprctl sonst einmal pro Bildschirm.
//
// Achtung: `gaps_out` ist der globale Wert. Workspace-Rules überschreiben ihn
// (rules.lua setzt singleWindowGapsOut für Workspaces mit genau einem
// Fenster) – das sieht man hier nicht, dafür müsste man pro Workspace fragen.
Singleton {
    id: root

    // Fallback, bis die erste Antwort da ist. Entspricht dem Stand von
    // variables.lua, damit beim Start nichts sichtbar springt.
    property real top: 0
    property real right: 10
    property real bottom: 10
    property real left: 10

    // Für den häufigen Fall "überall gleich"
    readonly property bool uniform: top === right && right === bottom && bottom === left

    function reload(): void {
        probe.running = true;
    }

    Process {
        id: probe

        running: true
        command: ["hyprctl", "getoption", "general:gaps_out", "-j"]

        stdout: StdioCollector {
            id: collector

            onStreamFinished: {
                // hyprctl liefert die vier Werte als String im Feld `css`,
                // in CSS-Reihenfolge: oben rechts unten links.
                let v;
                try {
                    v = JSON.parse(collector.text).css.trim().split(/\s+/).map(Number);
                } catch (e) {
                    console.warn("HyprGaps: gaps_out nicht lesbar:", e);
                    return;
                }

                // Lieber beim alten Wert bleiben als das Layout mit NaN
                // zerlegen – anchors.leftMargin: NaN schiebt alles ins Nichts.
                if (v.length !== 4 || v.some(isNaN)) {
                    console.warn("HyprGaps: unerwartetes Format:", collector.text);
                    return;
                }

                root.top = v[0];
                root.right = v[1];
                root.bottom = v[2];
                root.left = v[3];
            }
        }
    }

    // Nach `hyprctl reload` neu einlesen. `configreloaded` kommt ohne Daten,
    // deshalb reicht der Name.
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded")
                root.reload();
        }
    }
}
