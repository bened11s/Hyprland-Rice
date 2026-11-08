pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Kontextmenue der Tastenkürzel-Seite (Vorbild: launcher/clipboard/ClipMenu).
// Zeilen als [{ title, icon, danger?, confirm?, action }]; `confirm` fragt
// beim ersten Klick nach ("Wirklich löschen?") und fuehrt erst beim zweiten
// aus. Mit der Tastatur: Pfeile, Enter, Esc. Der Editor setzt x/y und `open`
// und schliesst bei Klick daneben (MouseArea im Overlay).
Rectangle {
    id: menu

    property bool open: false
    property var rows: []
    // Tastatur-Auswahl (-1 = keine), bewaffnete Bestaetigungszeile
    property int current: -1
    property int armed: -1

    signal closed

    readonly property real pad: 5

    visible: opacity > 0
    width: 230
    height: column.implicitHeight + menu.pad * 2
    radius: 12
    color: Colors.surfaceContainer
    border.width: 1
    border.color: Colors.outlineVariant

    opacity: menu.open ? 1 : 0
    scale: menu.open ? 1 : 0.96
    transformOrigin: Item.TopLeft

    Behavior on opacity {
        NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
    }

    onOpenChanged: {
        menu.current = -1;
        menu.armed = -1;
        if (menu.open)
            menu.forceActiveFocus();
    }

    function close(): void {
        if (!menu.open)
            return;
        menu.open = false;
        menu.closed();
    }

    function activate(i: int): void {
        const row = menu.rows[i];
        if (!row)
            return;
        if (row.confirm === true && menu.armed !== i) {
            menu.armed = i;
            menu.current = i;
            return;
        }
        menu.close();
        row.action();
    }

    function move(step: int): void {
        if (menu.rows.length === 0)
            return;
        menu.current = (menu.current + step + menu.rows.length) % menu.rows.length;
    }

    focus: menu.open
    Keys.onUpPressed: menu.move(-1)
    Keys.onDownPressed: menu.move(1)
    Keys.onReturnPressed: menu.activate(menu.current)
    Keys.onEnterPressed: menu.activate(menu.current)
    Keys.onEscapePressed: menu.close()
    Keys.onTabPressed: menu.move(1)
    Keys.onBacktabPressed: menu.move(-1)

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
                required property int index

                readonly property bool danger: row.modelData.danger === true
                readonly property bool isArmed: menu.armed === row.index
                readonly property bool highlighted: rowHover.hovered || menu.current === row.index

                width: parent.width
                height: 30
                radius: 8
                color: row.isArmed ? Colors.alpha(Colors.error, row.highlighted ? 0.22 : 0.14)
                     : row.highlighted ? Colors.alpha(row.danger ? Colors.error : Colors.fgSurface, 0.1)
                     : "transparent"

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
                    text: row.isArmed ? "warning" : (row.modelData.icon ?? "")
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
                    text: row.isArmed ? I18n.tr("Wirklich löschen?") : row.modelData.title
                    color: row.danger ? Colors.error : Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 12
                    font.weight: row.isArmed ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                HoverHandler {
                    id: rowHover

                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: if (hovered) menu.current = row.index
                }

                TapHandler {
                    onTapped: menu.activate(row.index)
                }
            }
        }
    }
}
