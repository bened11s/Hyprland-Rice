// System-Tray: ersetzt das KDE-Tray-Panel-Widget
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: root

    // ============================================================
    // VERZEICHNIS DER TRAY-ICONS (Rechteck mit Icon, Tooltip)
    // ============================================================

    component TrayEntry: Item {
        id: entry

        required property var modelData

        readonly property bool hasStatus: modelData.status !== undefined
        readonly property int status: hasStatus ? modelData.status : 0

        readonly property color fgColor: status === 1 ? "#c0caf5" : status === 2 ? "#565f89" : "#c0caf5"

        implicitWidth: 22
        implicitHeight: 22

        // Hover-Hintergrund
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 4
            color: hover.hovered ? "#1f2335" : "transparent"
        }

        IconImage {
            id: icon

            anchors.centerIn: parent
            width: 18
            height: 18

            implicitSize: 18
            asynchronous: true
            mipmap: true

            // Manche Tray-Items (z.B. PulseAudio) liefern Icons, die das
            // installierte Icon-Theme nicht kennt -> Fehler unterdruecken
            // und stattdessen das Titel-Fallback zeigen.
            onStatusChanged: {
                if (status === Image.Error)
                    icon.visible = false
            }

            source: entry.modelData.icon
        }

        // Fallback-Button, wenn das Icon fehlt (z.B. PulseAudio-Mikrofon)
        Rectangle {
            anchors.centerIn: parent
            width: 14
            height: 14
            radius: 3

            visible: !icon.visible && icon.status === Image.Error

            color: "transparent"
            border.width: 1
            border.color: entry.fgColor

            Text {
                anchors.centerIn: parent

                text: (entry.modelData.title !== undefined
                       && entry.modelData.title !== "")
                    ? entry.modelData.title.charAt(0).toUpperCase()
                    : "•"

                color: entry.fgColor
                font.pixelSize: 9
                font.family: "JetBrains Mono"
            }
        }

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            gesturePolicy: TapHandler.DragThreshold

            onTapped: function (eventPoint, button) {
                if (button === Qt.RightButton) {
                    if (entry.modelData.hasMenu)
                        entry.modelData.menu.open(
                            entry.parent ? entry.parent : entry,
                            entry.mapToGlobal(
                                entry.width / 2,
                                entry.height
                            )
                        )
                } else {
                    entry.modelData.activate(0, 0)
                }
            }
        }

        // Eigener Tooltip im Tokyo-Night-Stil (QtQuick.Controls waere zu generisch)
        Rectangle {
            id: tip

            readonly property string tipText: {
                let t = entry.modelData

                if (t.tooltipTitle !== undefined && t.tooltipTitle !== "")
                    return t.tooltipDescription !== undefined && t.tooltipDescription !== ""
                        ? t.tooltipTitle + "\n" + t.tooltipDescription
                        : t.tooltipTitle

                return t.title !== undefined ? t.title : ""
            }

            readonly property bool shouldShow: hover.hovered && tipText !== ""

            visible: shouldShow
            opacity: shouldShow ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }

            // Ueber dem Panel, aber an dessen oberen Rand geheftet.
            // parent: entry.Window.window ist null, solange kein Fenster
            // existiert -> deshalb ohne Reparatur des Parents auskommen.
            anchors.horizontalCenter: entry.horizontalCenter
            anchors.bottom: entry.bottom
            anchors.bottomMargin: entry.height + 4

            width: Math.min(320, tipLabel.implicitWidth + 16)
            height: tipLabel.implicitHeight + 10
            radius: 5

            color: "#16161e"
            border.width: 1
            border.color: "#3b4261"

            z: 100

            Text {
                id: tipLabel

                anchors.centerIn: parent

                text: tip.tipText
                color: "#c0caf5"

                font.pixelSize: 11
                font.family: "JetBrains Mono"
            }
        }
    }

    // ============================================================
    // TRAY-LEISTE
    // ============================================================

    RowLayout {
        anchors.fill: parent
        spacing: 1

        Repeater {
            model: SystemTray.items

            delegate: TrayEntry {}
        }
    }
}