pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Abschnitt der Info-Seite: kleine Ueberschrift ausserhalb, darunter ein
// gerundeter Behaelter ohne Rand mit den Zeilen als Spalte. Die Zeilen
// bringen ihren Innenabstand selbst mit.
Column {
    id: card

    property string title: ""
    default property alias content: rows.data

    spacing: 8

    Text {
        leftPadding: 4
        visible: card.title !== ""
        text: card.title
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Rectangle {
        width: parent.width
        height: rows.implicitHeight
        radius: 16
        color: Colors.alpha(Colors.fgSurface, 0.04)

        Column {
            id: rows

            width: parent.width
        }
    }
}
