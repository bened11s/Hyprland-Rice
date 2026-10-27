pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower

import qs.modules.services.audio
import qs.modules.services.bluetooth
import qs.modules.services.brightness
import qs.modules.services.core
import qs.modules.services.network
import qs.modules.services.plugins
import qs.modules.services.record
import qs.modules.services.system
import qs.modules.services.vpn

import qs.modules.settings
import qs.modules.bar.components.settings.edit

import qs
import qs.modules.services.config

// Kacheln fuer das aufgeklappte Settings-Feld (Vorlage: Control-Center).
//
// WELCHE Kacheln in WELCHER Reihe stehen, sagt QuickLayout.rows (aus
// Config.quick.rows, im Einstellungs-Menue per Drag and Drop zusammen-
// gestellt). Jede Kachel ist hier eine Component; ein Loader je Platz baut
// sie nach der Reihenfolge auf. Pillen teilen sich die Reihe, Kreise sind
// 54 px, breite Kacheln (Aufnahme, Regler) stehen allein.
//
// Die No-Sleep-Pille traegt einen Dauer-Dropdown (Standard: nichts gewaehlt
// = unbegrenzt); das Menue haengt aus der Karte heraus, Bar.qml haelt es in
// der Eingabe-Maske offen und Settings zaehlt seinen Hover zur Karte dazu.
//
// Hintergruenge zu den Aktionen:
//   - WLAN/Bluetooth: WifiStatus (nmcli monitor) bzw. BluetoothService
//   - VPN: der Vpn-Service mit NordVPN oder Cloudflare WARP
//   - No-Sleep/Game-Mode: SessionModes (systemd-inhibit bzw. hyprctl eval)
//   - DND: laeuft hier kein Notification-Daemon (mako/dunst/hypridle: nein),
//     ist der Kippschalter vorerst rein visuell
ColumnLayout {
    id: root

    spacing: 10

    // Raster: `unit` ist eine Spalte breit, eine Kachel belegt `span` davon
    // (plus die Luecken dazwischen). Reihen mit weniger belegten Spalten
    // bleiben rechts frei – so sieht man im Editor, wo noch Platz ist.
    readonly property real gridSpacing: 10
    readonly property real unit: (root.width - root.framePad * 2 - root.gridSpacing * (QuickLayout.columns - 1)) / QuickLayout.columns

    function cellWidth(span: int): real {
        return root.unit * span + root.gridSpacing * (span - 1);
    }

    // Breite des Eintrags `i` einer Reihe, wie sie gerade zu sehen ist: beim
    // Ziehen am Griff die Vorschau, und eine Luecke direkt dahinter schrumpft
    // um das, was die Kachel waechst (wie QuickLayout.resize)
    function shownSpan(entries: var, i: int): int {
        const e = entries[i];
        if (!e)
            return 0;
        const prev = entries[i - 1];
        if (e.id === QuickLayout.gap && prev && prev.id === root.edit.resizeId) {
            const grow = root.edit.resizeSpan - prev.span;
            return grow > 0 ? Math.max(0, e.span - grow) : e.span;
        }
        return root.edit.previewSpan(e.id, e.span);
    }

    // ---------- Kachel-Editor (nur im Einstellungs-Menue) ----------
    // Vorbild Android 16 "Kacheln bearbeiten": Kacheln werden an Ort und
    // Stelle gewaehlt, gezogen und in der Breite geaendert, im Modus "Layout"
    // die Reihen als Bloecke verschoben. Zustand und Trefferrechnung:
    // QuickEdit (edit/). Nur QuickTilesEditor setzt `editable` – dann ist der
    // Modus immer an; Steuerung und Settings-Pille bleiben unveraendert.
    property bool editable: false
    readonly property QuickEdit edit: QuickEdit {
        editable: root.editable
        frame: frame
        grid: grid
        rows: rowsRepeater
        tray: available.item
        rowGap: root.spacing
        slotGap: root.gridSpacing
    }
    // Im Bearbeitungsmodus bekommt das Raster einen Rahmen mit Polster
    property real framePad: root.edit.editing ? 10 : 0

    Behavior on framePad {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    // Offene Dropdowns schliessen, sobald bearbeitet wird – die Kacheln
    // sind dann stumm, ein haengendes Menue waere verwirrend
    Connections {
        target: root.edit

        function onEditingChanged(): void {
            if (!root.edit.editing)
                return;
            root.sleepMenuOpen = false;
            root.vpnMenuOpen = false;
            root.powerMenuOpen = false;
        }
    }

    // Der Pfeil auf der Wi-Fi-Pille fuehrt in die Netzliste; die Karte
    // (Settings.qml) schaltet daraufhin ihre Ansicht um.
    signal openWifi()
    signal openBluetooth()
    signal openAudio()

    // ---------- Zustaende ----------
    // WLAN-Status, No-Sleep und Game-Mode liegen in Singletons – diese
    // Kacheln gibt es je Monitor und Einbauort (Pille + Steuerung), alle
    // sollen dasselbe zeigen und nicht je eigene Poller/Inhibitoren starten.
    readonly property bool wifiOn: WifiStatus.radioOn
    readonly property string wifiStatus: !WifiStatus.loaded ? "…"
        : !WifiStatus.radioOn ? I18n.tr("Aus")
        : WifiStatus.connecting ? (WifiStatus.connectingSsid !== ""
                                   ? I18n.tr("Verbinde mit %1…").arg(WifiStatus.connectingSsid) : I18n.tr("Verbinde…"))
        : !WifiStatus.connected ? I18n.tr("Getrennt")
        : WifiStatus.ssid + " · " + WifiStatus.signal + "%"

    readonly property bool btOn: BluetoothService.enabled

    readonly property bool gameMode: SessionModes.gameMode
    readonly property bool noSleep: SessionModes.noSleep

    // Gewaehlte Dauer in Sekunden; -1 = nichts gewaehlt (Standard),
    // 0 = unbegrenzt. sleepRemaining ist die Restlaufzeit in Sekunden.
    readonly property int sleepDurationSec: SessionModes.sleepDurationSec
    readonly property int sleepRemaining: SessionModes.sleepRemaining

    // Dropdown-Zustand der No-Sleep-Pille (das Menue haengt aus der Karte
    // heraus und wird ueber Settings/Bar in die Eingabe-Maske gehaengt)
    // Die Menue-Panels leben in den Kachel-Components; die Kacheln melden sie
    // beim Aufbau hier an (null, solange die Kachel ausgeblendet ist).
    property bool sleepMenuOpen: false
    property Item sleepMenu: null
    // Maus ueber dem herausragenden Menue – Settings muss das kennen, sonst
    // klappt die Karte unter der Maus zu, sobald man ins Menue faehrt
    property bool sleepMenuHovered: false

    property bool vpnMenuOpen: false
    property Item vpnMenu: null
    property bool vpnMenuHovered: false

    property bool powerMenuOpen: false
    property Item powerMenu: null
    property bool powerMenuHovered: false

    // Kachel-ID -> Component (siehe QuickLayout.tiles fuer die IDs)
    readonly property var tileComponents: ({
        "wifi": wifiComponent,
        "bluetooth": bluetoothComponent,
        "vpn": vpnComponent,
        "nosleep": noSleepComponent,
        "gamemode": gameModeComponent,
        "airplane": airplaneComponent,
        "settings": settingsComponent,
        "record": recordComponent,
        "volume": volumeComponent,
        "mic": micComponent,
        "power": powerComponent,
        "brightness": brightnessComponent
    })

    // Status nur lesen lassen, solange die Kacheln zu sehen sind
    DemandRequest {
        demand: WifiStatus.demand
        active: root.visible
    }
    DemandRequest {
        demand: Brightness.demand
        active: root.visible
    }
    DemandRequest {
        demand: Vpn.demand
        active: root.visible
    }
    DemandRequest {
        demand: Airplane.demand
        active: root.visible
    }

    // ---------- Aktionen ----------
    function toggleWifi(): void {
        WifiStatus.setRadio(!root.wifiOn);
    }

    function toggleBt(): void {
        BluetoothService.setEnabled(!root.btOn);
    }

    function toggleNoSleep(): void {
        SessionModes.toggleNoSleep();
    }

    function pickDuration(sec: int): void {
        root.sleepMenuOpen = false;
        SessionModes.pickDuration(sec);
    }

    function durationLabel(sec: int): string {
        if (sec === 1800)
            return "30m";
        if (sec === 3600)
            return "1h";
        if (sec === 14400)
            return "4h";
        if (sec === 0)
            return "∞";
        return "–";
    }

    function toggleGameMode(): void {
        SessionModes.toggleGameMode();
    }

    function fmtRemaining(sec: int): string {
        if (sec >= 3600) {
            const h = Math.floor(sec / 3600);
            const m = Math.round((sec % 3600) / 60);
            return m > 0 ? h + " h " + m + " min" : h + " h";
        }
        return Math.max(1, Math.round(sec / 60)) + " min";
    }

    // ---------- Kacheln ----------
    component Tile: Rectangle {
        id: tile

        property string icon
        property string title
        property string subtitle
        property bool active

        // Farbe des aktiven Zustands. Standard ist die Themenfarbe; die
        // Aufnahme-Kachel setzt hier das feste Rot aus Colors.qml.
        property color accent: Colors.primary
        property color onAccent: Colors.fgPrimary

        // false = die Kachel togglet nicht selbst (No-Sleep hat einen
        // eigenen Guard, damit Dropdown-Klicks nicht doppelt ausloesen)
        property bool tapEnabled: true
        signal toggled()

        // Schmale Zelle (eine Rasterspalte): nur das Symbol, mittig; Texte,
        // Pfeile und Zusatzknoepfe sind dann weg – wie im Android-Tray
        readonly property bool compact: width < 150

        // Android-Tray: aktiv = die ganze Kachel in der Akzentfarbe, inaktiv
        // = neutrale Flaeche. Alles darauf (Texte, Pfeile, Knoepfe) nimmt die
        // passende Vordergrundfarbe – die Zusatzknoepfe holen sie sich hier.
        readonly property color fg: tile.active ? tile.onAccent : Colors.fgBackground
        readonly property color fgDim: tile.active ? Colors.alpha(tile.onAccent, 0.78) : Colors.fgSurfaceVariant
        readonly property color controlColor: tile.active ? Colors.alpha(tile.onAccent, 0.18) : Colors.alpha(Colors.fgSurface, 0.1)
        readonly property color controlHover: tile.active ? Colors.alpha(tile.onAccent, 0.3) : Colors.alpha(Colors.fgSurface, 0.18)

        implicitHeight: 54
        radius: height / 2
        color: tile.active ? tile.accent : Colors.alpha(Colors.fgSurface, 0.08)

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        // Hover-Schleier
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Colors.alpha(tile.fg, tileHover.hovered ? 0.06 : 0)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: tile.compact ? (tile.width - 28) / 2 : 16
            spacing: 12

            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28

                Text {
                    anchors.centerIn: parent

                    text: tile.icon
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 22
                    color: tile.active ? tile.onAccent : Colors.fgSurfaceVariant

                    Behavior on color {
                        ColorAnimation { duration: 140 }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                visible: !tile.compact

                Text {
                    font.family: Config.font
                    text: tile.title
                    color: tile.fg
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    font.family: Config.font
                    text: tile.subtitle
                    color: tile.fgDim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    visible: text !== ""
                }
            }
        }

        TapHandler {
            enabled: tile.tapEnabled
            onTapped: tile.toggled()
        }

        HoverHandler {
            id: tileHover

            cursorShape: Qt.PointingHandCursor
        }
    }

    // Kleiner Knopf auf einer Kachel. Wi-Fi und Bluetooth bauen sich ihren
    // Pfeil noch von Hand; hier lohnt das Bauteil, weil zwei nebeneinander
    // stehen und beide gleich aussehen sollen.
    component MiniButton: Rectangle {
        id: mini

        property string icon
        // Farben der Kachel, auf der der Knopf sitzt (tile.controlColor usw.)
        property color bg: Colors.alpha(Colors.fgSurface, 0.1)
        property color bgHover: Colors.alpha(Colors.fgSurface, 0.18)
        property color fg: Colors.fgBackground
        signal tapped()

        implicitWidth: 34
        implicitHeight: 34
        radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: miniHover.hovered ? mini.bgHover : mini.bg

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Behavior on opacity {
            NumberAnimation { duration: 140 }
        }

        Text {
            anchors.centerIn: parent

            text: mini.icon
            font.family: "Material Symbols Outlined"
            font.pixelSize: 18
            color: mini.fg
        }

        HoverHandler {
            id: miniHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds   // exklusiv: kein Kachel-Toggle
            onTapped: mini.tapped()
        }
    }

    component CircleToggle: Rectangle {
        id: circle

        property string icon
        property bool active
        signal toggled()

        implicitWidth: 54
        implicitHeight: 54
        radius: 27
        color: circle.active ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.08)

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Text {
            anchors.centerIn: parent

            text: circle.icon
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
            color: circle.active ? Colors.fgPrimary : Colors.fgSurfaceVariant

            Behavior on color {
                ColorAnimation { duration: 140 }
            }
        }

        TapHandler {
            onTapped: circle.toggled()
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    // ---------- Die Kacheln als Components ----------
    // Der Loader im Platz unten setzt Breite und Hoehe; Layout-Attached-
    // Properties am Kachel-Root greifen deshalb nicht mehr.

    Component {
        id: wifiComponent

        Tile {
            id: wifiTile

            tapEnabled: false   // Toggle macht der bewachte TapHandler unten

            icon: !root.wifiOn ? "wifi_off" : WifiStatus.connecting ? WifiStatus.icon : "wifi"
            title: "Wi-Fi"
            subtitle: root.wifiStatus
            active: root.wifiOn
            onToggled: root.toggleWifi()

            // Links schaltet den Funk, rechts fuehrt der Pfeil in die Liste
            // (dasselbe Muster wie bei der No-Sleep-Pille)
            TapHandler {
                id: wifiTap

                onTapped: {
                    if (wifiTile.compact || wifiTap.point.position.x < wifiTile.width - 46)
                        root.toggleWifi();
                }
            }

            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                visible: !wifiTile.compact
                width: 34
                height: 34
                radius: height / 2
                color: wifiMore.containsMouse ? wifiTile.controlHover
                                              : wifiTile.controlColor

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent

                    text: "chevron_right"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 18
                    color: wifiTile.fg
                }

                MouseArea {
                    id: wifiMore

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openWifi()
                }
            }
        }
    }

    Component {
        id: bluetoothComponent

        Tile {
            id: bluetoothTile

            tapEnabled: false
            icon: root.btOn ? "bluetooth" : "bluetooth_disabled"
            title: "Bluetooth"
            subtitle: !root.btOn ? I18n.tr("Aus")
                      : BluetoothService.summary || I18n.tr("An")
            active: root.btOn
            onToggled: root.toggleBt()

            TapHandler {
                id: bluetoothTap

                onTapped: {
                    if (bluetoothTile.compact || bluetoothTap.point.position.x < bluetoothTile.width - 46)
                        root.toggleBt();
                }
            }

            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                visible: !bluetoothTile.compact
                width: 34
                height: 34
                radius: 17
                color: bluetoothMore.containsMouse ? bluetoothTile.controlHover
                                                    : bluetoothTile.controlColor

                Text {
                    anchors.centerIn: parent
                    text: "chevron_right"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 18
                    color: bluetoothTile.fg
                }

                MouseArea {
                    id: bluetoothMore

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openBluetooth()
                }
            }
        }
    }

    Component {
        id: gameModeComponent

        CircleToggle {
            icon: "sports_esports"
            active: root.gameMode
            onToggled: root.toggleGameMode()
        }
    }

    Component {
        id: airplaneComponent

        CircleToggle {
            icon: "flight"
            active: Airplane.active
            onToggled: Airplane.toggle()
        }
    }

    Component {
        id: vpnComponent

        Tile {
            id: vpnTile

            tapEnabled: false
            icon: Vpn.connected ? "vpn_key" : "vpn_key_off"
            title: Vpn.providerName
            subtitle: Vpn.statusText
            active: Vpn.connected
            onToggled: Vpn.toggle()

            TapHandler {
                id: vpnTap

                onTapped: {
                    if (vpnTile.compact || vpnTap.point.position.x < vpnTile.width - 46)
                        Vpn.toggle();
                }
            }

            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                visible: !vpnTile.compact
                width: 34
                height: 34
                radius: 17
                color: root.vpnMenuOpen ? vpnTile.controlHover
                                        : vpnTile.controlColor

                Text {
                    anchors.centerIn: parent
                    text: root.vpnMenuOpen ? "expand_less" : "expand_more"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 18
                    color: vpnTile.fg
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        root.vpnMenuOpen = !root.vpnMenuOpen;
                        if (root.vpnMenuOpen) {
                            root.sleepMenuOpen = false;
                            root.powerMenuOpen = false;
                        }
                    }
                }
            }

            Rectangle {
                id: vpnMenuPanel

                Component.onCompleted: root.vpnMenu = vpnMenuPanel
                Component.onDestruction: {
                    if (root.vpnMenu === vpnMenuPanel)
                        root.vpnMenu = null;
                    root.vpnMenuHovered = false;
                }

                visible: root.vpnMenuOpen
                anchors {
                    top: parent.bottom
                    topMargin: 4
                    left: parent.left
                    leftMargin: 10
                }
                width: 180
                height: 72
                z: 200
                radius: 16
                color: Colors.shade(Colors.background, 0.08)
                border.width: 1
                border.color: Colors.outlineVariant

                // Eigene Trefferflaeche, damit Klicks nicht zur darunter
                // liegenden Aufnahme-Kachel durchfallen.
                MouseArea {
                    anchors.fill: parent
                }

                HoverHandler {
                    onHoveredChanged: root.vpnMenuHovered = hovered
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2

                    Repeater {
                        model: [
                            { id: "nordvpn", label: "NordVPN" },
                            { id: "cloudflare", label: "Cloudflare WARP" }
                        ]

                        Rectangle {
                            id: providerOption

                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 15
                            color: Vpn.provider === providerOption.modelData.id ? Colors.primary : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 6

                                Text {
                                    font.family: Config.font
                                    text: providerOption.modelData.label
                                    font.pixelSize: 12
                                    color: Vpn.provider === providerOption.modelData.id ? Colors.fgPrimary : Colors.fgBackground
                                }

                                Text {
                                    text: "check"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16
                                    visible: Vpn.provider === providerOption.modelData.id
                                    color: Colors.fgPrimary
                                }
                            }

                            MouseArea {
                                id: providerMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Vpn.selectProvider(providerOption.modelData.id);
                                    root.vpnMenuOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: noSleepComponent

        Tile {
            id: noSleepTile

            tapEnabled: false   // Toggle macht der bewachte TapHandler unten

            icon: "coffee"
            title: "No Sleep"
            subtitle: !root.noSleep ? I18n.tr("Aus")
                     : root.sleepDurationSec === -1 ? I18n.tr("Aktiv (unbegrenzt)")
                     : root.sleepDurationSec === 0 ? I18n.tr("Unendlich")
                     : I18n.tr("Noch %1").arg(root.fmtRemaining(root.sleepRemaining))
            active: root.noSleep
            onToggled: root.toggleNoSleep()

            TapHandler {
                id: pillTap

                // Taps im Dropdown-Bereich (rechts) gehoeren dem Dropdown
                onTapped: {
                    if (noSleepTile.compact || pillTap.point.position.x < noSleepTile.width - 96)
                        root.toggleNoSleep();
                }
            }

            // Dropdown-Knopf: zeigt "–", solange keine Dauer gewaehlt ist
            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                visible: !noSleepTile.compact
                implicitWidth: dropdownLabel.implicitWidth + arrow.implicitWidth + 22
                implicitHeight: 34
                radius: 17
                color: root.sleepMenuOpen ? noSleepTile.controlHover : noSleepTile.controlColor

                Behavior on color {
                    ColorAnimation { duration: 140 }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        id: dropdownLabel
                        font.family: Config.font

                        text: root.durationLabel(root.sleepDurationSec)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: noSleepTile.fg
                    }

                    Text {
                        id: arrow

                        text: root.sleepMenuOpen ? "expand_less" : "expand_more"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16
                        color: noSleepTile.fgDim
                    }
                }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds   // exklusiv: kein Pillen-Toggle
                    onTapped: {
                        root.sleepMenuOpen = !root.sleepMenuOpen;
                        if (root.sleepMenuOpen) {
                            root.vpnMenuOpen = false;
                            root.powerMenuOpen = false;
                        }
                    }
                }
            }

            // Das Menue haengt schmal unter dem Dropdown-Knopf und ragt aus
            // der Karte heraus – Bar.qml haengt es in die Eingabe-Maske
            Rectangle {
                id: sleepMenuPanel

                Component.onCompleted: root.sleepMenu = sleepMenuPanel
                Component.onDestruction: {
                    if (root.sleepMenu === sleepMenuPanel)
                        root.sleepMenu = null;
                    root.sleepMenuHovered = false;
                }

                visible: root.sleepMenuOpen
                anchors {
                    top: parent.bottom
                    topMargin: 4
                    right: parent.right
                    rightMargin: 10
                }
                width: 150
                height: 140
                radius: 16
                color: Colors.shade(Colors.background, 0.08)
                border.width: 1
                border.color: Colors.outlineVariant

                HoverHandler {
                    onHoveredChanged: root.sleepMenuHovered = hovered
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2

                    Repeater {
                        model: [
                            { label: "30m", sec: 1800 },
                            { label: "1h", sec: 3600 },
                            { label: "4h", sec: 14400 },
                            { label: "---", sec: 0 }
                        ]

                        Rectangle {
                            id: option

                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 15
                            color: root.sleepDurationSec === option.modelData.sec ? Colors.primary : "transparent"
                            border.width: 1
                            border.color: optionHover.hovered
                                          ? Colors.alpha(Colors.fgSurfaceVariant, 0.55)
                                          : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }

                            Behavior on border.color {
                                ColorAnimation { duration: 100 }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 6

                                Text {
                                    font.family: Config.font
                                    text: option.modelData.label
                                    font.pixelSize: 12
                                    color: root.sleepDurationSec === option.modelData.sec ? Colors.fgPrimary : Colors.fgBackground
                                }

                                Text {
                                    text: "check"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16
                                    visible: root.sleepDurationSec === option.modelData.sec
                                    color: Colors.fgPrimary
                                }
                            }

                            TapHandler {
                                onTapped: root.pickDuration(option.modelData.sec)
                            }

                            HoverHandler {
                                id: optionHover
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: settingsComponent

        CircleToggle {
            icon: "tune"
            active: SettingsState.open
            onToggled: SettingsState.toggleOnFocused()
        }
    }

    Component {
        id: recordComponent

        Tile {
            id: recordTile

            tapEnabled: false   // Toggle macht der bewachte TapHandler unten

            icon: Recorder.active ? "stop_circle" : "screen_record"
            title: I18n.tr("Aufnahme")
            subtitle: Recorder.active
                      ? I18n.tr("Läuft · %1").arg(Recorder.elapsedLabel)
                      : I18n.tr(Recorder.sound ? "%1 · mit Ton" : "%1 · ohne Ton")
                        .arg(I18n.tr(Recorder.region ? "Bereich" : "Vollbild"))
            active: Recorder.active
            accent: Colors.record
            onAccent: Colors.fgRecord
            onToggled: Recorder.toggle()

            // Links schaltet die Aufnahme, rechts sitzen die beiden Schalter
            // (dasselbe Muster wie bei der Wi-Fi-Pille)
            TapHandler {
                id: recordTap

                onTapped: {
                    if (recordTile.compact || recordTap.point.position.x < recordTile.width - 90)
                        Recorder.toggle();
                }
            }

            // Modus und Ton. Beide gelten ab der naechsten Aufnahme – waehrend
            // einer laufenden bekommt gpu-screen-recorder nichts mehr gesagt,
            // deshalb sind sie dann ausgegraut.
            Row {
                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                visible: !recordTile.compact
                spacing: 6

                MiniButton {
                bg: recordTile.controlColor
                bgHover: recordTile.controlHover
                fg: recordTile.fg
                    // Vollbild = fokussierter Monitor, Bereich = Rahmen mit slurp
                    enabled: !Recorder.active
                    icon: Recorder.region ? "screenshot_region" : "fullscreen"
                    onTapped: Recorder.region = !Recorder.region
                }

                MiniButton {
                bg: recordTile.controlColor
                bgHover: recordTile.controlHover
                fg: recordTile.fg
                    // Desktop-Ton (default_output), nicht das Mikrofon
                    enabled: !Recorder.active
                    icon: Recorder.sound ? "volume_up" : "volume_off"
                    onTapped: Recorder.sound = !Recorder.sound
                }
            }
        }
    }

    Component {
        id: volumeComponent

        LevelSlider {
            title: I18n.tr("Lautstärke")
            icon: Audio.muted ? "volume_off"
                               : Audio.volume >= 0.5 ? "volume_up" : "volume_down"
            value: Audio.volume
            accent: Audio.muted ? Colors.error : Colors.primary
            foreground: Audio.muted ? Colors.fgError : Colors.fgPrimary
            detailsAvailable: true
            iconClickable: true
            onAdjusted: value => Audio.setVolume(value)
            onDetailsRequested: root.openAudio()
            onIconClicked: Audio.toggleMute()
        }
    }

    // Mikrofon: Eingangspegel des gewaehlten Eingabegeraets. Klick aufs
    // Symbol schaltet stumm, der Pfeil oeffnet die Geraeteauswahl.
    Component {
        id: micComponent

        LevelSlider {
            title: I18n.tr("Mikrofon")
            icon: Audio.sourceMuted ? "mic_off" : "mic"
            value: Audio.sourceVolume
            accent: Audio.sourceMuted ? Colors.error : Colors.secondary
            foreground: Audio.sourceMuted ? Colors.fgError : Colors.fgSecondary
            detailsAvailable: true
            iconClickable: true
            onAdjusted: value => Audio.setSourceVolume(value)
            onDetailsRequested: root.openAudio()
            onIconClicked: Audio.toggleSourceMute()
        }
    }

    // Energieprofil (power-profiles-daemon): Klick oeffnet ein Dropdown mit
    // Sparen / Ausgewogen / Leistung. Aktiv (Akzentflaeche) ausser im
    // Standardprofil "Ausgewogen".
    Component {
        id: powerComponent

        // Nur mit Systemakku waehlbar (Laptop) – am Desktop gesperrt und
        // gedimmt, mit Hinweis statt Profilname
        Tile {
            id: powerTile

            readonly property var current: Power.profiles.find(p => p.value === Power.profile) ?? Power.profiles[1]
            readonly property bool usable: Power.hasSystemBattery
            // Ohne Leistungsprofil (Treiber bietet keins) nur die beiden anderen
            readonly property var choices: Power.hasPerformance ? Power.profiles
                : Power.profiles.filter(p => p.value !== PowerProfile.Performance)

            icon: current.icon
            title: I18n.tr("Energie")
            subtitle: usable ? current.label : I18n.tr("Nur mit Akku")
            active: usable && Power.profile !== PowerProfile.Balanced
            tapEnabled: usable
            opacity: usable ? 1 : 0.45
            onToggled: {
                root.powerMenuOpen = !root.powerMenuOpen;
                if (root.powerMenuOpen) {
                    root.sleepMenuOpen = false;
                    root.vpnMenuOpen = false;
                }
            }

            // Pfeil als Hinweis aufs Dropdown – die ganze Kachel oeffnet es
            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                visible: !powerTile.compact && powerTile.usable
                width: 34
                height: 34
                radius: 17
                color: root.powerMenuOpen ? powerTile.controlHover : powerTile.controlColor

                Behavior on color {
                    ColorAnimation { duration: 140 }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.powerMenuOpen ? "expand_less" : "expand_more"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 18
                    color: powerTile.fg
                }
            }

            Rectangle {
                id: powerMenuPanel

                Component.onCompleted: root.powerMenu = powerMenuPanel
                Component.onDestruction: {
                    if (root.powerMenu === powerMenuPanel)
                        root.powerMenu = null;
                    root.powerMenuHovered = false;
                }

                visible: root.powerMenuOpen
                anchors {
                    top: parent.bottom
                    topMargin: 4
                    right: parent.right
                    rightMargin: 10
                }
                width: 170
                height: powerTile.choices.length * 32 + 8
                z: 200
                radius: 16
                color: Colors.shade(Colors.background, 0.08)
                border.width: 1
                border.color: Colors.outlineVariant

                // Eigene Trefferflaeche, damit Klicks nicht zu den darunter
                // liegenden Reglern durchfallen
                MouseArea {
                    anchors.fill: parent
                }

                HoverHandler {
                    onHoveredChanged: root.powerMenuHovered = hovered
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 2

                    Repeater {
                        model: powerTile.choices

                        Rectangle {
                            id: profileOption

                            required property var modelData
                            readonly property bool chosen: Power.profile === profileOption.modelData.value

                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: 15
                            color: profileOption.chosen ? Colors.primary : "transparent"
                            border.width: 1
                            border.color: profileMouse.containsMouse && !profileOption.chosen
                                          ? Colors.alpha(Colors.fgSurfaceVariant, 0.55)
                                          : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: 140 }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 12
                                spacing: 8

                                Text {
                                    text: profileOption.modelData.icon
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16
                                    color: profileOption.chosen ? Colors.fgPrimary : Colors.fgSurfaceVariant
                                }

                                Text {
                                    font.family: Config.font
                                    text: profileOption.modelData.label
                                    font.pixelSize: 12
                                    color: profileOption.chosen ? Colors.fgPrimary : Colors.fgBackground
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "check"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16
                                    visible: profileOption.chosen
                                    color: Colors.fgPrimary
                                }
                            }

                            MouseArea {
                                id: profileMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Power.setProfile(profileOption.modelData.value);
                                    root.powerMenuOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: brightnessComponent

        LevelSlider {
            title: I18n.tr("Helligkeit")
            icon: "brightness_6"
            value: Brightness.value
            accent: Brightness.value > 0.5
                    ? Colors.alpha(Colors.primary, 0.78) : Colors.primaryDim
            foreground: Brightness.value > 0.5 ? Colors.fgPrimary : Colors.fgBackground
            enabled: Brightness.ready
            opacity: enabled ? 1 : 0.5
            onAdjusted: value => Brightness.setValue(value)
        }
    }

    // ---------- Bearbeiten: Zuruecksetzen / Entfernen ----------
    Loader {
        Layout.fillWidth: true
        active: root.editable
        visible: active && root.edit.editing

        sourceComponent: EditHeader {
            edit: root.edit
        }
    }

    // ---------- Die Reihen aus QuickLayout.rows ----------
    // Im Bearbeitungsmodus bekommt das Raster einen Rahmen (frame); im Modus
    // "Layout" weicht es den Reihen-Bloecken.
    Rectangle {
        id: frame

        Layout.fillWidth: true
        implicitHeight: (root.edit.layoutMode ? blocks.implicitHeight : grid.implicitHeight) + root.framePad * 2
        radius: 20
        color: root.edit.editing ? Colors.alpha(Colors.fgSurface, 0.04) : "transparent"
        border.width: root.edit.editing ? 1 : 0
        border.color: Colors.alpha(Colors.outline, 0.25)
        // Beim Ziehen ueber die Ablage darunter liegen: dort wohnt der Geist
        z: root.edit.dragging ? 5 : 0

        Behavior on color {
            ColorAnimation { duration: 160 }
        }

        // Tippen neben die Kacheln hebt die Wahl auf
        TapHandler {
            enabled: root.edit.editing
            onTapped: root.edit.selectedId = ""
        }

        ColumnLayout {
            id: grid

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.framePad
            }
            spacing: root.spacing
            visible: !root.edit.layoutMode

            Repeater {
                id: rowsRepeater

                // Nur die Anzahl als Modell: ein neues rows-Array (jede
                // Aenderung) baut so nicht alle Kacheln neu, die Plaetze
                // lesen ihren Eintrag selbst und laden nur bei neuer ID
                model: QuickLayout.rows.length

                RowLayout {
                    id: tileRow

                    required property int index
                    // Array von { id, span }; id "_" = Luecke
                    readonly property var entries: QuickLayout.rows[tileRow.index] ?? []
                    readonly property var starts: QuickLayout.columnsOf(tileRow.entries)

                    readonly property alias slots: slotRepeater

                    Layout.fillWidth: true
                    spacing: root.gridSpacing
                    readonly property var ids: tileRow.entries.map(t => t.id)
                    // Reihe mit offenem Dropdown ueber die darunter liegenden heben
                    z: (root.sleepMenuOpen && tileRow.ids.includes("nosleep"))
                       || (root.vpnMenuOpen && tileRow.ids.includes("vpn"))
                       || (root.powerMenuOpen && tileRow.ids.includes("power")) ? 100 : 0

                    Repeater {
                        id: slotRepeater

                        model: tileRow.entries.length

                        // Eingebaute Kacheln kommen aus tileComponents, Plugin-Kacheln
                        // ("<plugin>.<kachel>") als QML-Datei aus Plugins.tiles – die
                        // bekommt `plugin` (Kontext) und, wenn sie es kennt, `tileId`
                        // (QuickTile in modules/widgets hat beides).
                        Loader {
                            id: slot

                            required property int index
                            readonly property var modelData: tileRow.entries[slot.index] ?? ({ id: "", span: 1 })

                            readonly property string tileId: slot.modelData.id
                            readonly property bool isGap: slot.tileId === QuickLayout.gap
                            // Nur der Pfad als Abhaengigkeit: Plugins.tiles wird bei
                            // jeder Plugin-Aenderung neu gebaut, die Kachel soll aber
                            // nur neu laden, wenn ihre Datei wechselt
                            readonly property string pluginUrl: Plugins.tiles[slot.tileId]?.url ?? ""

                            Layout.fillWidth: false
                            // Beim Ziehen am Griff zeigt der Platz die neue Breite live
                            readonly property int shownSpan: root.shownSpan(tileRow.entries, slot.index)

                            Layout.preferredWidth: root.cellWidth(slot.shownSpan)
                            Layout.preferredHeight: slot.item?.implicitHeight ?? 54
                            // Die gezogene Kachel bleibt blass zurueck, der Geist wandert
                            opacity: root.edit.dragId === slot.tileId ? 0.35 : 1
                            // Eine ganz aufgebrauchte Luecke nimmt keinen Platz mehr
                            visible: slot.shownSpan > 0
                            // Ring und Griff der gewaehlten Kachel ragen in die Luecke –
                            // ueber die Nachbarn heben
                            z: root.edit.selectedId === slot.tileId ? 2 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: 120 }
                            }

                            // Bearbeitungs-Schicht ueber der Kachel (nur eingebettet):
                            // langer Druck, Auswahl-Ring, Griff, Ziehen – und im Modus
                            // schluckt sie jede Eingabe, damit die Kachel nicht schaltet
                            Loader {
                                anchors.fill: parent
                                z: 1
                                active: root.editable && !slot.isGap

                                sourceComponent: TileEditOverlay {
                                    edit: root.edit
                                    tileId: slot.tileId
                                    span: slot.modelData.span
                                    step: root.unit + root.gridSpacing
                                }
                            }

                            function rebuild(): void {
                                if (slot.pluginUrl !== "")
                                    slot.setSource(slot.pluginUrl, { plugin: Plugins.tiles[slot.tileId].plugin });
                                else
                                    slot.sourceComponent = slot.isGap ? gapCells : root.tileComponents[slot.tileId] ?? null;
                            }

                            Component.onCompleted: slot.rebuild()
                            // Neue Kachel auf diesem Platz (Reihe umgestellt): nach dem
                            // Binding neu laden, nicht mitten drin (sonst Binding-Schleife)
                            onTileIdChanged: Qt.callLater(slot.rebuild)
                            onPluginUrlChanged: slot.rebuild()
                            onLoaded: {
                                if (slot.pluginUrl !== "" && slot.item && "tileId" in slot.item)
                                    slot.item.tileId = slot.tileId.slice(slot.tileId.indexOf(".") + 1);
                            }
                            onStatusChanged: {
                                if (slot.status === Loader.Error) {
                                    console.warn(`Kachel ${slot.tileId}: ${slot.pluginUrl} laedt nicht`);
                                    slot.sourceComponent = brokenTile;
                                }
                            }

                            // Luecke: im Editor je Spalte eine Blase, sonst leer
                            Component {
                                id: gapCells

                                Row {
                                    spacing: root.gridSpacing

                                    Repeater {
                                        model: root.editable ? slot.shownSpan : 0

                                        CellBubble {
                                            required property int index

                                            width: root.cellWidth(1)
                                            edit: root.edit
                                            rowIndex: tileRow.index
                                            column: (tileRow.starts[slot.index] ?? 0) + index
                                        }
                                    }
                                }
                            }

                            // Ersatz fuer eine Plugin-Kachel, deren QML-Datei nicht
                            // laedt – das Raster behaelt seinen Platz, und man sieht,
                            // welche Kachel es ist
                            Component {
                                id: brokenTile

                                Tile {
                                    icon: "error"
                                    title: Plugins.tiles[slot.tileId]?.label ?? slot.tileId
                                    subtitle: I18n.tr("Kachel lädt nicht")
                                    active: false
                                    tapEnabled: false
                                    opacity: 0.6
                                }
                            }
                        }
                    }

                    // Editor: der freie Rest der Reihe als Blasen. Breitenziehen
                    // zaehlt mit der Vorschau-Breite, die Blasen weichen live.
                    Repeater {
                        id: restCells

                        readonly property int used: tileRow.entries.reduce(
                            (sum, t, i) => sum + root.shownSpan(tileRow.entries, i), 0)

                        model: root.editable ? Math.max(0, QuickLayout.columns - restCells.used) : 0

                        CellBubble {
                            required property int index

                            edit: root.edit
                            Layout.preferredWidth: root.cellWidth(1)
                            Layout.preferredHeight: 54
                            Layout.alignment: Qt.AlignVCenter
                            rowIndex: tileRow.index
                            column: restCells.used + index
                        }
                    }

                    // Rest der Reihe bleibt frei
                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Modus "Layout": Reihen als Bloecke
        Loader {
            id: blocks

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: root.framePad
            }
            active: root.edit.layoutMode
            visible: active

            sourceComponent: RowBlocks {}
        }

        // Geist und Markierung beim Ziehen
        Loader {
            anchors.fill: parent
            active: root.editable && root.edit.dragging

            sourceComponent: DragOverlay {
                edit: root.edit
            }
        }
    }

    // ---------- Bearbeiten: Ablage "Verfuegbar" ----------
    Loader {
        id: available

        Layout.fillWidth: true
        active: root.editable
        visible: active && root.edit.tilesMode

        sourceComponent: EditAvailable {
            edit: root.edit
        }
    }

    // ---------- Ansicht-Pille ----------
    Loader {
        Layout.fillWidth: true
        active: root.editable
        visible: active

        sourceComponent: EditFooter {
            edit: root.edit
        }
    }
}
