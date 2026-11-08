pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Popover ueber einer Taste der Vorschau: "Gruppe › Titel" und die
// Kombination als Kappen, optional ein Zustand ("aus").
Rectangle {
    id: tip

    property string title: ""
    property var keys: []
    property string hint: ""

    width: col.implicitWidth + 20
    height: col.implicitHeight + 14
    radius: 8
    color: Colors.background
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.5)

    Column {
        id: col

        anchors.centerIn: parent
        spacing: 5

        Row {
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tip.title
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: tip.hint !== ""
                text: "· " + tip.hint
                color: Colors.error
                font.family: Config.font
                font.pixelSize: 11
            }
        }

        Row {
            visible: tip.keys.length > 0
            spacing: 3

            Repeater {
                model: tip.keys

                Keycap {
                    required property string modelData

                    anchors.verticalCenter: parent?.verticalCenter
                    text: modelData
                    size: 18
                }
            }
        }
    }
}
