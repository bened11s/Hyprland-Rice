pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.SystemTray

import qs
import qs.modules.bar.components.settings
import qs.modules.bar.components.statusBar
import qs.modules.services.network

// Untermenue "Steuerung" der Notch: Tray-Icons und die Schnell-Kacheln der
// Settings-Karte (WLAN, Bluetooth, VPN, Audio-Geraete, Helligkeit ...).
// Beides sind eigene, eingebettete Instanzen (`embedded: true`) – die Pillen
// der Leiste bleiben fuer das Insel-Layout unangetastet.
// Aufruf: SUPER+A, `>steuerung`, Blaettern.
ViewPanel {
    id: root

    // Fuer Bar.qml: Tastaturfokus beim WLAN-Passwort/BT-PIN, Pairing-Anfragen
    readonly property alias settings: embeddedSettings
    readonly property bool typing: embeddedSettings.typingPassword || embeddedSettings.typingPin
    readonly property bool hasTray: SystemTray.items.values.length > 0
    // Tray-Kacheln plus Abstand zu den Schnelleinstellungen
    readonly property real trayHeight: root.hasTray ? trayGrid.implicitHeight + 10 : 0

    title: I18n.tr("Steuerung")
    icon: "toggle_on"
    contentWidth: embeddedSettings.expandedWidth
    contentHeight: root.trayHeight + embeddedSettings.height + embeddedSettings.dropdownReserve
    maxContentHeight: root.trayHeight + embeddedSettings.maxHeight

    // Unterseiten zuruecksetzen, wenn die Ansicht geht. Beim Oeffnen schon
    // mal die WLAN-Liste aus dem Cache holen (~60 ms, nur wenn aelter als
    // 15 s) – klappt man die WLAN-Seite auf, steht sie dann sofort da.
    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: if (root.active) Qt.callLater(root.activeChanged)

    onActiveChanged: if (active) {
        Network.refreshIfStale(15000);
    } else {
        embeddedSettings.wifiOpen = false;
        embeddedSettings.bluetoothOpen = false;
        embeddedSettings.audioOpen = false;
    }

    // Tray als Kachel-Reihe (Name + Symbol, Rechtsklick = Menue)
    TrayGrid {
        id: trayGrid

        x: 10
        width: parent.width - 20
        visible: root.hasTray
    }

    Item {
        y: root.trayHeight
        width: parent.width
        height: embeddedSettings.height

        Settings {
            id: embeddedSettings

            embedded: true
            expanded: true
            verticalMargin: 0
            cardRadius: root.cardRadius
            borderWidth: 0
        }
    }
}
