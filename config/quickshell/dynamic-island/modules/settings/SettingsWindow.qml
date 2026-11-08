pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Einstellungs-Fenster. Der Inhalt – Gruppenleiste, Zeilen, Plugin-
// Verwaltung – ist SettingsCard.qml; hier steht nur das Fenster, das sie
// traegt.
//
// Ein normales schwebendes Fenster (xdg-toplevel), keine Layer-Oberflaeche:
// es bekommt Fokus wie jede App, laesst sich mit SUPER + Ziehen verschieben,
// und SUPER + C schliesst es nur, wenn es selbst das aktive Fenster ist.
// Hyprland setzt es schwebend und mittig und laesst Rand, Schatten und
// Transparenz weg (Fenster-Regel "dynamic-island-settings" in
// profiles/simple.lua). Das Fenster ist etwas groesser als die Karte, damit
// deren Schatten Platz hat; Klicks nimmt nur die Karte an (mask).
//
// Groesse: an den Kanten und Ecken der Karte ziehen (oder SUPER + rechte
// Maustaste), verschieben auch am Kopf der Gruppenleiste. Ohne Hyprland-Rand
// gibt es keine Greifkante des Compositors – die Griffe unten bitten ihn
// per xdg-toplevel um das Ziehen (startSystemResize/-Move). Die letzte
// Groesse merkt sich SettingsState.
//
// Gebaut wird es erst beim Oeffnen (LazyLoader) und beim Schliessen wieder
// verworfen.
LazyLoader {
    active: SettingsState.open

    FloatingWindow {
        id: win

        readonly property real inset: 28
        readonly property real grip: 6
        readonly property real corner: 18

        title: "dynamic-island-settings"
        color: "transparent"

        // Anfangsgroesse = zuletzt gewaehlte, hoechstens so gross wie der Monitor
        implicitWidth: Math.min(SettingsState.cardSize.width + win.inset * 2,
                                SettingsState.screen?.width ?? Infinity)
        implicitHeight: Math.min(SettingsState.cardSize.height + win.inset * 2,
                                 SettingsState.screen?.height ?? Infinity)
        minimumSize: Qt.size(SettingsState.minimumSize.width + win.inset * 2,
                             SettingsState.minimumSize.height + win.inset * 2)

        mask: Region {
            item: card
        }

        // Vom Compositor geschlossen (SUPER + C, Fenster-Menue …)
        onClosed: SettingsState.close()
        onVisibleChanged: {
            if (visible)
                card.reset();
        }
        // Entsteht bereits sichtbar – dann kommt kein Wechsel-Signal
        Component.onCompleted: if (visible) Qt.callLater(win.visibleChanged)

        // Neue Groesse merken, sobald das Ziehen vorbei ist
        onWidthChanged: saveSize.restart()
        onHeightChanged: saveSize.restart()

        Timer {
            id: saveSize

            interval: 600
            onTriggered: {
                if (win.visible && win.width > 0 && win.height > 0)
                    SettingsState.rememberSize(Qt.size(win.width - win.inset * 2, win.height - win.inset * 2));
            }
        }

        SettingsCard {
            id: card

            anchors {
                fill: parent
                margins: win.inset
            }
            shown: win.visible
        }

        // ---- Griffe ----
        // Liegen innerhalb der Karte (nur dort nimmt das Fenster Klicks an),
        // als schmaler Streifen ueber deren Rand
        component Grip: MouseArea {
            required property int edges

            cursorShape: {
                const h = edges & (Qt.LeftEdge | Qt.RightEdge);
                const v = edges & (Qt.TopEdge | Qt.BottomEdge);
                if (h && v)
                    return (edges === (Qt.LeftEdge | Qt.TopEdge) || edges === (Qt.RightEdge | Qt.BottomEdge))
                        ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor;
                return h ? Qt.SizeHorCursor : Qt.SizeVerCursor;
            }
            onPressed: win.startSystemResize(edges)
        }

        Item {
            anchors.fill: card

            Grip {
                edges: Qt.TopEdge
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: win.corner; rightMargin: win.corner }
                height: win.grip
            }
            Grip {
                edges: Qt.BottomEdge
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: win.corner; rightMargin: win.corner }
                height: win.grip
            }
            Grip {
                edges: Qt.LeftEdge
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left; topMargin: win.corner; bottomMargin: win.corner }
                width: win.grip
            }
            Grip {
                edges: Qt.RightEdge
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: win.corner; bottomMargin: win.corner }
                width: win.grip
            }
            Grip {
                edges: Qt.LeftEdge | Qt.TopEdge
                anchors { left: parent.left; top: parent.top }
                width: win.corner
                height: win.corner
            }
            Grip {
                edges: Qt.RightEdge | Qt.TopEdge
                anchors { right: parent.right; top: parent.top }
                width: win.corner
                height: win.corner
            }
            Grip {
                edges: Qt.LeftEdge | Qt.BottomEdge
                anchors { left: parent.left; bottom: parent.bottom }
                width: win.corner
                height: win.corner
            }
            Grip {
                edges: Qt.RightEdge | Qt.BottomEdge
                anchors { right: parent.right; bottom: parent.bottom }
                width: win.corner
                height: win.corner
            }

            // Verschieben am Kopf der Gruppenleiste ("Einstellungen")
            MouseArea {
                anchors { left: parent.left; top: parent.top; topMargin: win.grip; leftMargin: win.corner }
                width: card.sidebarWidth - win.corner
                height: 64
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
                onPressed: win.startSystemMove()
            }
        }
    }
}
