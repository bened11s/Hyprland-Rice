pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Zeile unter dem Raster des Kachel-Editors: mittig die Pille mit den
// beiden Ansichten ("Bearbeiten" = Kacheln, "Layout" = Reihen).
Item {
    id: footer

    required property QuickEdit edit

    implicitHeight: 30

    // ---- Ansicht-Pille ----
    Rectangle {
        id: pill

        readonly property var modes: ["tiles", "layout"]
        readonly property var labels: [I18n.tr("Bearbeiten"), I18n.tr("Layout")]
        readonly property int current: Math.max(0, pill.modes.indexOf(footer.edit.mode))
        // Beide Segmente gleich breit (der laengere Text gibt vor)
        readonly property real segmentWidth: Math.max(label0.implicitWidth, label1.implicitWidth) + 30
        readonly property real inset: 3

        anchors.centerIn: parent
        width: pill.segmentWidth * 2 + pill.inset * 2
        height: 30
        radius: 15
        color: Colors.alpha(Colors.fgSurface, 0.08)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.25)
        // Die Markierung wandert unter das gewaehlte Segment
        Rectangle {
            x: pill.inset + pill.current * pill.segmentWidth
            y: pill.inset
            width: pill.segmentWidth
            height: pill.height - pill.inset * 2
            radius: height / 2
            color: Colors.primary

            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: label0

            x: pill.inset
            width: pill.segmentWidth
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            font.family: Config.font
            text: pill.labels[0]
            color: pill.current === 0 ? Colors.fgPrimary : Colors.fgSurface
            font.pixelSize: 12
            font.weight: Font.DemiBold

            Behavior on color {
                ColorAnimation { duration: 140 }
            }
        }

        Text {
            id: label1

            x: pill.inset + pill.segmentWidth
            width: pill.segmentWidth
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            font.family: Config.font
            text: pill.labels[1]
            color: pill.current === 1 ? Colors.fgPrimary : Colors.fgSurface
            font.pixelSize: 12
            font.weight: Font.DemiBold

            Behavior on color {
                ColorAnimation { duration: 140 }
            }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: pillTap

            onTapped: {
                const index = pillTap.point.position.x < pill.width / 2 ? 0 : 1;
                footer.edit.mode = pill.modes[index];
                footer.edit.selectedId = "";
            }
        }
    }
}
