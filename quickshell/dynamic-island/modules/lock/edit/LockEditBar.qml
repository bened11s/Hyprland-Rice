pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.desktop
import qs.modules.lock

// Leiste des Anordnungs-Editors (EditStage.qml): Widget hinzufuegen,
// Zuruecksetzen von Uhr und Karte auf die Vorgabe (fragt einmal nach),
// Abbrechen (alles seit dem Start zurueck), Fertig. Gleicher Bau wie die Leiste der Desktop-Widgets (EditBar.qml).
Rectangle {
    id: bar

    property bool resetArmed: false

    Timer {
        id: disarmReset

        interval: 3000
        onTriggered: bar.resetArmed = false
    }

    implicitWidth: rows.implicitWidth + 24
    implicitHeight: rows.implicitHeight + 20
    width: implicitWidth
    height: implicitHeight
    radius: 20
    color: Colors.alpha(Colors.background, 0.94)
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.5)

    // Maus ueber der Leiste: Griffe darunter sperren (EditStage.overUi)
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

    RowLayout {
        id: rows

        anchors.centerIn: parent
        spacing: 6

        EditChip {
            icon: "add"
            text: I18n.tr("Widget")
            on: LockLayout.adding
            onClicked: {
                if (LockLayout.adding) {
                    LockLayout.adding = false;
                } else {
                    LockLayout.selected = "";
                    LockLayout.openPicker(null);
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
            icon: bar.resetArmed ? "check" : "restart_alt"
            text: bar.resetArmed ? I18n.tr("Zurücksetzen?") : I18n.tr("Zurücksetzen")
            danger: true
            armed: bar.resetArmed
            dim: !LockLayout.custom && !bar.resetArmed
            onClicked: {
                if (bar.resetArmed) {
                    bar.resetArmed = false;
                    LockLayout.selected = "";
                    LockLayout.reset();
                } else if (LockLayout.custom) {
                    bar.resetArmed = true;
                    disarmReset.restart();
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
            icon: "close"
            text: I18n.tr("Abbrechen")
            onClicked: LockLayout.cancel()
        }

        EditChip {
            icon: "check"
            text: I18n.tr("Fertig")
            on: true
            onClicked: LockLayout.done()
        }
    }
}
