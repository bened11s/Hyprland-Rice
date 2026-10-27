pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Zeile ueber dem Raster im Bearbeitungsmodus: links "Zuruecksetzen" (nur,
// wenn der Aufbau vom Standard abweicht), rechts "Entfernen" fuer die
// gewaehlte Kachel – wie "Remove" oben rechts im Android-Editor.
Item {
    id: header

    required property QuickEdit edit

    implicitHeight: 30

    EditButton {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        icon: "restart_alt"
        text: I18n.tr("Zurücksetzen")
        opacity: !Config.isDefault("quick", "rows") ? 1 : 0
        visible: opacity > 0
        onClicked: {
            header.edit.selectedId = "";
            QuickLayout.reset();
        }

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }

    EditButton {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        icon: "remove_circle"
        text: I18n.tr("Entfernen")
        danger: true
        opacity: header.edit.tilesMode && header.edit.selectedId !== "" ? 1 : 0
        visible: opacity > 0
        onClicked: header.edit.removeSelected()

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }
}
