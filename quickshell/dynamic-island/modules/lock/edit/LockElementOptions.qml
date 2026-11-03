pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.desktop
import qs.modules.lock
import qs.modules.services.config

// Optionen von Uhr und Medien-Karte im Anordnungs-Editor, angedockt an den
// Auswahlrahmen wie WidgetOptions bei den Widgets: Ein-/Ausblenden und Groesse.
Rectangle {
    id: pop

    required property string name
    property string title: ""
    property string icon: "widgets"

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

    implicitWidth: Math.max(260, rows.implicitWidth + 28)
    implicitHeight: rows.implicitHeight + 24
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

    ColumnLayout {
        id: rows

        x: 14
        y: 12
        spacing: 8

        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: pop.icon
                color: Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 18
            }

            Text {
                text: pop.title
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            EditChip {
                icon: pop.hiddenHere ? "visibility_off" : "visibility"
                text: pop.hiddenHere ? I18n.tr("Ausgeblendet") : I18n.tr("Sichtbar")
                on: !pop.hiddenHere
                onClicked: LockLayout.setHidden(pop.name, !pop.hiddenHere)
            }
        }

        RowLayout {
            spacing: 6
            opacity: pop.hiddenHere ? 0.4 : 1

            EditLabel {
                text: I18n.tr("Größe")
                Layout.preferredWidth: 60
            }

            EditChip {
                icon: "remove"
                onClicked: pop.setSize(pop.size / 1.1)
            }

            EditChip {
                text: Math.round(pop.size * 100) + " %"
                on: Math.abs(pop.size - 1) < 0.005
                onClicked: pop.setSize(1)
            }

            EditChip {
                icon: "add"
                onClicked: pop.setSize(pop.size * 1.1)
            }
        }
    }
}
