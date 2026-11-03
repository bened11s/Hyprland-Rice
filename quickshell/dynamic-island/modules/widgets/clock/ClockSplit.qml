import QtQuick

import qs
import qs.modules.services.config

// Geteilte Uhr: Stunden gross, Minuten klein und hochgestellt rechts daneben
// ("21 ³⁷"), die Minuten in der Akzentfarbe. Im 12-h-Modus steht unter den
// Minuten noch ein kleines AM/PM – erst ab Desktop-Groesse, in der Notch
// waere es nicht mehr lesbar.
Item {
    id: root

    property date date
    property real size: 16
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property bool use12h: Config.appearance.clock === "12h"
    property string fontFamily: Config.font
    property int weight: Font.Bold

    readonly property real gap: Math.max(1, Math.round(root.size * 0.08))
    readonly property bool showAp: root.use12h && root.size >= 40

    implicitWidth: hours.implicitWidth + root.gap + Math.max(minutes.implicitWidth, root.showAp ? ap.implicitWidth : 0)
    implicitHeight: hours.implicitHeight

    Text {
        id: hours

        text: Qt.formatDateTime(root.date, root.use12h ? "h" : "HH")
        color: root.color
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75
        font.weight: root.weight
        font.letterSpacing: root.size * 0.023
    }

    Text {
        id: minutes

        anchors {
            left: hours.right
            leftMargin: root.gap
            // Hochgestellt: Oberkante der Minuten auf Hoehe der Ziffern-
            // Oberkante (Versalhoehe ~ 0.72 der Schriftgroesse)
            top: hours.top
            topMargin: Math.round((hours.implicitHeight - root.size * 0.75) / 2 - root.size * 0.06)
        }
        text: Qt.formatDateTime(root.date, "mm")
        color: root.accent
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75 * 0.56
        font.weight: root.weight
        font.letterSpacing: root.size * 0.02
    }

    Text {
        id: ap

        anchors {
            left: hours.right
            leftMargin: root.gap + 1
            bottom: hours.bottom
            bottomMargin: Math.round((hours.implicitHeight - root.size * 0.75) / 2 + root.size * 0.04)
        }
        visible: root.showAp
        text: Qt.formatDateTime(root.date, "AP")
        color: root.color
        opacity: 0.6
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75 * 0.28
        font.weight: Font.DemiBold
        font.letterSpacing: root.size * 0.03
    }
}
