pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.widgets

// Werkzeugleiste am Ausschnitt: eine Reihe Symbolknoepfe, die Vorgabe-Aktion
// (Enter) gefuellt. Die Aufnahme steht abgesetzt am Ende, weil sie kein
// Bild erzeugt, sondern das Overlay gegen eine laufende Aufnahme tauscht.
// Klicks und Hover bleiben auf der Leiste – darunter liegt die Zeigerflaeche
// des Overlays, die sonst ein Fenster waehlen wuerde.
Surface {
    id: bar

    property string preset: "copy"
    // Leiste haengt ueber dem Ausschnitt: Tooltips dann nach oben
    property bool tipAbove: false

    signal picked(string action)

    readonly property bool hovered: hover.hovered

    readonly property var actions: [
        { id: "copy", icon: "content_copy", label: I18n.tr("Kopieren"), key: "C" },
        { id: "save", icon: "save", label: I18n.tr("Speichern"), key: "S" },
        { id: "edit", icon: "edit", label: I18n.tr("Bearbeiten"), key: "E" },
        { id: "ocr", icon: "document_scanner", label: I18n.tr("Text erkennen"), key: "T" },
        { id: "qr", icon: "qr_code_scanner", label: I18n.tr("QR-Code"), key: "Q" },
        { id: "record", icon: "screen_record", label: I18n.tr("Aufnehmen"), key: "R" }
    ]

    implicitWidth: row.implicitWidth + 10
    implicitHeight: row.implicitHeight + 10
    clipContent: false
    maxRadius: height / 2

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: bar.actions

            Item {
                id: slot

                required property var modelData
                readonly property bool last: slot.modelData.id === "record"

                implicitWidth: button.implicitWidth + (slot.last ? 9 : 0)
                implicitHeight: button.implicitHeight

                // Trennstrich vor der Aufnahme
                Rectangle {
                    visible: slot.last
                    anchors.verticalCenter: parent.verticalCenter
                    x: 3
                    width: 1
                    height: 18
                    color: Colors.alpha(Colors.outline, 0.5)
                }

                ShotButton {
                    id: button

                    anchors.right: parent.right
                    icon: slot.modelData.icon
                    label: slot.modelData.label
                    key: slot.modelData.key
                    primary: slot.modelData.id === bar.preset
                    tipAbove: bar.tipAbove
                    onClicked: bar.picked(slot.modelData.id)
                }
            }
        }
    }
}
