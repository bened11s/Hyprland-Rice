pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Grundgeruest der Notch-Untermenues (Medien, Steuerung, Benachrichtigungen,
// System). Dieselbe Schnittstelle wie PowerPanel, damit die Notch sie wie die
// anderen Launcher-Ansichten behandelt:
//   topOffset, cardRadius, inset, active  ->  outerWidth/outerHeight/maxOuterHeight
//
// Oben eine kleine Titelzeile (Symbol + Name), darunter der Inhalt. Keine
// eigene Karte: die Notch ist die Flaeche.
//
//     ViewPanel {
//         title: "Medien"; icon: "music_note"
//         contentWidth: 360
//         contentHeight: inhalt.implicitHeight
//         Inhalt { id: inhalt; width: parent.width }
//     }
Item {
    id: panel

    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false

    property string title: ""
    property string icon: ""
    // Breite und Hoehe des Inhalts (ohne Titel und Rand)
    property real contentWidth: 360
    property real contentHeight: 0
    // Groesster Fall – fuer die Fensterreserve der Notch
    property real maxContentHeight: panel.contentHeight

    default property alias content: body.data

    readonly property real padding: 14
    readonly property real headerHeight: 34

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    readonly property real maxOuterHeight: panel.headerHeight + panel.maxContentHeight + panel.padding + panel.inset

    implicitWidth: panel.contentWidth + panel.padding * 2
    implicitHeight: panel.headerHeight + panel.contentHeight + panel.padding

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset

    Keys.onEscapePressed: LauncherState.close()

    // ---- Titelzeile ----
    // Mittig, auf derselben Hoehe wie die Uhr der Uebersicht – links davon
    // stehen die Seiten-Punkte der Notch, die Kopfzeile ist dort die
    // Blaetter-Zone und bleibt beim Blaettern an Ort und Stelle.
    Row {
        id: header

        x: (panel.width - width) / 2
        height: panel.headerHeight - 8
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: panel.icon
            color: Colors.primary
            font.family: "Material Symbols Outlined"
            font.pixelSize: 16
            font.variableAxes: ({ wght: 600 })
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: panel.title
            color: Colors.fgBackground
            font.family: Config.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }

    Item {
        id: body

        x: panel.padding
        y: panel.headerHeight
        width: panel.width - panel.padding * 2
        height: panel.contentHeight
    }
}
