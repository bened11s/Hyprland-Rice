pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.widgets

// Symbolknopf der Screenshot-Werkzeugleiste. Beschriftung nur als Tooltip
// (mit dem Tastenkuerzel), der nach kurzem Verweilen erscheint – ueber oder
// unter dem Knopf, je nachdem wo die Leiste am Ausschnitt haengt.
Item {
    id: button

    property string icon: "circle"
    property string label: ""
    property string key: ""
    // Die Vorgabe-Aktion (Enter): gefuellt in der Akzentfarbe
    property bool primary: false
    property bool tipAbove: false

    signal clicked()

    // Ueberschreibbar, damit ein Test den Tooltip zeigen kann
    property bool hovered: area.containsMouse

    implicitWidth: 36
    implicitHeight: 36

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: button.primary ? Colors.primary
             : button.hovered ? Colors.alpha(Colors.fgBackground, 0.12) : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        // Hover-Schleier auf der gefuellten Vorgabe
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Colors.alpha(Colors.fgPrimary, button.primary && button.hovered ? 0.14 : 0)

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: button.icon
        font.family: "Material Symbols Outlined"
        font.pixelSize: 20
        color: button.primary ? Colors.fgPrimary : Colors.fgBackground
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    Timer {
        id: tipDelay

        interval: 350
        running: button.hovered
    }

    // ---- Tooltip ----
    Rectangle {
        id: tip

        readonly property real gap: 8
        readonly property bool shown: button.hovered && !tipDelay.running

        anchors.horizontalCenter: parent.horizontalCenter
        y: button.tipAbove ? -tip.gap - tip.height : button.height + tip.gap
        width: tipRow.implicitWidth + 20
        height: 26
        radius: 7
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.5)
        visible: opacity > 0
        opacity: tip.shown ? 1 : 0

        Fade on opacity {}

        Row {
            id: tipRow

            anchors.centerIn: parent
            spacing: 7

            Text {
                text: button.label
                font.family: Config.font
                font.pixelSize: 12
                color: Colors.fgBackground
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                visible: button.key !== ""
                text: button.key
                font.family: Config.font
                font.pixelSize: 11
                color: Colors.fgSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
