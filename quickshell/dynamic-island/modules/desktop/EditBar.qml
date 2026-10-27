pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Leiste unten mittig beim Bearbeiten der Desktop-Widgets (nur auf dem
// Monitor, auf dem bearbeitet wird): wohin die Aenderungen gehen (Dieses
// Bild / Ordner / Ueberall), Widget hinzufuegen, automatisch anordnen,
// Abbrechen (alles seit dem Start zurueck), Fertig.
//
// Die Optionen eines Widgets haengen nicht hier, sondern angedockt am
// Widget selbst (WidgetOptions.qml).
//
// Ziele ohne eigene Szene tragen ein "+" (Klick legt sie als Kopie des
// Sichtbaren an). "Szene loeschen" fragt einmal nach.
Rectangle {
    id: bar

    property string screenName: ""
    readonly property bool adding: Scenes.adding
    property bool dropArmed: false

    Timer {
        id: disarmDrop

        interval: 3000
        onTriggered: bar.dropArmed = false
    }

    implicitWidth: rows.implicitWidth + 24
    implicitHeight: rows.implicitHeight + 20
    width: implicitWidth
    height: implicitHeight
    radius: 20
    color: Colors.alpha(Colors.background, 0.94)
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.5)

    // Maus ueber der Leiste: Widgets darunter sperren (WidgetHost.blocked)
    readonly property bool hovered: barHover.hovered

    HoverHandler {
        id: barHover
    }

    // Klicks bleiben auf der Leiste
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on implicitHeight {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    RowLayout {
        id: rows

        anchors.centerIn: parent
        spacing: 6

        EditLabel {
            text: I18n.tr("Szene")
        }

        Repeater {
            model: Scenes.targets

            EditChip {
                required property var modelData

                text: modelData.label
                // Noch keine eigene Szene: "+" = beim Klick anlegen
                icon: modelData.own ? "" : "add"
                dim: !modelData.own
                on: Scenes.target === modelData.key
                onClicked: Scenes.setTarget(modelData.key)
            }
        }

        EditChip {
            visible: Scenes.target !== "*" && Array.isArray(Scenes.scenes[Scenes.target])
            icon: bar.dropArmed ? "check" : "layers_clear"
            text: bar.dropArmed ? I18n.tr("Szene löschen?") : ""
            danger: true
            armed: bar.dropArmed
            onClicked: {
                if (bar.dropArmed) {
                    bar.dropArmed = false;
                    Scenes.dropTarget();
                } else {
                    bar.dropArmed = true;
                    disarmDrop.restart();
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 18
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            color: Colors.alpha(Colors.outline, 0.5)
        }

        EditChip {
            icon: "add"
            text: I18n.tr("Widget")
            on: bar.adding
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

        EditChip {
            icon: "auto_awesome_mosaic"
            text: I18n.tr("Anordnen")
            visible: Scenes.widgets.length > 0 && Scenes.analysis !== null
            onClicked: Scenes.arrange()
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 18
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            color: Colors.alpha(Colors.outline, 0.5)
        }

        EditChip {
            icon: "close"
            text: I18n.tr("Abbrechen")
            onClicked: Scenes.cancel()
        }

        EditChip {
            icon: "check"
            text: I18n.tr("Fertig")
            on: true
            onClicked: Scenes.done()
        }
    }
}
