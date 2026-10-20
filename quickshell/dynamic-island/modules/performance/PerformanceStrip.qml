pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.config
import qs

// Content only: the Dynamic Island supplies the surface, position and animation.
Item {
    id: root
    readonly property var entries: GamePerformance.entries()
    readonly property real textSize: Math.max(10, Math.min(24, Config.performance.fontSize))
    readonly property real gap: Config.performance.compact ? 10 : 18
    readonly property real titleWidth: Config.performance.compact ? 160 : 240
    implicitWidth: root.entries.reduce((total, entry) => total + Math.ceil(Math.min(
        (entry.accent ? boldMeasure : measure).advanceWidth(entry.label),
        entry.title ? root.titleWidth : 300)) + root.gap, 4 - root.gap)
    implicitHeight: values.implicitHeight
    clip: true
    readonly property real overflow: Math.max(0, values.implicitWidth - root.width)
    onOverflowChanged: if (root.overflow <= 0) values.x = 0

    // Keep one horizontal band beside the clock, even with every metric enabled.
    // Overflow scrolls automatically; no wheel/pointer handlers steal Island gestures.
    SequentialAnimation {
        running: root.visible && root.overflow > 0
        loops: Animation.Infinite
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: values
            property: "x"
            from: 0
            to: -root.overflow
            duration: Math.max(2500, root.overflow * 25)
        }
        PauseAnimation { duration: 1500 }
        NumberAnimation { target: values; property: "x"; to: 0; duration: 350 }
    }

    FontMetrics {
        id: measure
        font.family: Config.font
        font.pixelSize: root.textSize
        font.weight: Font.Medium
    }
    FontMetrics {
        id: boldMeasure
        font.family: Config.font
        font.pixelSize: root.textSize
        font.weight: Font.Bold
    }

    Row {
        id: values
        spacing: root.gap
        Repeater {
            model: root.entries
            Text {
                required property var modelData
                width: Math.min(implicitWidth, modelData.title ? root.titleWidth : 300)
                text: modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: modelData.accent ? Colors.primary : Colors.fgSurface
                font.family: Config.font
                font.pixelSize: root.textSize
                font.weight: modelData.accent ? Font.Bold : Font.Medium
            }
        }
    }
}
