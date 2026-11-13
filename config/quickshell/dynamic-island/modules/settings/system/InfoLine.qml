pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Zeile in den Abschnitten der Info-Seite (SystemEditor): Bezeichnung links,
// Wert rechts; unter jeder Zeile ausser der letzten eine feine Linie.
// Solange die Daten noch geladen werden, steht "…", fehlt ein Wert danach,
// "–".
Item {
    id: line

    required property string label
    property string value: ""
    // Daten noch unterwegs (SystemInfo.loaded / ShellUpdate.loaded)
    property bool pending: false
    property bool last: false

    width: parent?.width ?? 200
    height: 46

    Text {
        id: labelText

        anchors {
            left: parent.left
            leftMargin: 16
            verticalCenter: parent.verticalCenter
        }
        text: line.label
        color: Colors.fgSurface
        font.family: Config.font
        font.pixelSize: 13
    }

    Text {
        anchors {
            left: labelText.right
            leftMargin: 16
            right: parent.right
            rightMargin: 16
            verticalCenter: parent.verticalCenter
        }
        text: line.value !== "" ? line.value : line.pending ? "…" : "–"
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 13
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }

    Divider {
        visible: !line.last
    }
}
