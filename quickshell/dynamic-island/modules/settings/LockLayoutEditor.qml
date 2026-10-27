pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.services.config
import qs.modules.lock

// Block unter "Sperrbildschirm > Anordnung" (Config.meta editor "lock"): ob
// die Vorgabe gilt oder eine eigene Anordnung, und der Knopf zum
// Bearbeiten. Das eigentliche Anordnen passiert auf dem Sperrbildschirm
// selbst (modules/lock/LockEditor.qml).
Column {
    id: root

    spacing: 8
    bottomPadding: 8

    Text {
        width: parent.width
        text: LockLayout.custom ? I18n.tr("Eigene Anordnung") : I18n.tr("Standard-Anordnung")
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
                text: I18n.tr("Auf dem Sperrbildschirm anordnen")
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
            onTapped: LockLayout.edit(Hyprland.focusedMonitor?.name ?? "")
        }
    }
}
