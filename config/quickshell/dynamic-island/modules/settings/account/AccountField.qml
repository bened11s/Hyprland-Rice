pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Textfeld der Konto-Seite im Stil der VPN-Felder: `value` von aussen,
// `text` ist der getippte Stand, `password` versteckt die Eingabe.
Rectangle {
    id: field

    property string value: ""
    property string placeholder: ""
    property bool password: false
    readonly property alias text: input.text
    signal accepted()
    signal editingFinished()

    function clear(): void {
        input.text = "";
    }

    implicitWidth: 220
    implicitHeight: 30
    radius: 8
    color: Colors.alpha(Colors.fgSurface, 0.06)
    border.width: 1
    border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

    onValueChanged: if (!input.activeFocus) input.text = field.value

    Behavior on border.color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }

    TextInput {
        id: input

        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 10
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        font.family: Config.font
        font.pixelSize: 12
        color: Colors.fgSurface
        selectionColor: Colors.alpha(Colors.primary, 0.35)
        echoMode: field.password ? TextInput.Password : TextInput.Normal
        clip: true
        text: field.value
        onAccepted: field.accepted()
        onEditingFinished: field.editingFinished()
        Keys.onEscapePressed: event => {
            input.text = field.value;
            input.focus = false;
            event.accepted = true;
        }

        Text {
            anchors.fill: parent
            visible: input.text === ""
            text: field.placeholder
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
            font: input.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
}
