pragma ComponentBehavior: Bound
import QtQuick

import qs.modules.services.bluetooth

import qs
import qs.modules.services.config

// Audioprofil-Zeile im Bluetooth-Geraetemenue (siehe BluetoothPanel):
// modelData = { name, description, available } aus BluetoothService.audioInfo.
// Kurzname gross, PipeWires Text (mit Codec) klein darunter. Nicht
// verfuegbare Profile sind nur gedimmt. Eigene Datei, weil eine
// Inline-Component hier an "is not a type" scheitert.
Rectangle {
    id: profileRow

    required property var modelData
    property bool current: false
    readonly property bool usable: profileRow.modelData.available !== false && !profileRow.current
    readonly property string label: BluetoothService.profileLabel(profileRow.modelData.name ?? "")

    signal triggered()

    implicitHeight: 38
    radius: 12
    color: profileRow.current ? Colors.alpha(Colors.primary, 0.14)
         : profileArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.16) : "transparent"
    opacity: profileRow.modelData.available === false ? 0.45 : 1

    Text {
        id: profileMark

        anchors {
            left: parent.left
            leftMargin: 10
            verticalCenter: parent.verticalCenter
        }
        text: profileRow.current ? "radio_button_checked" : "radio_button_unchecked"
        font.family: "Material Symbols Outlined"
        font.pixelSize: 15
        color: profileRow.current ? Colors.primary : Colors.fgSurfaceVariant
    }

    Column {
        anchors {
            left: profileMark.right
            leftMargin: 8
            right: parent.right
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        spacing: 0

        Text {
            font.family: Config.font
            width: parent.width
            text: profileRow.label
            font.pixelSize: 12
            font.weight: profileRow.current ? Font.DemiBold : Font.Normal
            color: profileRow.current ? Colors.primary : Colors.fgBackground
            elide: Text.ElideRight
        }

        Text {
            font.family: Config.font
            width: parent.width
            visible: text !== "" && text !== profileRow.label
            text: profileRow.modelData.description ?? ""
            font.pixelSize: 10
            color: Colors.fgSurfaceVariant
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: profileArea

        anchors.fill: parent
        enabled: profileRow.usable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: profileRow.triggered()
    }
}
