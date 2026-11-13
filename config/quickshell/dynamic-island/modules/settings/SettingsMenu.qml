pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.modules.services.config

import qs

// Aufklappliste fuer das Einstellungs-Fenster (SettingsDropdown, SettingsMenuButton).
// Ein Controls-Popup: liegt in der Overlay-Ebene des Fensters, wird also von
// keinem Flickable/clip abgeschnitten, und schliesst bei Klick daneben/Escape.
//
// entries: [{ text, icon?, current?, danger?, enabled?, font?, action }]
// Ein Eintrag { separator: true } zeichnet eine Trennlinie.
Popup {
    id: menu

    property var entries: []
    // Mindestbreite (Dropdown: so breit wie sein Knopf)
    property real minWidth: 160
    readonly property bool hasIcons: menu.entries.some(e => (e.icon ?? "") !== "" || e.current !== undefined)

    padding: 5
    margins: 8
    width: Math.min(360, Math.max(menu.minWidth, sizer.implicitWidth + menu.padding * 2))
    height: Math.min(contentList.contentHeight + menu.padding * 2, 380)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    modal: false
    focus: true

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110 }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 90 }
    }

    background: Rectangle {
        radius: 12
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.outlineVariant
    }

    // Misst den breitesten Eintrag
    Column {
        id: sizer

        visible: false

        Repeater {
            model: menu.entries

            Text {
                required property var modelData

                leftPadding: menu.hasIcons ? 40 : 12
                rightPadding: 16
                text: modelData.text ?? ""
                font.family: modelData.font ?? Config.font
                font.pixelSize: 12
            }
        }
    }

    contentItem: ListView {
        id: contentList

        implicitHeight: contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: menu.entries

        delegate: Item {
            id: entry

            required property var modelData
            readonly property bool separator: entry.modelData.separator === true
            readonly property bool usable: !entry.separator && entry.modelData.enabled !== false

            width: ListView.view.width
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
                color: entryHover.hovered && entry.usable ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"
            }

            Text {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !entry.separator && menu.hasIcons
                text: entry.modelData.current === true ? "check" : (entry.modelData.icon ?? "")
                color: entry.modelData.danger ? Colors.error : entry.modelData.current ? Colors.primary : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: menu.hasIcons ? 40 : 12
                    right: parent.right
                    rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                visible: !entry.separator
                text: entry.modelData.text ?? ""
                color: entry.modelData.danger ? Colors.error : entry.modelData.current ? Colors.primary : Colors.fgSurface
                opacity: entry.usable ? 1 : 0.4
                font.family: entry.modelData.font ?? Config.font
                font.pixelSize: 12
                font.weight: entry.modelData.current ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            HoverHandler {
                id: entryHover

                cursorShape: entry.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            TapHandler {
                enabled: entry.usable
                onTapped: {
                    menu.close();
                    entry.modelData.action?.();
                }
            }
        }
    }
}
