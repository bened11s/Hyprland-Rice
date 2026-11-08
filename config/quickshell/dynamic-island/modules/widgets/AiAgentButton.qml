import QtQuick
import QtQuick.Controls
import Quickshell
import qs

Rectangle {
    id: root
    implicitWidth: 30
    implicitHeight: 26
    radius: 8
    color: hover.hovered ? Colors.alpha(Colors.primary, 0.22) : Colors.alpha(Colors.fgBackground, 0.07)
    Accessible.role: Accessible.Button
    Accessible.name: "KI-Agent öffnen"
    ToolTip.visible: hover.hovered
    ToolTip.delay: 500
    ToolTip.text: "KI-Agent öffnen · OpenCode / Claude Code"

    Text {
        anchors.centerIn: parent
        text: "smart_toy"
        font.family: "Material Symbols Outlined"
        font.pixelSize: 18
        color: hover.hovered ? Colors.primary : Colors.fgSurfaceVariant
    }
    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: Quickshell.execDetached([
            "bash", Quickshell.env("HOME") + "/.config/dynamic-island/scripts/open-ai-agent.sh"
        ])
    }
}
