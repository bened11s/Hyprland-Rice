pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.vpn

import qs

// VPN-Icon unten im Settings-Kreis – reine Ansicht, der Zustand lebt im
// Vpn-Singleton (modules/services/vpn/Vpn.qml).
Text {
    id: vpnIcon

    anchors {
        horizontalCenter: parent.horizontalCenter
        bottom: parent.bottom
    }

    text: Vpn.connected ? "vpn_key" : "vpn_key_off"   // Ligaturen: exakt so schreiben
    color: Vpn.connected ? Colors.primary : Colors.error
    font.pixelSize: 8
    font.family: "Material Symbols Outlined"
}
