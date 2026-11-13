import QtQuick

import qs

// Feine Trennlinie am unteren Rand einer Zeile der Info-Seite, links und
// rechts 16 px eingerueckt.
Rectangle {
    anchors {
        left: parent.left
        right: parent.right
        bottom: parent.bottom
        leftMargin: 16
        rightMargin: 16
    }
    height: 1
    color: Colors.alpha(Colors.outline, 0.15)
}
