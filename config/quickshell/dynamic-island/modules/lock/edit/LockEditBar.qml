pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.desktop
import qs.modules.lock
import qs.modules.services.config
import qs.modules.settings

// Leiste des Anordnungs-Editors (EditStage.qml), gleicher Bau wie die Leiste
// der Desktop-Widgets (EditBar.qml, docs/settings-style.md): Widget
// hinzufuegen, seltene Aktionen im ⋮ (Rueckgaengig, Wiederherstellen,
// Zuruecksetzen von Uhr und Karte auf die Vorgabe), Abbrechen (alles seit dem
// Start zurueck), Fertig. "Zuruecksetzen" fragt in der Leiste nach.
Rectangle {
    id: bar

    // Rueckfrage "Uhr und Medien zuruecksetzen?" statt der Knoepfe
    property bool confirmReset: false
    readonly property bool adding: LockLayout.adding
    readonly property bool canReset: LockLayout.custom

    onAddingChanged: if (bar.adding) bar.confirmReset = false
    onCanResetChanged: if (!bar.canReset) bar.confirmReset = false

    implicitWidth: (bar.confirmReset ? confirm : actions).implicitWidth + 16
    implicitHeight: 46
    width: implicitWidth
    height: implicitHeight
    radius: 14
    color: Colors.alpha(Colors.background, 0.94)
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.5)

    // Maus ueber der Leiste: Griffe darunter sperren (EditStage.overUi). Die
    // Liste des ⋮ liegt als Popup ausserhalb der Leiste – solange sie offen
    // ist, gilt dasselbe (Qt 6 reicht den Druck an alle Handler darunter weiter)
    readonly property bool hovered: barHover.hovered || more.menuOpen

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
        visible: !bar.confirmReset
        spacing: 6

        EditButton {
            text: I18n.tr("Widget hinzufügen")
            active: bar.adding
            // Auswahl ueber der Leiste (WidgetPicker, EditStage)
            onClicked: {
                if (LockLayout.adding) {
                    LockLayout.adding = false;
                } else {
                    LockLayout.selected = "";
                    LockLayout.openPicker(null);
                }
            }
        }

        SettingsMenuButton {
            id: more

            above: true
            entries: [
                {
                    text: I18n.tr("Rückgängig"),
                    icon: "undo",
                    enabled: LockLayout.canUndo,
                    action: () => LockLayout.undo()
                },
                {
                    text: I18n.tr("Wiederherstellen"),
                    icon: "redo",
                    enabled: LockLayout.canRedo,
                    action: () => LockLayout.redo()
                },
                { separator: true },
                // Uhr und Karte auf die Vorgabe, Widgets bleiben
                {
                    text: I18n.tr("Zurücksetzen"),
                    icon: "restart_alt",
                    danger: true,
                    enabled: bar.canReset,
                    action: () => bar.confirmReset = true
                }
            ]
        }

        EditButton {
            Layout.leftMargin: 10
            text: I18n.tr("Abbrechen")
            onClicked: LockLayout.cancel()
        }

        EditButton {
            text: I18n.tr("Fertig")
            primary: true
            onClicked: LockLayout.done()
        }
    }

    RowLayout {
        id: confirm

        anchors.centerIn: parent
        visible: bar.confirmReset
        spacing: 6

        Text {
            Layout.leftMargin: 8
            Layout.rightMargin: 10
            text: I18n.tr("Uhr und Medien zurücksetzen?")
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 12
        }

        EditButton {
            text: I18n.tr("Zurücksetzen")
            danger: true
            onClicked: {
                bar.confirmReset = false;
                LockLayout.selected = "";
                LockLayout.reset();
            }
        }

        EditButton {
            text: I18n.tr("Abbrechen")
            onClicked: bar.confirmReset = false
        }
    }
}
