pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.config

import qs

// Auswahlknopf: zeigt den aktuellen Wert, Klick klappt die Liste auf
// (SettingsMenu). Ersetzt Chip-Wolken fuer Auswahlen mit vielen Werten.
//
//   options   Werte (beliebiger Typ)
//   current   gewaehlter Wert (Vergleich per String)
//   labelOf   Anzeigename eines Werts, Vorgabe String(v)
//   fontOf    Schrift je Wert (Schriftauswahl), Vorgabe Config.font
//   iconOf    Symbol je Wert in der Liste (der gewaehlte zeigt den Haken)
//   above     Liste ueber statt unter dem Knopf (Leisten am unteren Rand)
//   picked(v) Signal bei Auswahl
Rectangle {
    id: drop

    property var options: []
    property var current: undefined
    property var labelOf: v => String(v)
    property var fontOf: null
    property var iconOf: null
    property bool above: false
    // Liste sichtbar (bis das Ausblenden fertig ist) – Verwender ausserhalb
    // des Einstellungsfensters sperren damit, was unter der Liste liegt
    readonly property bool menuOpen: menu.visible
    // Zusaetzliche Eintraege unter einer Trennlinie (z.B. "Benutzerdefiniert")
    property var extraEntries: []
    property real maxWidth: 240
    signal picked(var value)

    readonly property string currentLabel: drop.current === undefined || drop.current === null ? "" : drop.labelOf(drop.current)

    implicitWidth: Math.min(drop.maxWidth, valueText.implicitWidth + 44)
    implicitHeight: 30
    radius: 8
    opacity: enabled ? 1 : 0.4
    color: menu.opened ? Colors.alpha(Colors.fgSurface, 0.12)
         : dropHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
         : Colors.alpha(Colors.fgSurface, 0.06)

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Text {
        id: valueText

        anchors {
            left: parent.left
            leftMargin: 12
            right: arrow.left
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        text: drop.currentLabel
        color: Colors.fgSurface
        font.family: drop.fontOf && drop.current !== undefined ? drop.fontOf(drop.current) : Config.font
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    Text {
        id: arrow

        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        text: "expand_more"
        color: Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: 18
        rotation: menu.opened ? 180 : 0

        Behavior on rotation {
            NumberAnimation { duration: 140 }
        }
    }

    HoverHandler {
        id: dropHover

        cursorShape: drop.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: drop.enabled
        onTapped: menu.opened ? menu.close() : menu.open()
    }

    SettingsMenu {
        id: menu

        y: drop.above ? -menu.height - 4 : drop.height + 4
        minWidth: drop.width
        entries: drop.options.map(v => ({
            text: drop.labelOf(v),
            current: String(v) === String(drop.current),
            font: drop.fontOf ? drop.fontOf(v) : undefined,
            icon: drop.iconOf ? drop.iconOf(v) : undefined,
            action: () => drop.picked(v)
        })).concat(drop.extraEntries.length > 0 ? [{ separator: true }].concat(drop.extraEntries) : [])
    }
}
