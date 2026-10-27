pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config

// Schnellkachel fuer Plugins – dieselbe Optik wie die eingebauten Kacheln
// der Settings-Karte (Android-Tray-Stil): aktiv ist die ganze Kachel in der
// Akzentfarbe, inaktiv eine neutrale Flaeche; unter 150 px Breite bleibt
// nur das Symbol, mittig.
//
// Vertrag fuer Plugin-Autoren (plugins/README.md). Die Kachel-Datei aus
// plugin.json (`tiles.<id>.component`) wird von SettingsTiles.qml geladen
// und bekommt `plugin` (Kontext-Objekt) und `tileId` gesetzt:
//
//     import qs.modules.widgets
//
//     QuickTile {
//         id: tile
//         active: tile.plugin.settings.lamp === true
//         subtitle: tile.active ? "An" : "Aus"
//         onToggled: tile.plugin.set("lamp", !tile.active)
//     }
//
// Symbol und Titel kommen aus dem Manifest (tiles.<id>.icon / .label), lassen
// sich hier aber ueberschreiben – z.B. ein anderes Symbol je Zustand. Kinder
// landen auf der Kachel (default property), etwa ein Zusatzknopf rechts;
// `tapEnabled: false` schaltet den eigenen Tap ab, wenn die Kachel ihn
// selbst verteilt (siehe die Wi-Fi-Pille in SettingsTiles.qml).
Rectangle {
    id: tile

    // Vom Lader gesetzt: Kontext des Plugins (id, name, settings, set(), ...)
    // und die Kachel-ID aus dem Manifest
    property var plugin: null
    property string tileId: ""
    readonly property var meta: tile.plugin?.manifest?.tiles?.[tile.tileId] ?? ({})

    property string icon: tile.meta.icon ?? tile.plugin?.manifest?.icon ?? "extension"
    property string title: tile.meta.label ?? tile.tileId
    property string subtitle: ""
    property bool active: false

    // Farbe des aktiven Zustands (Standard: Themenfarbe)
    property color accent: Colors.primary
    property color onAccent: Colors.fgPrimary

    // false = die Kachel togglet nicht selbst (eigener TapHandler im Plugin)
    property bool tapEnabled: true
    signal toggled()

    default property alias content: extras.data

    // Schmale Zelle (eine Rasterspalte): nur das Symbol, mittig
    readonly property bool compact: width < 150

    // Vordergrundfarben, passend zum Zustand – fuer eigene Knoepfe auf der Kachel
    readonly property color fg: tile.active ? tile.onAccent : Colors.fgBackground
    readonly property color fgDim: tile.active ? Colors.alpha(tile.onAccent, 0.78) : Colors.fgSurfaceVariant
    readonly property color controlColor: tile.active ? Colors.alpha(tile.onAccent, 0.18) : Colors.alpha(Colors.fgSurface, 0.1)
    readonly property color controlHover: tile.active ? Colors.alpha(tile.onAccent, 0.3) : Colors.alpha(Colors.fgSurface, 0.18)

    implicitHeight: 54
    radius: height / 2
    color: tile.active ? tile.accent : Colors.alpha(Colors.fgSurface, 0.08)

    Behavior on color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }

    // Hover-Schleier
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Colors.alpha(tile.fg, tileHover.hovered ? 0.06 : 0)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.leftMargin: tile.compact ? (tile.width - 28) / 2 : 16
        spacing: 12

        Item {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28

            Text {
                anchors.centerIn: parent
                text: tile.icon
                font.family: "Material Symbols Outlined"
                font.pixelSize: 22
                color: tile.active ? tile.onAccent : Colors.fgSurfaceVariant

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            visible: !tile.compact

            Text {
                font.family: Config.font
                text: tile.title
                color: tile.fg
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                font.family: Config.font
                text: tile.subtitle
                color: tile.fgDim
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: text !== ""
            }
        }
    }

    TapHandler {
        enabled: tile.tapEnabled
        onTapped: tile.toggled()
    }

    HoverHandler {
        id: tileHover

        cursorShape: Qt.PointingHandCursor
    }

    // Eigene Kinder der Kachel (Zusatzknoepfe usw.), ueber dem Text
    Item {
        id: extras

        anchors.fill: parent
    }
}
