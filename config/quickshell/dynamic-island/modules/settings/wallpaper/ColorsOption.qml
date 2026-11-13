import QtQuick
import qs.modules.services.config
import qs.modules.settings

import qs

// Zeile "Name ...... Auswahlknopf" im Kasten des dynamischen Schemas
// (ColorsPage.qml). Eigene Datei statt `component` (Hot-Reload).
Item {
    id: option

    required property string label
    property alias options: drop.options
    property alias current: drop.current
    property alias labelOf: drop.labelOf
    signal picked(var value)

    width: parent?.width ?? 0
    height: 40

    Text {
        anchors {
            left: parent.left
            right: drop.left
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        text: option.label
        color: Colors.fgSurface
        opacity: option.enabled ? 1 : 0.4
        font.family: Config.font
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    SettingsDropdown {
        id: drop

        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        width: implicitWidth
        onPicked: v => option.picked(v)
    }
}
