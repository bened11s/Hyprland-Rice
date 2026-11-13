pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config
import qs.modules.services.desktop
import qs.modules.settings

// Leiste rechts unten beim Bearbeiten der Desktop-Widgets (nur auf dem
// Monitor, auf dem bearbeitet wird), im Stil des Einstellungsfensters
// (docs/settings-style.md): Szene als Auswahlknopf (wohin die Aenderungen
// gehen), Widget hinzufuegen, seltene Aktionen im ⋮ (automatisch anordnen,
// Szene loeschen), Abbrechen (alles seit dem Start zurueck), Fertig.
// "Szene loeschen" fragt in der Leiste nach.
//
// Die Optionen eines Widgets haengen nicht hier, sondern angedockt am
// Widget selbst (WidgetOptions.qml).
//
// In der Szenen-Liste tragen Ziele ohne eigene Szene ein "+" (Auswahl legt
// sie als Kopie des Sichtbaren an).
Rectangle {
    id: bar

    property string screenName: ""
    readonly property bool adding: Scenes.adding
    // Rueckfrage "Szene wirklich loeschen?" statt der Knoepfe
    property bool confirmDrop: false
    // DesktopScreen schliesst darueber "das Menue der Leiste" (Esc, Klick ins
    // Leere, Rechtsklick). Die Listen sind jetzt Popups und schliessen sich
    // selbst – uebrig ist die Rueckfrage, die genauso weggehen soll
    property alias scenesOpen: bar.confirmDrop
    readonly property bool canDrop: Scenes.target !== "*" && Array.isArray(Scenes.scenes[Scenes.target])

    onAddingChanged: if (bar.adding) bar.confirmDrop = false
    onCanDropChanged: if (!bar.canDrop) bar.confirmDrop = false

    implicitWidth: (bar.confirmDrop ? confirm : actions).implicitWidth + 16
    implicitHeight: 46
    width: implicitWidth
    height: implicitHeight
    radius: 14
    color: Colors.alpha(Colors.background, 0.94)
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.5)

    // Maus ueber der Leiste: Widgets darunter sperren (WidgetHost.blocked).
    // Die Listen liegen als Popup ausserhalb der Leiste – solange eine offen
    // ist, gilt dasselbe, sonst traefe ein Klick in die Liste das Widget
    // darunter (Qt 6 reicht den Druck an alle Handler darunter weiter)
    readonly property bool hovered: barHover.hovered || sceneDrop.menuOpen || more.menuOpen

    HoverHandler {
        id: barHover
    }

    // Klicks bleiben auf der Leiste
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    RowLayout {
        id: actions

        anchors.centerIn: parent
        visible: !bar.confirmDrop
        spacing: 6

        SettingsDropdown {
            id: sceneDrop

            above: true
            options: Scenes.targets.map(t => t.key)
            current: Scenes.target
            labelOf: key => Scenes.targets.find(t => t.key === key)?.label ?? I18n.tr("Szene")
            iconOf: key => Scenes.targets.find(t => t.key === key)?.own ? "" : "add"
            onPicked: key => Scenes.setTarget(key)
        }

        EditButton {
            text: I18n.tr("Widget hinzufügen")
            active: bar.adding
            // Auswahl ueber der Leiste (WidgetPicker, DesktopScreen)
            onClicked: {
                if (Scenes.adding)
                    Scenes.adding = false;
                else {
                    // auf dem Monitor dieser Leiste
                    Scenes.editScreen = bar.screenName;
                    Scenes.openPicker(null);
                }
            }
        }

        SettingsMenuButton {
            id: more

            above: true
            entries: [
                {
                    text: I18n.tr("Automatisch anordnen"),
                    icon: "auto_awesome_mosaic",
                    enabled: Scenes.widgets.length > 0 && Scenes.analysis !== null,
                    action: () => Scenes.arrange()
                },
                { separator: true },
                // "Ueberall" und Ziele ohne eigene Szene haben nichts zu loeschen
                {
                    text: I18n.tr("Szene löschen"),
                    icon: "delete",
                    danger: true,
                    enabled: bar.canDrop,
                    action: () => bar.confirmDrop = true
                }
            ]
        }

        EditButton {
            Layout.leftMargin: 10
            text: I18n.tr("Abbrechen")
            onClicked: Scenes.cancel()
        }

        EditButton {
            text: I18n.tr("Fertig")
            primary: true
            onClicked: Scenes.done()
        }
    }

    RowLayout {
        id: confirm

        anchors.centerIn: parent
        visible: bar.confirmDrop
        spacing: 6

        Text {
            Layout.leftMargin: 8
            Layout.rightMargin: 10
            text: I18n.tr("Szene wirklich löschen?")
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 12
        }

        EditButton {
            text: I18n.tr("Löschen")
            danger: true
            onClicked: {
                bar.confirmDrop = false;
                Scenes.dropTarget();
            }
        }

        EditButton {
            text: I18n.tr("Abbrechen")
            onClicked: bar.confirmDrop = false
        }
    }
}
