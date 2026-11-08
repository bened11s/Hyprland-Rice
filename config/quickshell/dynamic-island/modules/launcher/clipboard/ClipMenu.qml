pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.widgets
import qs.modules.services.config

// Rechtsklick-Menue einer Zeile der Zwischenablage. Die Zeilen kommen als
// [{ title, icon, danger?, action }] – das Panel setzt x/y und `open`,
// ein Klick daneben schliesst (MouseArea im Panel).
Rectangle {
    id: menu

    property bool open: false
    property var rows: []

    readonly property real pad: 5

    visible: opacity > 0
    width: 180
    height: column.implicitHeight + menu.pad * 2
    radius: 12
    color: Colors.surfaceContainer
    border.width: 1
    border.color: Colors.outlineVariant

    // Kommt leicht herangewachsen
    opacity: menu.open ? 1 : 0
    scale: menu.open ? 1 : 0.96
    transformOrigin: Item.TopLeft

    Fade on opacity {}
    Behavior on scale {
        NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
    }

    // Klicks bleiben hier
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Column {
        id: column

        anchors {
            fill: parent
            margins: menu.pad
        }
        spacing: 1

        Repeater {
            model: menu.rows

            Rectangle {
                id: row

                required property var modelData

                readonly property bool danger: row.modelData.danger === true

                width: parent.width
                height: 30
                radius: 8
                color: rowHover.hovered ? Colors.alpha(row.danger ? Colors.error : Colors.fgSurface, 0.1) : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }

                Text {
                    id: rowIcon

                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: row.modelData.icon ?? ""
                    color: row.danger ? Colors.error : Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 15
                }

                Text {
                    anchors {
                        left: rowIcon.right
                        leftMargin: 8
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: row.modelData.title
                    color: row.danger ? Colors.error : Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                HoverHandler {
                    id: rowHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: row.modelData.action()
                }
            }
        }
    }
}
