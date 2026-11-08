pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.config

import qs

// Eine Karte der Einstellungsliste (SettingsCard): Titel und ihre Zeilen.
// Der Titel ist die Gruppe aus Config.meta (`group`), bei "Alle"/Suche steht
// der Bereich davor.
Rectangle {
    id: gcard

    // { section, group, rows, wide } aus SettingsCard.groupCards
    required property var group
    // SettingsCard.entries – rows sind Indizes darin
    property var entries: []
    // Bereich vor dem Gruppentitel ("" = keiner)
    property string sectionLabel: ""

    readonly property var rows: gcard.group?.rows ?? []
    // Eine einzelne Zeile, die schon so heisst wie ihre Gruppe, braucht
    // keinen Titel darueber
    readonly property string groupLabel: {
        const g = gcard.group?.group ?? "";
        if (g === "" || (gcard.rows.length === 1 && gcard.entries[gcard.rows[0]]?.title === I18n.tr(g)))
            return "";
        return I18n.tr(g);
    }
    readonly property bool titled: gcard.sectionLabel !== "" || gcard.groupLabel !== ""

    height: cardColumn.implicitHeight + 8
    radius: 16
    color: Colors.alpha(Colors.fgSurface, 0.035)
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.14)

    Column {
        id: cardColumn

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 4
        }

        Row {
            visible: gcard.titled
            height: gcard.titled ? 30 : 0
            leftPadding: 14
            spacing: 6

            Text {
                anchors.bottom: parent.bottom
                bottomPadding: 4
                visible: gcard.sectionLabel !== ""
                text: gcard.sectionLabel
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Text {
                anchors.bottom: parent.bottom
                bottomPadding: 4
                visible: gcard.groupLabel !== ""
                text: (gcard.sectionLabel !== "" ? "· " : "") + gcard.groupLabel
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 11
                font.weight: gcard.sectionLabel !== "" ? Font.Normal : Font.DemiBold
            }
        }

        Repeater {
            model: gcard.rows

            SettingsRow {
                required property int modelData

                width: cardColumn.width
                entry: gcard.entries[modelData] ?? null
            }
        }
    }
}
