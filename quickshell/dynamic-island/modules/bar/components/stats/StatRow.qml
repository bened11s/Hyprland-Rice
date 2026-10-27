pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Eine Messzeile der Statistik-Karte: Symbol, Bezeichnung, Balken, Wert.
//
// Der Balken ist derselbe Rectangle-Trick wie im LevelSlider der Settings –
// nur ohne dessen Maus- und Rad-Steuerung, hier wird nichts gestellt.
Item {
    id: row

    property string icon
    property string label
    // 0…1; negativ heisst "kein Balken, nur Text"
    property real value: -1
    property string detail: ""
    // Farblich hervorheben (heiss, fast voll)
    property bool warn: false

    implicitHeight: 30

    Text {
        id: iconLabel

        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        text: row.icon
        color: row.warn ? Colors.error : Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: 16
    }

    Text {
        id: name
        font.family: Config.font

        anchors {
            left: iconLabel.right
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        width: 34
        text: row.label
        color: Colors.fgBackground
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    Text {
        id: detail
        font.family: Config.font

        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        text: row.detail
        color: row.warn ? Colors.error : Colors.fgSurfaceVariant
        font.pixelSize: 11
        horizontalAlignment: Text.AlignRight
    }

    Rectangle {
        anchors {
            left: name.right
            leftMargin: 10
            right: detail.left
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        height: 6
        radius: height / 2
        color: Colors.alpha(Colors.fgSurface, 0.16)
        visible: row.value >= 0

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, row.value))
            height: parent.height
            radius: parent.radius
            color: row.warn ? Colors.error : Colors.primary

            Behavior on width {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 200 }
            }
        }
    }
}
