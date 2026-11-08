pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Block in der Gruppe des Plugins `desktop` (Einstellung `scenes`, editor "desktop"): welche
// Szene gerade gilt und der Knopf zum Bearbeiten. Das eigentliche Anordnen
// passiert direkt auf dem Desktop (EditBar.qml).
Column {
    id: root

    spacing: 8
    bottomPadding: 8

    readonly property string sceneLabel: {
        const key = Scenes.currentKey;
        if (key === "")
            return I18n.tr("Keine Szene – der Desktop ist leer");
        if (key === "*")
            return I18n.tr("Standard-Szene (gilt überall)");
        return key.endsWith("/") ? I18n.tr("Ordner %1").arg(key.slice(0, -1)) : I18n.tr("Bild %1").arg(key.split("/").pop());
    }

    Text {
        width: parent.width
        text: root.sceneLabel
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }

    Rectangle {
        width: editLabel.implicitWidth + 40
        height: 30
        radius: 15
        color: editHover.hovered ? Qt.lighter(Colors.primary, 1.1) : Colors.primary

        Row {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "edit"
                color: Colors.fgPrimary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15
            }

            Text {
                id: editLabel

                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Auf dem Desktop anordnen")
                color: Colors.fgPrimary
                font.family: Config.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
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
