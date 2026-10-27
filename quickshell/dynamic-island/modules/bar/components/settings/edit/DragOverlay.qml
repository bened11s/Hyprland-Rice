pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Geist und Ziel-Markierung beim Ziehen einer Kachel – liegt im Rahmen um
// das Raster (QuickEdit.frame), alle Positionen kommen von dort.
Item {
    id: overlay

    required property QuickEdit edit

    anchors.fill: parent
    z: 50

    // Einfuege-Markierung: senkrecht zwischen Kacheln, waagerecht fuer eine
    // neue Reihe (QuickEdit.markerFor)
    Rectangle {
        x: overlay.edit.marker.x
        y: overlay.edit.marker.y
        width: overlay.edit.marker.width
        height: overlay.edit.marker.height
        radius: 1
        color: Colors.primary
        visible: overlay.edit.dragging && width > 0
    }

    // Der Geist folgt dem Zeiger: Symbol und Name der Kachel
    Rectangle {
        id: ghost

        readonly property var info: QuickLayout.tiles[overlay.edit.dragId] ?? ({})

        visible: overlay.edit.dragging
        x: overlay.edit.dragPos.x - width / 2
        y: overlay.edit.dragPos.y - height / 2
        width: ghostLabel.implicitWidth + 54
        height: 40
        radius: 20
        color: overlay.edit.hideTarget ? Colors.alpha(Colors.error, 0.92) : Colors.alpha(Colors.primary, 0.92)
        scale: 1.05

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            id: ghostIcon

            anchors {
                left: parent.left
                leftMargin: 14
                verticalCenter: parent.verticalCenter
            }
            text: overlay.edit.hideTarget ? "visibility_off" : (ghost.info.icon ?? "")
            color: overlay.edit.hideTarget ? Colors.fgError : Colors.fgPrimary
            font.family: "Material Symbols Outlined"
            font.pixelSize: 18
        }

        Text {
            id: ghostLabel

            font.family: Config.font
            anchors {
                left: ghostIcon.right
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: I18n.tr(ghost.info.label ?? "")
            color: overlay.edit.hideTarget ? Colors.fgError : Colors.fgPrimary
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
}
