pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.core
import qs.modules.services.network

// WLAN-Symbol der eingeklappten Settings-Pille. Der Status kommt aus
// WifiStatus (ein Dienst fuer alle Anzeigen, ereignisgesteuert) – dieses
// Symbol pollte frueher selbst alle 3 s, und das in jeder Instanz.
Item {
    id: wrapper
    anchors.fill: parent   // füllt den Kreis aus Settings – sonst hängt alles an (0,0)

    DemandRequest {
        demand: WifiStatus.demand
        active: wrapper.visible
    }

    Text {
        id: signalStrength
        anchors.centerIn: parent

        color: !WifiStatus.radioOn ? Colors.error
             : WifiStatus.connecting ? Colors.primary : Colors.secondary
        text: WifiStatus.icon
        font.family: "Material Symbols Outlined"
        font.pointSize: 12

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }
}
