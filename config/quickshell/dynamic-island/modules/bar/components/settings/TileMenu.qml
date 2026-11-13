pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Aufklappliste einer Kachel (VPN-Anbieter, No-Sleep-Dauer, Energieprofil,
// Aufnahme). Optik wie SettingsMenu, aber ein gewoehnliches Item: das Menue
// haengt aus der Karte heraus, und Bar.qml nimmt es in die Eingabe-Maske –
// ein Controls-Popup bekaeme dort keine Klicks.
//
// entries: [{ text, icon?, current?, action }] bzw. { separator: true }
Rectangle {
    id: menu

    property var entries: []
    readonly property alias hovered: menuHover.hovered
    // Nach jeder Wahl – die Kachel klappt das Menue dann zu
    signal picked()

    width: 190
    height: column.implicitHeight + 10
    z: 200
    radius: 12
    color: Colors.shade(Colors.background, 0.08)
    border.width: 1
    border.color: Colors.outlineVariant

    // Eigene Trefferflaeche, damit Klicks nicht zu den Kacheln darunter fallen
    MouseArea {
        anchors.fill: parent
    }

    HoverHandler {
        id: menuHover
    }

    Column {
        id: column

        x: 5
        y: 5
        width: parent.width - 10

        Repeater {
            model: menu.entries

            Item {
                id: entry

                required property var modelData
                readonly property bool separator: entry.modelData.separator === true
                readonly property bool current: entry.modelData.current === true

                width: column.width
                height: entry.separator ? 9 : 32

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    height: 1
                    visible: entry.separator
                    color: Colors.alpha(Colors.outline, 0.3)
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !entry.separator
                    radius: 8
                    color: entryHover.hovered ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"
                }

                Text {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !entry.separator
                    text: entry.current ? "check" : (entry.modelData.icon ?? "")
                    color: entry.current ? Colors.primary : Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 16
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 40
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    visible: !entry.separator
                    text: entry.modelData.text ?? ""
                    color: entry.current ? Colors.primary : Colors.fgBackground
                    font.family: Config.font
                    font.pixelSize: 12
                    font.weight: entry.current ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                HoverHandler {
                    id: entryHover

                    enabled: !entry.separator
                }

                // MouseArea statt TapHandler: nimmt den Druck exklusiv, ein
                // TapHandler hier wurde von Handlern darunter abgebrochen
                MouseArea {
                    anchors.fill: parent
                    enabled: !entry.separator
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Erst zuklappen, dann handeln: die Aktion aendert meist
                        // `entries`, und der Repeater baut diesen Eintrag neu
                        const action = entry.modelData.action;
                        menu.picked();
                        if (action)
                            Qt.callLater(action);
                    }
                }
            }
        }
    }
}
