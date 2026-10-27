pragma ComponentBehavior: Bound
import QtQuick

import qs.modules.services.audio
import qs.modules.services.brightness
import qs.modules.services.config
import qs.modules.services.system
import qs.modules.services.vpn
import qs.modules.services.bluetooth

import qs
import qs.modules.widgets

// Settings-Knopf rechts neben der Notch. Bei Hover waechst er wie die Notch
// zu einer (noch leeren) Karte – nach RECHTS und UNTEN: oben links fix
// (x kommt aus Bar.qml linksseitig, y haengt oben am Leistenrand).
// Eingeklappt zeigen Wifi- und VPN-Icon, aufgeklappt ist die Karte leer.
// Optik (Verlauf, Rand, Schatten) kommt von Surface, die Kinder liegen in
// dessen Karte.
Surface {
    id: settings

    // Schnittstelle (Bar.qml setzt verticalMargin/cardRadius)
    required property real verticalMargin
    required property real cardRadius

    // Ein Klick oeffnet die Karte. Hover haelt eine geoeffnete Karte nur noch
    // offen; beim Verlassen greift weiterhin der kurze Schliess-Nachlauf.
    readonly property bool containsMouse: hoverSensor.hovered || tiles.sleepMenuHovered || tiles.vpnMenuHovered || tiles.powerMenuHovered
    property bool expanded: false
    // Eingebettet in das Steuerungs-Untermenue der Notch (ControlPanel): immer
    // aufgeklappt, ohne eigene Flaeche, kein Peek und kein Zuklappen – die
    // Notch ist Hintergrund und entscheidet, wann die Ansicht geht.
    property bool embedded: false
    property bool showBrightness: false
    // Hovern zieht die Pille seitlich auf und zeigt die Statuszeile
    property bool peek: false

    // Zweite Ansicht der Karte: die WLAN-Liste. Zu macht sie der Zurueck-Pfeil
    // oder – wie bei den Kacheln – die Maus, die weggeht. Nur waehrend ein
    // Passwort getippt wird, bleibt sie stehen; dann haengt auch die Tastatur
    // an der Leiste (siehe Bar.qml).
    property bool wifiOpen: false
    property bool bluetoothOpen: false
    property bool audioOpen: false
    readonly property bool typingPassword: wifiOpen && (wifi?.passwordSsid ?? "") !== ""
    readonly property bool typingPin: bluetoothOpen && (bluetooth?.pairingInputOpen ?? false)

    // Unterseiten: in der Pille erst beim Oeffnen gebaut (und nach dem
    // Ausblenden wieder weg). Eingebettet (Steuerungs-Untermenue) leben sie
    // mit, weil die Notch dort immer die groesste Ansicht reserviert –
    // das Untermenue selbst entsteht ohnehin erst beim Oeffnen.
    readonly property Item wifi: wifiLoader.item
    readonly property Item bluetooth: bluetoothLoader.item
    readonly property Item audio: audioLoader.item

    function closeWifi(): void {
        settings.wifiOpen = false;
    }

    onContainsMouseChanged: {
        if (settings.embedded)
            return;
        if (containsMouse) {
            closeTimer.stop();
            peekClose.stop();
            if (!expanded && !wifiOpen && !bluetoothOpen && !audioOpen)
                peekTimer.restart();
        } else {
            peekTimer.stop();
            peekClose.restart();
            if (expanded)
                closeTimer.restart();
        }
    }

    // Erst nach kurzem Verweilen aufziehen, damit blosses Vorbeifahren die
    // Pille nicht zucken laesst (dasselbe Timing wie bei der Notch)
    Timer {
        id: peekTimer

        interval: 180
        onTriggered: settings.peek = true
    }

    Timer {
        id: peekClose

        interval: 260
        onTriggered: settings.peek = false
    }

    // Masse: eingeklappt der gewohnte Kreis, ausgeklappt die Karte. Hoehe =
    // Kachelreihen + Raender (kein Kreis-Vorlauf mehr, die Tiles stehen oben).
    readonly property real collapsedSize: parent.height - verticalMargin
    readonly property real expandedWidth: 520
    readonly property real expandedHeight: 10 + (wifiOpen ? wifiLoader.implicitHeight
                                               : bluetoothOpen ? bluetoothLoader.implicitHeight
                                               : audioOpen ? audioLoader.implicitHeight
                                               : tiles.implicitHeight) + 10

    // Groesster Fall der WLAN-Ansicht – so viel muss sich das Bar-Fenster nach
    // unten reservieren (siehe Bar.qml), sonst schneidet es die Liste ab.
    readonly property real maxHeight: 10 + 36 + 6 + 268 + 26 + 10
    readonly property real maxDrop: Math.max(0, verticalMargin / 2 + maxHeight - parent.height)

    // Das No-Sleep-Dropdown haengt aus der Karte heraus; Bar.qml haengt es
    // in die Fenster-Maske, damit man die Eintraege klicken kann
    readonly property alias sleepMenu: tiles.sleepMenu
    readonly property alias vpnMenu: tiles.vpnMenu
    readonly property alias powerMenu: tiles.powerMenu
    // Platz, den ein offenes Dropdown UNTER der Karte braucht – die Notch
    // clippt ihren Inhalt, eingebettet muss die Ansicht dafuer wachsen. Nur
    // der Teil, der wirklich unten herausragt: liegt das Dropdown innerhalb
    // der Karte (der Normalfall), waechst nichts.
    readonly property real dropdownReserve: {
        const menu = tiles.sleepMenuOpen ? tiles.sleepMenu
                   : tiles.vpnMenuOpen ? tiles.vpnMenu
                   : tiles.powerMenuOpen ? tiles.powerMenu
                   : null;
        if (!menu || !menu.visible)
            return 0;
        // Abhaengigkeiten fuer die Neuberechnung: Groesse von Menue und Karte
        const bottom = menu.mapToItem(settings, 0, menu.height).y + 0 * settings.height;
        return Math.max(0, Math.ceil(bottom - settings.height + 8));
    }

    anchors {
        top: parent.top
        topMargin: verticalMargin / 2   // oben fix -> alles Wachstum geht nach unten
    }
    // Aufgeklappt die Karte, beim Hovern die Statuszeile, sonst der Kreis
    readonly property real peekWidth: status.implicitWidth + 12
    width: expanded || wifiOpen || bluetoothOpen || audioOpen ? expandedWidth
         : peek ? peekWidth
         : collapsedSize
    // Eingebettet (Steuerungs-Untermenue) immer gleich hoch: die groesste
    // Ansicht (Kacheln bzw. WLAN/BT/Audio). Unterseiten und Dropdowns lassen
    // die Notch so nicht springen.
    readonly property real embeddedHeight: 20 + Math.max(tiles.implicitHeight, wifiLoader.implicitHeight,
                                                        bluetoothLoader.implicitHeight, audioLoader.implicitHeight)
    height: settings.embedded ? settings.embeddedHeight
          : expanded || wifiOpen || bluetoothOpen || audioOpen ? expandedHeight : collapsedSize

    // Klappt die Karte zu, ist auch die WLAN-Ansicht und das Dauer-Menue vorbei
    onExpandedChanged: if (!expanded) {
        settings.wifiOpen = false;
        settings.bluetoothOpen = false;
        settings.audioOpen = false;
        tiles.sleepMenuOpen = false;
        tiles.vpnMenuOpen = false;
        tiles.powerMenuOpen = false;
    } else {
        settings.showBrightness = false;
        settings.peek = false;          // die Karte loest die Statuszeile ab
        brightnessDisplayTimer.stop();
    }

    // Eingeklappt greift die halbe Breite (Kreis), aufgeklappt cardRadius
    maxRadius: cardRadius
    clipContent: false   // muss offen sein: das Dropdown haengt unten raus
    // Eingebettet: keine eigene Karte, die Notch ist die Flaeche
    baseColor: settings.embedded ? "transparent" : Colors.background
    lift: settings.embedded ? 0 : Appearance.lift
    shadow: !settings.embedded && Appearance.shadow && !settings.nested

    Morph on width {}
    Morph on height {}

    // Lautstaerke-Ring um den Kreis – reine ANZEIGE (Scrollen/Klicken ist
    // raus, das Volumen regelt man woanders). Blendet beim Aufklappen mit
    // den Icons aus, damit die Karte leer wirkt.
    Audioslider {
        anchors.fill: parent
        arcWidth: 2
        arcGap: 3
        startAngle: 130
        sweepAngle: 280

        opacity: settings.expanded || settings.showBrightness ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Audioslider {
        anchors.fill: parent
        arcWidth: 2
        arcGap: 3
        startAngle: 130
        sweepAngle: 280
        value: Brightness.value
        muted: false
        activeColor: Brightness.value > 0.5
                     ? Colors.fgSurfaceVariant
                     : Colors.alpha(Colors.fgSurfaceVariant, 0.45)

        opacity: !settings.expanded && settings.showBrightness ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    // Statuszeile: eingeklappt steht hier nur das WLAN-Symbol – und zwar
    // genau dort, wo es vorher mittig im Kreis sass, weil das erste Feld so
    // breit ist wie der Kreis. Beim Hovern kommen die anderen dazu und
    // schieben die Pille auf.
    Row {
        id: status

        anchors {
            left: parent.left
            top: parent.top
        }
        height: settings.collapsedSize
        spacing: 2
        opacity: settings.expanded ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        component StatusIcon: Text {
            id: icon

            property bool active: false
            property bool shown: true

            anchors.verticalCenter: parent?.verticalCenter ?? undefined
            width: settings.peek && icon.shown ? implicitWidth + 6 : 0
            visible: width > 0
            opacity: settings.peek && icon.shown ? 1 : 0
            horizontalAlignment: Text.AlignHCenter

            color: icon.active ? Colors.secondary : Colors.alpha(Colors.fgSurfaceVariant, 0.6)
            font.family: "Material Symbols Outlined"
            font.pixelSize: 15

            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }
        }

        // WLAN – das einzige, was immer zu sehen ist
        Item {
            width: settings.collapsedSize
            height: settings.collapsedSize

            Wifi {}
        }

        StatusIcon {
            text: BluetoothService.primaryDevice ? "bluetooth_connected"
                : tiles.btOn ? "bluetooth" : "bluetooth_disabled"
            active: tiles.btOn
        }

        // Verbundenes BT-Geraet: Name (samt Akku-Prozent aus `summary`) und
        // Akkusymbol direkt hinter dem Bluetooth-Zeichen. Ohne Verbindung ist
        // die Gruppe null breit und damit ganz weg – wie der Akku unten.
        Row {
            id: btSummary

            readonly property bool shown: settings.peek && BluetoothService.summary !== ""
            readonly property int battery: BluetoothService.batteryLevel(BluetoothService.primaryDevice)

            anchors.verticalCenter: parent.verticalCenter
            width: btSummary.shown ? implicitWidth + 6 : 0
            visible: width > 0
            opacity: btSummary.shown ? 1 : 0
            spacing: 3
            clip: true

            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }

            Text {
                font.family: Config.font
                anchors.verticalCenter: parent.verticalCenter

                width: Math.min(implicitWidth, 150)
                text: BluetoothService.summary
                color: Colors.fgBackground
                font.pixelSize: 11
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                visible: btSummary.battery >= 0
                text: BluetoothService.batteryIcon(btSummary.battery)
                color: btSummary.battery <= 10 ? Colors.error : Colors.secondary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15
            }
        }

        StatusIcon {
            text: Vpn.connected ? "vpn_key" : "vpn_key_off"
            active: Vpn.connected
        }

        // Die beiden nur, wenn sie wirklich laufen
        StatusIcon {
            text: "coffee"
            active: true
            shown: tiles.noSleep
        }

        StatusIcon {
            text: "sports_esports"
            active: true
            shown: tiles.gameMode
        }

        // Akku zum Schluss – Symbol samt Prozentzahl, deshalb kein StatusIcon
        // (das ist ein reines Symbol). Gibt es keinen Akku, ist die Gruppe
        // null breit und damit ganz weg.
        Row {
            id: battery

            readonly property bool shown: settings.peek && Power.hasBattery && Config.bar.battery
            readonly property bool low: Power.percent <= 20 && !Power.charging

            anchors.verticalCenter: parent.verticalCenter
            width: battery.shown ? implicitWidth + 6 : 0
            visible: width > 0
            opacity: battery.shown ? 1 : 0
            spacing: 3
            clip: true

            Behavior on width {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 160 }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                // Ohne Systemakku steckt der Akku in einem Geraet – dann sagt
                // das Maus- bzw. Tastatursymbol mehr als ein Akku-Symbol
                text: Power.hasSystemBattery ? Power.batteryIcon : Power.deviceIcon(Power.shown)
                color: battery.low ? Colors.error : Colors.secondary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15
            }

            Text {
                font.family: Config.font
                anchors.verticalCenter: parent.verticalCenter

                text: `${Power.percent} %`
                color: battery.low ? Colors.error : Colors.fgBackground
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }

    // VPN-Status unten im Kreis – in der Statuszeile steht er schon
    VpnIcon {
        opacity: settings.expanded || settings.showBrightness || settings.peek ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Text {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
        }
        text: "brightness_6"
        color: Brightness.value > 0.5
               ? Colors.fgSurfaceVariant
               : Colors.alpha(Colors.fgSurfaceVariant, 0.45)
        font.pixelSize: 8
        font.family: "Material Symbols Outlined"
        opacity: !settings.expanded && settings.showBrightness ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    // Der Kachel-Inhalt der ausgeklappten Karte (Wi-Fi, Bluetooth, VPN,
    // No-Sleep + Game-/DND-Kreise), fuellt die Karte komplett – oben beginnt
    // direkt die erste Reihe, kein Whitespace.
    SettingsTiles {
        id: tiles

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
        }
        opacity: settings.expanded && !settings.wifiOpen && !settings.bluetoothOpen && !settings.audioOpen ? 1 : 0
        visible: opacity > 0

        onOpenWifi: {
            settings.bluetoothOpen = false;
            settings.audioOpen = false;
            settings.wifiOpen = true;
        }
        onOpenBluetooth: {
            settings.wifiOpen = false;
            settings.audioOpen = false;
            settings.bluetoothOpen = true;
        }
        onOpenAudio: {
            settings.wifiOpen = false;
            settings.bluetoothOpen = false;
            settings.audioOpen = true;
        }

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        id: wifiLoader

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
        }
        active: settings.embedded || settings.wifiOpen || opacity > 0
        opacity: settings.wifiOpen ? 1 : 0
        visible: opacity > 0

        sourceComponent: WifiPanel {
            active: settings.wifiOpen

            onClosed: settings.wifiOpen = false
        }

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        id: bluetoothLoader

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
        }
        active: settings.embedded || settings.bluetoothOpen || opacity > 0
        opacity: settings.bluetoothOpen ? 1 : 0
        visible: opacity > 0

        sourceComponent: BluetoothPanel {
            active: settings.bluetoothOpen

            onClosed: settings.bluetoothOpen = false
        }

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Loader {
        id: audioLoader

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
        }
        active: settings.embedded || settings.audioOpen || opacity > 0
        opacity: settings.audioOpen ? 1 : 0
        visible: opacity > 0

        sourceComponent: AudioPanel {
            active: settings.audioOpen

            onClosed: settings.audioOpen = false
        }

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Timer {
        id: closeTimer

        interval: 700
        // Waehrend eines Passworts darf die Maus rausrutschen
        onTriggered: if (!settings.embedded && !settings.typingPassword && !settings.typingPin && !BluetoothService.pairingActive)
            settings.expanded = false
    }

    Timer {
        id: brightnessDisplayTimer

        interval: 3000
        onTriggered: settings.showBrightness = false
    }

    Connections {
        target: Brightness

        function onValueChanged(): void {
            if (Brightness.ready && !settings.expanded && !settings.wifiOpen
                    && !settings.bluetoothOpen && !settings.audioOpen) {
                settings.showBrightness = true;
                brightnessDisplayTimer.restart();
            }
        }
    }

    TapHandler {
        enabled: !settings.expanded && !settings.wifiOpen && !settings.bluetoothOpen && !settings.audioOpen
        onTapped: settings.expanded = true
    }

    WheelHandler {
        enabled: !settings.expanded && !settings.wifiOpen && !settings.bluetoothOpen && !settings.audioOpen
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property real acc: 0

        onWheel: event => {
            acc += event.angleDelta.y;
            if (Math.abs(acc) >= 120) {
                Audio.setVolume(Audio.volume + (acc > 0 ? 0.05 : -0.05));
                acc = 0;
            }
            event.accepted = true;
        }
    }

    // Reiner Hover-Sensor, zuletztdeklariert (Muster siehe Notch.qml)
    HoverHandler {
        id: hoverSensor
    }
}
