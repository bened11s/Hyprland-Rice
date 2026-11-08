pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

import qs
import qs.modules.services.hypr

// Special-Overlay im Selektor – horizontal und ohne Fenster-Icons:
//   - ein Icon pro EXISTIERENDEM Special-WS (special:<name>)
//   - feste Icons je Special-Name (siehe iconName, Fallback: Anfangsbuchstabe)
//   - der aktive bekommt eine tertiäre Pille hinter dem Icon – das Gegenstück
//     zur aktiven Punktpille der Normalansicht
//   - Klick toggelt das jeweilige Special
//
// WorkspaceSelector legt das Overlay zentriert über die verwischten Punkte;
// solange es sichtbar ist, fängt es deren Klicks ab.
RowLayout {
    id: root

    // Welcher Special ist auf DIESEM Monitor offen – bestimmt die Pille. Nur
    // wenn hier einer steht, zeigt die Leiste das Overlay ueberhaupt an.
    required property string activeSpecial

    // Alle existierenden Specials ueber alle Monitore – das Overlay eines
    // Bildschirms listet also auch die Scratchpads, die gerade auf dem
    // anderen liegen (Klick togglpt auf dem fokussierten Monitor und holt
    // sie damit notfalls rueber).
    readonly property var specials: Hyprland.workspaces.values.filter(
        w => w.name.startsWith("special:"))

    // 0, weil der Abstand wie bei den Punkten aus dem hitPadding kommt –
    // so bleiben die Klickzonen auch hier lückenlos aneinander.
    spacing: 0

    Repeater {
        model: root.specials

        Item {
            id: ws

            required property var modelData   // HyprlandWorkspace

            // "special:music" -> "music". Der generische Special heisst intern
            // "special:special" (Hyprland haengt IMMER das Prefix an), also
            // bleibt der Key nie leer und bekommt den Star.
            readonly property string key: ws.modelData.name.slice("special:".length)
            readonly property bool isActive: root.activeSpecial === ws.modelData.name
            readonly property bool hasWindows: HyprIpc.windowsOn(ws.modelData) > 0

            // Gleiche Größenphilosophie wie die Punktreihe: deutliche
            // Trefferfläche (hitPadding), das Sichtbare sitzt zentriert.
            readonly property real iconSize: 18
            readonly property real pillWidth: ws.iconSize + 16
            readonly property real pillHeight: 24
            readonly property real hitPadding: 6

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: ws.pillWidth + ws.hitPadding * 2
            implicitHeight: ws.pillHeight + ws.hitPadding * 2

            // Die tertiäre Pille hinter dem aktiven Icon. Sie zieht sich
            // inaktiv auf Breite 0 zusammen – derselbe Zug wie der aktive
            // Punkt, der sich zur Pille dehnt bzw. schrumpft.
            Rectangle {
                anchors.centerIn: parent

                width: ws.isActive ? ws.pillWidth : 0
                height: ws.pillHeight
                radius: height / 2
                color: Colors.tertiary

                Behavior on width {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }

            Text {
                anchors.centerIn: parent

                text: ws.iconName(ws.key)
                font.family: "Material Symbols Outlined"
                font.pixelSize: ws.iconSize

                // Aktiv = onTertiary (lesbar auf der Pille). Belegte Specials
                // heben sich vom leeren Rahmen ab – dieselbe Stufung wie bei
                // den Punkten, nur ohne Groessenunterschied.
                color: ws.isActive ? Colors.fgTertiary
                     : ws.hasWindows ? Colors.fgSurface
                     : Colors.fgSurfaceVariant

                Behavior on color {
                    ColorAnimation { duration: 140 }
                }
            }

            function iconName(key: string): string {
                // Material-Symbole fuer die ueblichen Special-Namen
                const map = {
                    "special": "star",
                    "communication": "forum",
                    "music": "music_cast",
                    "todo": "checklist",
                    "sysmon": "monitor_heart"
                };
                return map[key] ?? key.charAt(0).toUpperCase();
            }

            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: Hyprland.dispatch(Hyprland.usingLua
                    ? `hl.dsp.workspace.toggle_special("${ws.key}")`
                    : `togglespecialworkspace ${ws.key}`);
            }
        }
    }
}
