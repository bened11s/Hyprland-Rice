import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config

// Kleine Beschriftung vor einer Chip-Reihe
Text {
    color: Colors.fgSurfaceVariant
    font.family: Config.font
    font.pixelSize: 10
    font.weight: Font.DemiBold
    Layout.alignment: Qt.AlignVCenter
}
