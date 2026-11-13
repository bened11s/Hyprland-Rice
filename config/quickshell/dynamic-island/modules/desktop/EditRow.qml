import QtQuick

import qs
import qs.modules.services.config

// Zeile im Optionsfeld eines Widgets (WidgetOptions), wie SettingsRow im
// Einstellungsfenster: Beschriftung links, das Bedienelement rechts (Kinder
// der Zeile), darueber eine duenne Linie.
Item {
    id: row

    property string label: ""
    default property alias content: slot.data

    width: parent?.width ?? 0
    height: 40

    Rectangle {
        width: parent.width
        height: 1
        color: Colors.alpha(Colors.outline, 0.15)
    }

    Text {
        anchors {
            left: parent.left
            right: slot.left
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        text: row.label
        color: Colors.fgSurface
        font.family: Config.font
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    Row {
        id: slot

        anchors.right: parent.right
        height: parent.height
        spacing: 4
    }
}
