pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Modus "Layout": die Reihen aus QuickLayout.rows als Bloecke, die Kacheln
// darin nur als graue Platzhalter mit blassem Symbol (Skelett wie im
// Android-Editor), unten mittig ein Griff. Einen Block senkrecht ziehen
// sortiert die Reihen um (QuickLayout.moveRow); die anderen ruecken schon
// waehrend des Ziehens an ihren neuen Platz.
//
// Positionen sind von Hand gerechnet (kein Column), damit die Bloecke beim
// Ausweichen animieren koennen: alle gleich hoch, y = Platz * Schritt.
Item {
    id: blocks

    readonly property real blockHeight: 58
    readonly property real gap: 8
    readonly property real step: blocks.blockHeight + blocks.gap
    readonly property real pad: 8
    readonly property real cellGap: 6
    readonly property int count: QuickLayout.rows.length

    // Welcher Block wird gezogen, wie weit, und wo landet er
    property int dragIndex: -1
    property real dragOffset: 0
    readonly property int dropIndex: blocks.dragIndex < 0 ? -1
        : Math.max(0, Math.min(blocks.count - 1, Math.round((blocks.dragIndex * blocks.step + blocks.dragOffset) / blocks.step)))

    implicitHeight: blocks.count * blocks.blockHeight + Math.max(0, blocks.count - 1) * blocks.gap

    readonly property real unit: (blocks.width - blocks.pad * 2 - blocks.cellGap * (QuickLayout.columns - 1)) / QuickLayout.columns

    function cellWidth(span: int): real {
        return blocks.unit * span + blocks.cellGap * (span - 1);
    }

    Repeater {
        model: QuickLayout.rows

        Rectangle {
            id: block

            required property var modelData     // Array von { id, span }
            required property int index

            readonly property bool lifted: blocks.dragIndex === block.index
            // Zwischen Start und Ziel ruecken die anderen um einen Platz
            readonly property int shift: blocks.dragIndex < 0 || block.lifted ? 0
                : block.index > blocks.dragIndex && block.index <= blocks.dropIndex ? -1
                : block.index < blocks.dragIndex && block.index >= blocks.dropIndex ? 1
                : 0

            width: blocks.width
            height: blocks.blockHeight
            y: block.lifted ? block.index * blocks.step + blocks.dragOffset
                            : (block.index + block.shift) * blocks.step
            z: block.lifted ? 2 : 0
            radius: 16
            color: block.lifted ? Colors.alpha(Colors.fgSurface, 0.12) : Colors.alpha(Colors.fgSurface, 0.05)
            border.width: 1
            border.color: block.lifted ? Colors.alpha(Colors.primary, 0.6) : Colors.alpha(Colors.outline, 0.22)
            scale: block.lifted ? 1.02 : 1

            Behavior on y {
                enabled: !block.lifted
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 120 }
            }
            Behavior on border.color {
                ColorAnimation { duration: 120 }
            }
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            // Die Kacheln als Skelett
            Row {
                anchors {
                    left: parent.left
                    top: parent.top
                    margins: blocks.pad
                }
                spacing: blocks.cellGap

                Repeater {
                    model: block.modelData

                    Rectangle {
                        id: ghostTile

                        required property var modelData     // { id, span }

                        // Luecken ("_") bleiben leer, sie halten nur den Platz
                        readonly property bool isGap: ghostTile.modelData.id === QuickLayout.gap

                        width: blocks.cellWidth(ghostTile.modelData.span)
                        height: 30
                        radius: 15
                        color: ghostTile.isGap ? "transparent" : Colors.alpha(Colors.fgSurface, 0.1)

                        Text {
                            anchors.centerIn: parent
                            text: QuickLayout.tiles[ghostTile.modelData.id]?.icon ?? ""
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.45)
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                        }
                    }
                }
            }

            // Griff unten mittig
            Rectangle {
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 6
                    horizontalCenter: parent.horizontalCenter
                }
                width: 32
                height: 4
                radius: 2
                color: block.lifted || blockHover.hovered ? Colors.primary : Colors.alpha(Colors.fgSurfaceVariant, 0.5)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }
            }

            HoverHandler {
                id: blockHover

                cursorShape: blocks.dragIndex >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }

            DragHandler {
                id: drag

                target: null
                xAxis.enabled: false
                yAxis.enabled: true
                enabled: blocks.dragIndex < 0 || block.lifted

                onActiveChanged: {
                    if (drag.active) {
                        blocks.dragOffset = 0;
                        blocks.dragIndex = block.index;
                    } else {
                        const from = blocks.dragIndex;
                        const to = blocks.dropIndex;
                        blocks.dragIndex = -1;
                        blocks.dragOffset = 0;
                        if (from >= 0 && to >= 0 && from !== to)
                            QuickLayout.moveRow(from, to);
                    }
                }
                onTranslationChanged: {
                    if (drag.active)
                        blocks.dragOffset = drag.activeTranslation.y;
                }
            }
        }
    }
}
