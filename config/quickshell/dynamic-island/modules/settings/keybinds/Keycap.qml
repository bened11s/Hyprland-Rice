import QtQuick

import qs
import qs.modules.services.config

// Eine Tastenkappe in einer Kombination ("Super", "Alt", "W") – wie in der
// Uebersicht der Notch, hier etwas groesser fuer die Einstellungen.
Rectangle {
    id: cap

    required property string text
    // Neu belegt / gerade aufgenommen
    property bool accent: false
    property bool dim: false
    property int size: 22

    width: Math.max(height, capText.implicitWidth + 12)
    height: cap.size
    radius: 6
    color: cap.accent ? Colors.alpha(Colors.primary, 0.16) : Colors.alpha(Colors.fgSurface, 0.07)
    border.width: 1
    border.color: cap.accent ? Colors.alpha(Colors.primary, 0.6) : Colors.alpha(Colors.outline, 0.45)
    opacity: cap.dim ? 0.45 : 1

    Text {
        id: capText

        anchors.centerIn: parent
        text: cap.text
        color: cap.text === "Super" || cap.accent ? Colors.primary : Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: Math.round(cap.size * 0.5)
        font.weight: Font.Medium
        font.strikeout: cap.dim
    }
}
