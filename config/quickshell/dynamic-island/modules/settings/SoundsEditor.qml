pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.sounds

// Block unter "Klänge > Eigene Klänge" (Config.meta editor "sounds"): je
// Klang eine Zeile zum Probehoeren, eine eigene Datei waehlen (oder aus dem
// Dateimanager auf die Zeile ziehen) und zurueck zum eingebauten.
// Umwandeln und Ablage macht Sounds/soundmgr.py.
Column {
    id: root

    spacing: 2
    bottomPadding: 8

    readonly property var entries: [
        { name: "message", title: "Neue Nachricht" },
        { name: "shutter", title: "Screenshot" },
        { name: "plug", title: "Ladekabel an" },
        { name: "unplug", title: "Ladekabel ab" },
        { name: "lock", title: "Sperren" },
        { name: "unlock", title: "Entsperren" },
        { name: "connect", title: "Bluetooth verbunden" },
        { name: "disconnect", title: "Bluetooth getrennt" }
    ]

    Repeater {
        model: root.entries

        Rectangle {
            id: row

            required property var modelData
            readonly property string name: row.modelData.name
            readonly property bool own: Sounds.isCustom(row.name)
            readonly property bool busy: Sounds.busyName === row.name

            width: root.width
            height: 38
            radius: 10
            color: drop.containsDrag ? Colors.alpha(Colors.primary, 0.14)
                 : rowHover.hovered ? Colors.alpha(Colors.fgSurface, 0.05) : "transparent"
            border.width: drop.containsDrag ? 1 : 0
            border.color: Colors.primary

            HoverHandler {
                id: rowHover
            }

            // Datei aus dem Dateimanager hierher ziehen
            DropArea {
                id: drop

                anchors.fill: parent
                keys: ["text/uri-list"]
                onDropped: d => {
                    if (d.hasUrls && d.urls.length > 0)
                        Sounds.importFile(row.name, d.urls[0].toString());
                }
            }

            // Abspielen
            Rectangle {
                id: playButton

                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                radius: 14
                color: playHover.hovered ? Colors.alpha(Colors.primary, 0.22) : Colors.alpha(Colors.primary, 0.12)

                Text {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    color: Colors.primary
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 17
                }

                HoverHandler {
                    id: playHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: Sounds.playNow(row.name)
                }
            }

            Text {
                anchors.left: playButton.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr(row.modelData.title)
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 11
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Eigene Datei: Kennzeichen + zuruecksetzen
                Rectangle {
                    visible: row.own && !row.busy
                    width: 28
                    height: 28
                    radius: 14
                    color: resetHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "restart_alt"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16
                    }

                    HoverHandler {
                        id: resetHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: Sounds.reset(row.name)
                    }
                }

                Rectangle {
                    width: fileLabel.implicitWidth + 24
                    height: 28
                    radius: 14
                    color: row.own ? Colors.alpha(Colors.primary, fileHover.hovered ? 0.28 : 0.18)
                                   : Colors.alpha(Colors.fgSurface, fileHover.hovered ? 0.1 : 0.06)

                    Text {
                        id: fileLabel

                        anchors.centerIn: parent
                        text: row.busy ? "…" : row.own ? I18n.tr("Eigener Klang") : I18n.tr("Datei wählen")
                        color: row.own ? Colors.primary : Colors.fgSurfaceVariant
                        font.family: Config.font
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    HoverHandler {
                        id: fileHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        enabled: Sounds.busyName === ""
                        onTapped: Sounds.choose(row.name)
                    }
                }
            }
        }
    }

    Text {
        visible: Sounds.lastError !== ""
        width: parent.width
        leftPadding: 4
        topPadding: 4
        text: Sounds.lastError
        color: Colors.error
        font.family: Config.font
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
}
