pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Zeile in der Gruppe des Plugins `desktop` (Einstellung `scenes`, editor "desktop"): welche
// Szene gerade gilt und der Knopf zum Bearbeiten. Das eigentliche Anordnen
// passiert direkt auf dem Desktop (EditBar.qml).
Item {
    id: root

    implicitHeight: 30 + 8

    readonly property string sceneLabel: {
        const key = Scenes.currentKey;
        if (key === "")
            return I18n.tr("Keine Szene – der Desktop ist leer");
        if (key === "*")
            return I18n.tr("Standard-Szene (gilt überall)");
        return key.endsWith("/") ? I18n.tr("Ordner %1").arg(key.slice(0, -1)) : I18n.tr("Bild %1").arg(key.split("/").pop());
    }

    Text {
        anchors {
            left: parent.left
            right: editButton.left
            rightMargin: 12
        }
        height: 30
        verticalAlignment: Text.AlignVCenter
        text: root.sceneLabel
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 11
        elide: Text.ElideMiddle
    }

    // Aktion in Zeilen (docs/settings-style.md): Textknopf ohne Symbol
    Rectangle {
        id: editButton

        anchors.right: parent.right
        width: editLabel.implicitWidth + 24
        height: 30
        radius: 8
        color: editHover.hovered ? Qt.lighter(Colors.primary, 1.1) : Colors.primary

        Text {
            id: editLabel

            anchors.centerIn: parent
            text: I18n.tr("Auf dem Desktop anordnen")
            color: Colors.fgPrimary
            font.family: Config.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        HoverHandler {
            id: editHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: Scenes.edit(Hyprland.focusedMonitor?.name ?? "")
        }
    }
}
