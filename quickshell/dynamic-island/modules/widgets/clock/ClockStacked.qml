import QtQuick

import qs
import qs.modules.services.config

// Gestapelte Uhr: Stunden ueber Minuten, eng gesetzt, grosse Ziffern – vor
// allem fuer das Desktop-Widget. Die Minuten stehen in der Akzentfarbe.
Item {
    id: root

    property date date
    property real size: 16
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property bool use12h: Config.appearance.clock === "12h"
    property string fontFamily: Config.font
    property int weight: Font.Bold

    // Zeilen ueberlappen: der Zeilenabstand der Schrift ist fuer Ziffern
    // viel zu luftig, die Versalien sind nur ~0.72 der Groesse hoch
    readonly property real overlap: Math.round(root.size * 0.22)
    readonly property bool showAp: root.use12h && root.size >= 40

    implicitWidth: Math.max(hours.implicitWidth, minutes.implicitWidth) + (root.showAp ? ap.implicitWidth + root.size * 0.1 : 0)
    implicitHeight: hours.implicitHeight + minutes.implicitHeight - root.overlap

    Text {
        id: hours

        anchors.horizontalCenter: minutes.horizontalCenter
        text: Qt.formatDateTime(root.date, root.use12h ? "h" : "HH")
        color: root.color
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75
        font.weight: root.weight
        font.letterSpacing: root.size * 0.01
    }

    Text {
        id: minutes

        x: 0
        y: hours.implicitHeight - root.overlap
        text: Qt.formatDateTime(root.date, "mm")
        color: root.accent
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75
        font.weight: root.weight
        font.letterSpacing: root.size * 0.01
    }

    Text {
        id: ap

        anchors {
            left: minutes.right
            leftMargin: root.size * 0.1
            baseline: minutes.baseline
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
