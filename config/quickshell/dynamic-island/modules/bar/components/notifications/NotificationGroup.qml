pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services.notifications

import qs
import qs.modules.services.config

// Die Nachrichten einer App als Buendel.
//
// Bei genau einer Nachricht ist das einfach die Zeile selbst – ein Kopf mit
// "App · 1" darueber waere nur Ballast. Erst ab zwei bekommt die Gruppe einen
// Kopf mit App-Name, Anzahl und Aufklapp-Pfeil; eingeklappt steht darunter die
// neueste, aufgeklappt alle.
Item {
    id: group

    required property var modelData        // { app, entries } aus dem Dienst

    readonly property var entries: group.modelData?.entries ?? []
    readonly property int count: group.entries.length
    readonly property bool grouped: group.count > 1
    property bool expanded: false

    readonly property real headerHeight: 26
    readonly property real rowHeight: 52

    // Eingeklappt zeigt eine Gruppe nur die neueste Nachricht
    readonly property var shown: group.grouped && !group.expanded ? group.entries.slice(0, 1)
                                                                 : group.entries

    // Das App-Icon der Gruppe: das erste, das eine Nachricht mitbringt
    readonly property string appIcon: {
        for (const e of group.entries) {
            const name = e?.notif?.appIcon ?? "";
            if (name !== "")
                return Quickshell.iconPath(name, true);
        }
        return "";
    }

    implicitHeight: content.implicitHeight

    // Zuklappen, sobald nur noch eine Nachricht uebrig ist – sonst bliebe ein
    // Kopf ohne Inhalt stehen
    onCountChanged: if (!group.grouped)
        group.expanded = false

    Column {
        id: content

        width: parent.width
        spacing: 0

        // ---- Kopf ----
        Item {
            width: parent.width
            height: group.grouped ? group.headerHeight : 0
            visible: group.grouped

            Image {
                id: groupIcon

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                width: 14
                height: 14
                source: group.appIcon
                asynchronous: true
                sourceSize.width: 28
                sourceSize.height: 28
                visible: status === Image.Ready
            }

            Text {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                visible: groupIcon.status !== Image.Ready

                text: "apps"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 13
            }

            Text {
                font.family: Config.font
                anchors {
                    left: parent.left
                    leftMargin: 20
                    right: groupClose.left
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                text: `${group.modelData?.app ?? ""} · ${group.count}`
                color: Colors.fgSurfaceVariant
                font.pixelSize: 10
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // Ganze Gruppe wegraeumen
            Rectangle {
                id: groupClose

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 20
                height: 20
                radius: height / 2
                color: groupCloseArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.14) : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: "close"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 12
                }

                MouseArea {
                    id: groupCloseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.dismissGroup(group.modelData)
                }
            }

            Text {
                id: chevron

                anchors {
                    right: groupClose.left
                    rightMargin: 2
                    verticalCenter: parent.verticalCenter
                }
                text: group.expanded ? "expand_less" : "expand_more"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 14
            }

            // Klick auf den Kopf (ausser dem Kreuz) klappt auf und zu
            MouseArea {
                anchors {
                    left: parent.left
                    right: groupClose.left
                    top: parent.top
                    bottom: parent.bottom
                }
                cursorShape: Qt.PointingHandCursor
                onClicked: group.expanded = !group.expanded
            }
        }

        // ---- Nachrichten ----
        Repeater {
            model: group.shown

            NotificationRow {
                required property var modelData

                width: content.width
                entry: modelData
                swipeable: true
                // In einer Gruppe steht das Icon schon im Kopf
                showIcon: !group.grouped
                leftInset: group.grouped ? 12 : 0
            }
        }
    }
}
