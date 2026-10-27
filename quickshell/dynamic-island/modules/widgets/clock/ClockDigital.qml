import QtQuick

import qs
import qs.modules.services.config

// Digitale Uhr "HH:mm" bzw. "h:mm AP" – das klassische Notch-Label.
//
// Die Schriftgroesse laeuft ueber pointSize (size * 0.75 = Punkt bei 96 dpi),
// damit die Notch mit size 13 * 96 / 72 exakt ihre alten 13 pt bekommt.
Item {
    id: root

    property date date
    property real size: 16
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property bool use12h: Config.appearance.clock === "12h"
    property string fontFamily: Config.font
    property int weight: Font.Bold

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label

        text: Qt.formatDateTime(root.date, root.use12h ? "h:mm AP" : "HH:mm")
        color: root.color
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75
        font.weight: root.weight
        // 0.4 px bei der Notch-Groesse, proportional darueber
        font.letterSpacing: root.size * 0.023
    }
}
