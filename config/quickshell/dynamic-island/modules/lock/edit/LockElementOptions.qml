pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.desktop
import qs.modules.lock
import qs.modules.services.config
import qs.modules.settings

// Optionen von Uhr und Medien-Karte im Anordnungs-Editor, angedockt an den
// Auswahlrahmen und gebaut wie WidgetOptions bei den Widgets
// (docs/settings-style.md): Kopf mit dem Namen, darunter Zeilen mit je einem
// Bedienelement (EditRow) – Sichtbar als Schalter, Groesse.
Rectangle {
    id: pop

    required property string name
    property string title: ""

    readonly property bool hiddenHere: LockLayout.hidden(pop.name)
    readonly property real size: LockLayout.scale(pop.name)
    readonly property bool hovered: popHover.hovered

    function setSize(value: real): void {
        const e = LockLayout.entry(pop.name);
        LockLayout.set(pop.name, {
            x: e?.x,
            y: e?.y,
            size: value
        });
    }

    implicitWidth: 320
    implicitHeight: body.implicitHeight + 10
    width: implicitWidth
    height: implicitHeight
    radius: 14
    color: Colors.alpha(Colors.background, 0.96)
    border.width: 2
    border.color: Colors.primary

    HoverHandler {
        id: popHover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Column {
        id: body

        x: 16
        y: 4
        width: pop.width - 32

        Item {
            width: parent.width
            height: 46

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: pop.title
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        EditRow {
            label: I18n.tr("Sichtbar")

            SettingsSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: !pop.hiddenHere
                onToggled: LockLayout.setHidden(pop.name, !pop.hiddenHere)
            }
        }

        // auch: Griff an der Ecke, Tasten + / -
        EditRow {
            label: I18n.tr("Größe")

            EditButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "remove"
                onClicked: pop.setSize(pop.size / 1.1)
            }

            // Klick auf den Wert: zurueck auf 100 %
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 50
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(pop.size * 100) + " %"
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 12

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: pop.setSize(1)
                }
            }

            EditButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "add"
                onClicked: pop.setSize(pop.size * 1.1)
            }
        }
    }
}
