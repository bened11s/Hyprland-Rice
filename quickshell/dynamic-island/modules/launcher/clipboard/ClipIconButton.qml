import QtQuick

import qs
import qs.modules.widgets

// Kleiner Symbolknopf in einer Zeile der Zwischenablage (Anheften, Loeschen,
// Verlauf leeren). `shown` = false laesst den Platz stehen, blendet aber
// aus – sonst rutscht der Nachbar beim Ein-/Ausblenden unter der Maus weg.
Item {
    id: button

    property string icon: ""
    property bool danger: false
    property bool shown: true
    // Akzent (angeheftet) bzw. scharf (Loeschen bestaetigen)
    property bool on: false
    property bool armed: false

    signal clicked

    width: 24
    height: 24
    opacity: button.shown ? 1 : 0
    enabled: button.shown

    Fade on opacity {}

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: button.armed ? Colors.alpha(Colors.error, area.containsMouse ? 0.32 : 0.22)
             : area.containsMouse ? Colors.alpha(button.danger ? Colors.error : Colors.fgSurface, 0.12)
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    Text {
        anchors.centerIn: parent
        text: button.icon
        color: button.armed || (button.danger && area.containsMouse) ? Colors.error
             : button.on ? Colors.primary
             : Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: 16
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
