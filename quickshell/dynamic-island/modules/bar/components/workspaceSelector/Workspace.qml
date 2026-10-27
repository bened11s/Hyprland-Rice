pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

import qs
import qs.modules.widgets

// Ein Punkt im Workspace-Selektor.
//
// Den Zustand bekommt die Komponente komplett durchgereicht (activeWsId,
// occupied, groupOffset) statt Hyprland selbst zu fragen – sonst würde jeder
// der zehn Punkte dieselbe Abfrage nochmal machen.
//
// Bewusst OHNE Fenster-Icons darunter: ein Punkt
// pro Workspace, mehr nicht.
Item {
    id: root

    required property int index          // liefert der Repeater
    required property int activeWsId
    required property var occupied
    required property int groupOffset

    readonly property int ws: root.groupOffset + root.index + 1
    readonly property bool isActive: root.activeWsId === root.ws
    readonly property bool isOccupied: root.occupied[root.ws] ?? false

    readonly property real dotSize: 5
    readonly property real activeWidth: 18

    // Die drei Zustaende eines Punktes. Belegt = derselbe Primaerton wie aktiv,
    // nur abgeschwaecht: so sieht man auf einen Blick, wo Fenster liegen, ohne
    // dass es mit dem aktiven Punkt (der ausserdem zur Pille wird) konkurriert.
    // Leer bleibt neutral-grau. Hier sind die Stellschrauben fuer die Optik.
    readonly property color colourActive: Colors.primary
    readonly property color colourOccupied: Colors.alpha(Colors.secondary, 0.75)
    readonly property color colourEmpty: Colors.outlineVariant

    // Belegte Punkte duerfen minimal groesser sein - der Farbunterschied allein
    // geht bei 5px schnell unter.
    readonly property real occupiedSize: 6

    // Sichtbarer Punkt und Trefferfläche sind absichtlich entkoppelt: das Item
    // ist deutlich größer als der Punkt, damit man nicht zielen muss. Das
    // RowLayout hat dafür spacing 0 – der Abstand zwischen den Punkten kommt
    // komplett aus diesem Rand, sonst lägen tote Zonen dazwischen.
    readonly property real hitPadding: 6
    readonly property real hitHeight: 24

    // Ohne Alignment würde das RowLayout den Punkt auf volle Kartenhöhe ziehen
    Layout.alignment: Qt.AlignVCenter

    // Der aktive Punkt zieht sich zur Pille. Weil die Breite aus dem Zustand
    // kommt, wächst das Layout – und damit die Karte – automatisch mit.
    implicitWidth: (root.isActive ? root.activeWidth : root.dotSize) + root.hitPadding * 2
    implicitHeight: root.hitHeight + root.hitPadding * 2

    Morph on implicitWidth {}

    Rectangle {
        anchors.centerIn: parent

        width: root.isActive ? root.activeWidth
             : root.isOccupied ? root.occupiedSize
             : root.dotSize
        height: root.isActive || !root.isOccupied ? root.dotSize : root.occupiedSize
        radius: height / 2

        color: root.isActive ? root.colourActive
             : root.isOccupied ? root.colourOccupied
             : root.colourEmpty

        // Der aktive Punkt reagiert nicht auf Hover – er ist schon hervorgehoben
        scale: hover.hovered && !root.isActive ? 1.4 : 1

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
        // Damit der Punkt beim Belegen/Leeren nicht springt
        Behavior on width {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    // Handler statt MouseArea: die beiden verhandeln den Grab untereinander
    // und nehmen sich nichts weg (siehe Kommentar in Notch.qml).
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: {
            // Aktiver Punkt = Eintritt in den generischen Special (die Sterne-
            // Chips, siehe SpecialWorkspaces.qml). FRUEHER stand hier ein
            // "dynamic-island toggle specialws" CLI-Aufruf - den gibt es
            // nicht, der Klick tat deshalb sichtbar nichts.
            if (root.isActive) {
                Hyprland.dispatch(Hyprland.usingLua
                    ? 'hl.dsp.workspace.toggle_special("special")'
                    : "togglespecialworkspace special");
                return;
            }

            // Lua-Config versteht nur Lua – darum die Weiche
            Hyprland.dispatch(Hyprland.usingLua
                ? `hl.dsp.focus({ workspace = ${root.ws} })`
                : `workspace ${root.ws}`);
        }
    }
}