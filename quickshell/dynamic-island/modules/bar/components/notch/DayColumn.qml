pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Eine Spalte im Tagesstreifen: Wochentag oben, Datum in der Pille darunter.
// Größe, Deckkraft und Farbe ergeben sich aus dem Abstand zur Mitte:
// Mitte = gewählter Tag (blau, volles Kürzel), nach außen kleiner und blasser.
// Heute ist immer rot, egal wo es gerade steht.
Item {
    id: column

    required property date day
    required property date today
    required property int offset          // Abstand zur Mitte, negativ = früher

    readonly property int distance: Math.min(Math.abs(offset), 4)
    readonly property bool isFocus: offset === 0
    readonly property bool isToday: day.getDate() === today.getDate()
                                 && day.getMonth() === today.getMonth()
                                 && day.getFullYear() === today.getFullYear()

    readonly property color accent: isToday ? Colors.error
                                  : isFocus ? Colors.primary
                                  : Colors.fgSurface

    implicitWidth: 26
    implicitHeight: 40
    opacity: [1, 0.72, 0.48, 0.3, 0.18][distance]

    Behavior on opacity {
        NumberAnimation { duration: 140 }
    }

    // Wochentag: nur der gewählte Tag bekommt das volle Kürzel
    Text {
        font.family: Config.font
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 1
        }
        text: {
            const name = column.day.toLocaleDateString(I18n.locale, "ddd").replace(".", "").toUpperCase();
            return column.isFocus ? name : name.charAt(0);
        }
        color: column.isToday ? Colors.error
             : column.isFocus ? Colors.primary
             : Colors.fgSurfaceVariant
        font.pixelSize: [9.5, 8.5, 8, 7.5, 7][column.distance]
        font.weight: column.isFocus || column.isToday ? Font.Bold : Font.Normal
        font.letterSpacing: 0.5
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 15
        width: 24
        height: 22
        radius: height / 2
        color: column.isFocus ? Colors.alpha(Colors.primary, 0.16) : "transparent"

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Text {
            font.family: Config.font
            anchors.centerIn: parent
            text: column.day.getDate()
            color: column.accent
            font.pixelSize: [15, 13, 11.5, 10, 9][column.distance]
            font.weight: column.isFocus || column.isToday ? Font.Bold : Font.Normal
        }
    }
}
