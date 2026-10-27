pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Ablage "Verfuegbar" unter dem Raster (Modus "Bearbeiten"): die Kacheln,
// die in keiner Reihe stehen (QuickLayout.hidden), als Chips.
//   Chip antippen   blendet die Kachel ein (eigene Reihe hinten)
//   Chip ziehen     legt sie an die gezogene Stelle (QuickEdit.place)
//   Kachel hierher  blendet sie aus – die Flaeche faerbt sich dann rot
Item {
    id: available

    required property QuickEdit edit

    readonly property bool isTarget: available.edit.hideTarget

    implicitHeight: heading.height + 6 + tray.height

    Text {
        id: heading

        font.family: Config.font
        text: I18n.tr("Verfügbar")
        color: Colors.fgSurfaceVariant
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    Rectangle {
        id: tray

        anchors {
            top: heading.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
        }
        height: Math.max(48, flow.implicitHeight + 12)
        radius: 18
        color: available.isTarget ? Colors.alpha(Colors.error, 0.12) : Colors.alpha(Colors.fgSurface, 0.04)
        border.width: 1
        border.color: available.isTarget ? Colors.alpha(Colors.error, 0.6) : Colors.alpha(Colors.outline, 0.22)

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }
        Behavior on height {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Flow {
            id: flow

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
            }
            spacing: 6

            Repeater {
                model: QuickLayout.hidden

                Rectangle {
                    id: chip

                    required property string modelData

                    readonly property var info: QuickLayout.tiles[chip.modelData] ?? ({})
                    readonly property bool lifted: available.edit.dragId === chip.modelData

                    width: chipLabel.implicitWidth + 50
                    height: 36
                    radius: 18
                    color: chipHover.hovered && !available.edit.dragging ? Colors.alpha(Colors.fgSurface, 0.16)
                                                                        : Colors.alpha(Colors.fgSurface, 0.09)
                    border.width: 1
                    border.color: Colors.alpha(Colors.outline, 0.3)
                    opacity: chip.lifted ? 0.3 : 1

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }

                    Text {
                        id: chipIcon

                        anchors {
                            left: parent.left
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: chip.info.icon ?? "help"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 17
                    }

                    Text {
                        id: chipLabel

                        font.family: Config.font
                        anchors {
                            left: chipIcon.right
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: chip.info.label ? I18n.tr(chip.info.label) : chip.modelData
                        color: Colors.fgSurface
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    HoverHandler {
                        id: chipHover

                        cursorShape: available.edit.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: QuickLayout.show(chip.modelData)
                    }

                    DragHandler {
                        id: drag

                        target: null
                        onActiveChanged: {
                            if (drag.active)
                                available.edit.beginDrag(chip.modelData);
                            else
                                available.edit.endDrag();
                        }
                        onCentroidChanged: {
                            if (drag.active)
                                available.edit.updateDrag(drag.centroid.scenePosition);
                        }
                    }
                }
            }
        }

        // Nichts ausgeblendet: nur ein Symbol, die Flaeche bleibt als Ziel
        Text {
            anchors.centerIn: parent
            visible: QuickLayout.hidden.length === 0
            text: available.isTarget ? "visibility_off" : "check_circle"
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.55)
            font.family: "Material Symbols Outlined"
            font.pixelSize: 18
        }
    }
}
