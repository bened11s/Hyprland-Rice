pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.config

import qs

// Eine Gruppe der Einstellungsliste (SettingsCard), im Stil von Caelestia:
// kleine Ueberschrift ueber einem gerundeten Container, darin die Zeilen mit
// feinen Trennlinien. Die Ueberschrift ist die Gruppe aus Config.meta
// (`group`), sonst der Abschnitt; heisst sie wie die Seite, faellt sie weg.
// Bei der Suche steht "Bereich · Gruppe".
//
// Grosse Editoren, die sich selbst zeichnen (`bare`, z. B. Monitore, Info),
// stehen ohne Container, Ueberschrift und Titelzeile da.
Item {
    id: gcard

    // { section, page, group, rows, bare } aus SettingsCard.groupCards
    required property var group
    // SettingsCard.entries – rows sind Indizes darin
    property var entries: []
    // Suche: Bereich vor der Gruppe ("" = keine Suche)
    property string sectionLabel: ""
    // Titel der Seite – eine Ueberschrift, die genauso heisst, entfaellt
    property string pageTitle: ""
    // Titel eines Abschnitts (SettingsCard.sectionTitle)
    property var titleOf: s => s

    readonly property var rows: gcard.group?.rows ?? []
    readonly property bool bare: gcard.group?.bare ?? false
    readonly property string heading: {
        if (gcard.bare)
            return "";
        const g = gcard.group?.group ? I18n.tr(gcard.group.group) : "";
        if (gcard.sectionLabel !== "")
            return g !== "" && g !== gcard.sectionLabel ? `${gcard.sectionLabel} · ${g}` : gcard.sectionLabel;
        const t = g !== "" ? g : gcard.titleOf(gcard.group?.page ?? "");
        // Eine einzelne Zeile, die schon so heisst, braucht keine Ueberschrift
        if (t === gcard.pageTitle || (gcard.rows.length === 1 && gcard.entries[gcard.rows[0]]?.title === t))
            return "";
        return t;
    }

    implicitHeight: (gcard.heading !== "" ? headingText.implicitHeight + 8 : 0) + box.height

    Text {
        id: headingText

        visible: gcard.heading !== ""
        leftPadding: 4
        text: gcard.heading
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: box

        y: gcard.heading !== "" ? headingText.implicitHeight + 8 : 0
        width: parent.width
        height: cardColumn.implicitHeight
        radius: 16
        color: gcard.bare ? "transparent" : Colors.alpha(Colors.fgSurface, 0.04)

        Column {
            id: cardColumn

            width: parent.width

            Repeater {
                model: gcard.rows

                Item {
                    id: slot

                    required property int modelData
                    required property int index

                    width: cardColumn.width
                    height: settingsRow.implicitHeight

                    // Trennlinie zur Zeile davor
                    Rectangle {
                        visible: slot.index > 0 && !gcard.bare
                        x: 16
                        width: parent.width - 32
                        height: 1
                        color: Colors.alpha(Colors.outline, 0.15)
                    }

                    SettingsRow {
                        id: settingsRow

                        width: parent.width
                        bare: gcard.bare
                        entry: gcard.entries[slot.modelData] ?? null
                    }
                }
            }
        }
    }
}
