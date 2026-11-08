import QtQuick

import qs
import qs.modules.services.config

// Einzeiliges Eingabefeld mit Symbol und Platzhalter (Suche, Name, Befehl).
Rectangle {
    id: field

    property string icon: ""
    property string placeholder: ""
    property alias text: input.text
    property alias input: input
    property bool mono: false

    signal accepted
    signal escaped

    height: 32
    radius: 9
    color: Colors.alpha(Colors.fgSurface, input.activeFocus ? 0.09 : 0.06)
    border.width: 1
    border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.6) : Colors.alpha(Colors.outline, 0.3)

    Behavior on border.color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }

    Text {
        id: fieldIcon

        anchors {
            left: parent.left
            leftMargin: 9
            verticalCenter: parent.verticalCenter
        }
        visible: field.icon !== ""
        text: field.icon
        color: input.activeFocus ? Colors.primary : Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: 16
    }

    TextInput {
        id: input

        anchors {
            left: field.icon !== "" ? fieldIcon.right : parent.left
            leftMargin: 8
            right: clear.visible ? clear.left : parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        color: Colors.fgSurface
        font.family: field.mono ? "monospace" : Config.font
        font.pixelSize: field.mono ? 12 : 13
        selectionColor: Colors.alpha(Colors.primary, 0.35)
        selectedTextColor: Colors.fgSurface
        clip: true

        Keys.onReturnPressed: field.accepted()
        Keys.onEnterPressed: field.accepted()
        Keys.onEscapePressed: {
            if (input.text !== "")
                input.text = "";
            else
                field.escaped();
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

    // Leeren
    Text {
        id: clear

        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        visible: input.text !== ""
        text: "close"
        color: clearHover.hovered ? Colors.fgSurface : Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: 15

        HoverHandler {
            id: clearHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: input.text = ""
        }
    }
}
