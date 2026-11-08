pragma ComponentBehavior: Bound
import QtQuick

import qs.modules.services.bluetooth

import qs
import qs.modules.services.config
import qs.modules.services.core

Item {
    id: panel

    property bool active: false
    property string menuAddress: ""
    // Geraet, dessen Name gerade getippt wird (Eingabezeile unter der Reihe)
    property string renameAddress: ""
    property bool adapterMenuOpen: false
    // Settings.qml haengt den Tastaturfokus hieran (typingPin) – gilt deshalb
    // auch fuer die Umbenennen-Zeile, nicht nur fuer PIN/Passkey
    readonly property bool pairingInputOpen: active && (BluetoothService.pairingInputRequired || renameAddress !== "")
    readonly property real rowHeight: 50
    readonly property real listHeight: 268

    signal closed()

    implicitHeight: header.height + 6 + listWrapper.height

    // Sortierte Liste und Audio-Profile gibt es nur auf Anfrage. `visible`
    // haelt sie waehrend des Ausblendens, damit die Liste nicht vorher leer wird
    DemandRequest {
        demand: BluetoothService.demand
        active: panel.active || panel.visible
    }

    // In der Pille entsteht die Seite erst beim Oeffnen, also bereits aktiv –
    // dann gibt es kein Wechsel-Signal, die Startarbeit wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        if (!active) {
            panel.menuAddress = "";
            panel.renameAddress = "";
            panel.adapterMenuOpen = false;
            BluetoothService.setDiscovering(false);
            if (BluetoothService.pairingDevice)
                BluetoothService.cancelPairing();
        } else if (BluetoothService.pairingInputRequired) {
            Qt.callLater(() => pinInput.forceActiveFocus());
        }
    }

    // Menuezeile: { icon, label, danger?, active? } – `active` setzt ein Haekchen
    component Action: Rectangle {
        id: actionRow

        required property var modelData
        readonly property bool current: actionRow.modelData.active ?? false
        signal triggered()

        implicitHeight: 30
        radius: 12
        color: actionArea.containsMouse
               ? Colors.alpha(actionRow.modelData.danger ? Colors.error : Colors.fgSurface, 0.16)
               : "transparent"

        Row {
            anchors {
                left: parent.left
                leftMargin: 10
                right: checkMark.left
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 8

            Text {
                id: actionIcon

                anchors.verticalCenter: parent.verticalCenter
                text: actionRow.modelData.icon
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15
                color: actionRow.modelData.danger ? Colors.error
                     : actionRow.current ? Colors.primary : Colors.fgSurfaceVariant
            }

            Text {
                font.family: Config.font
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - actionIcon.width - parent.spacing
                text: actionRow.modelData.label
                font.pixelSize: 12
                font.weight: actionRow.current ? Font.DemiBold : Font.Normal
                color: actionRow.modelData.danger ? Colors.error
                     : actionRow.current ? Colors.primary : Colors.fgBackground
                elide: Text.ElideRight
            }
        }

        Text {
            id: checkMark

            anchors {
                right: parent.right
                rightMargin: actionRow.current ? 10 : 0
                verticalCenter: parent.verticalCenter
            }
            width: actionRow.current ? implicitWidth : 0
            visible: actionRow.current
            text: "check"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 15
            color: Colors.primary
        }

        MouseArea {
            id: actionArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionRow.triggered()
        }
    }

    function toggleMenu(address: string, index: int): void {
        const opening = panel.menuAddress !== address;
        panel.menuAddress = opening ? address : "";
        panel.renameAddress = "";
        panel.adapterMenuOpen = false;
        if (opening)
            Qt.callLater(() => list.positionViewAtIndex(index, ListView.Beginning));
    }

    Item {
        id: header

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 36
        // Das Adapter-Menue haengt ueber der Liste
        z: panel.adapterMenuOpen ? 300 : 0

        Rectangle {
            id: backButton

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            width: 30
            height: 30
            radius: 15
            color: backArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

            Text {
                anchors.centerIn: parent
                text: "chevron_left"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20
                color: Colors.fgBackground
            }

            MouseArea {
                id: backArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.closed()
            }
        }

        Text {
            font.family: Config.font
            anchors {
                left: backButton.right
                leftMargin: 6
                verticalCenter: parent.verticalCenter
            }
            text: "Bluetooth"
            color: Colors.fgBackground
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        // Adapterwahl – nur mit mehreren Adaptern (Onboard + USB-Stick)
        Rectangle {
            id: adapterButton

            anchors {
                right: visibleButton.left
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            width: 30
            height: 30
            visible: BluetoothService.adapters.length > 1
            radius: 15
            color: panel.adapterMenuOpen ? Colors.alpha(Colors.fgSurface, 0.14)
                 : adapterArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

            Text {
                anchors.centerIn: parent
                text: "settings_input_antenna"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
                color: BluetoothService.autoAdapter ? Colors.fgSurfaceVariant : Colors.primary
            }

            MouseArea {
                id: adapterArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    panel.menuAddress = "";
                    panel.renameAddress = "";
                    panel.adapterMenuOpen = !panel.adapterMenuOpen;
                }
            }
        }

        // Adapter-Menue: "Automatisch" (zeigt die aktuelle Wahl) plus ein
        // Eintrag je Adapter. Eintraege entstehen erst beim Aufklappen
        Rectangle {
            anchors {
                top: parent.bottom
                topMargin: 4
                right: parent.right
            }
            width: Math.min(parent.width, 300)
            height: panel.adapterMenuOpen ? adapterLoader.implicitHeight + 12 : 0
            visible: height > 0
            radius: 14
            color: Colors.surfaceContainer
            border.width: 1
            border.color: Colors.outlineVariant
            clip: true

            Loader {
                id: adapterLoader

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 6
                }
                active: panel.adapterMenuOpen

                sourceComponent: Column {
                    id: adapterColumn

                    readonly property var entries: {
                        const current = BluetoothService.adapter?.adapterId ?? "";
                        const auto = BluetoothService.autoAdapter;
                        const rows = [{
                            id: "",
                            icon: "auto_mode",
                            label: auto && current !== "" ? `${I18n.tr("Automatisch")} · ${current}` : I18n.tr("Automatisch"),
                            active: auto
                        }];
                        for (const a of BluetoothService.adapters) {
                            rows.push({
                                id: a.adapterId,
                                icon: "bluetooth",
                                label: BluetoothService.adapterLabel(a),
                                active: !auto && a.adapterId === current
                            });
                        }
                        return rows;
                    }

                    spacing: 2

                    Item {
                        width: adapterColumn.width
                        height: 18

                        Text {
                            font.family: Config.font
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                bottom: parent.bottom
                                bottomMargin: 2
                            }
                            text: I18n.tr("Adapter")
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: adapterColumn.entries

                        Action {
                            width: adapterColumn.width
                            onTriggered: {
                                BluetoothService.selectAdapter(modelData.id);
                                panel.adapterMenuOpen = false;
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: visibleButton

            anchors {
                right: scanButton.left
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            width: 30
            height: 30
            radius: 15
            color: BluetoothService.discoverable ? Colors.primary
                   : visibleArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.12) : "transparent"
            opacity: BluetoothService.enabled ? 1 : 0.4

            Text {
                anchors.centerIn: parent
                text: BluetoothService.discoverable ? "visibility" : "visibility_off"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
                color: BluetoothService.discoverable ? Colors.fgPrimary : Colors.fgSurfaceVariant
            }

            MouseArea {
                id: visibleArea

                anchors.fill: parent
                enabled: BluetoothService.enabled
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: BluetoothService.setDiscoverable(!BluetoothService.discoverable)
            }
        }

        Rectangle {
            id: scanButton

            anchors {
                right: powerToggle.left
                rightMargin: 5
                verticalCenter: parent.verticalCenter
            }
            width: 30
            height: 30
            radius: 15
            color: BluetoothService.discovering ? Colors.alpha(Colors.primary, 0.18)
                   : scanArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"
            opacity: BluetoothService.enabled ? 1 : 0.4

            Text {
                id: scanIcon

                anchors.centerIn: parent
                text: "refresh"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
                color: BluetoothService.discovering ? Colors.primary : Colors.fgSurfaceVariant

                RotationAnimator {
                    target: scanIcon
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: BluetoothService.discovering && scanIcon.visible
                    onRunningChanged: if (!running)
                        scanIcon.rotation = 0
                }
            }

            MouseArea {
                id: scanArea

                anchors.fill: parent
                enabled: BluetoothService.enabled
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: BluetoothService.setDiscovering(!BluetoothService.discovering)
            }
        }

        Rectangle {
            id: powerToggle

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            width: 40
            height: 22
            radius: 11
            color: BluetoothService.enabled ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.18)

            Rectangle {
                width: 16
                height: 16
                radius: 8
                y: 3
                x: BluetoothService.enabled ? parent.width - width - 3 : 3
                color: BluetoothService.enabled ? Colors.fgPrimary : Colors.fgSurfaceVariant

                Behavior on x {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: BluetoothService.setEnabled(!BluetoothService.enabled)
            }
        }
    }

    Item {
        id: listWrapper

        anchors {
            top: header.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
        }
        height: panel.listHeight

        ListView {
            id: list

            anchors.fill: parent
            clip: true
            spacing: 4
            model: BluetoothService.enabled ? BluetoothService.devices : []
            // Kein Highlight-Nachfuehren (siehe LauncherPanel.qml)
            highlightFollowsCurrentItem: false
            boundsBehavior: Flickable.StopAtBounds

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;
                    const max = Math.max(0, list.contentHeight - list.height);
                    list.contentY = Math.max(0, Math.min(max, list.contentY - delta * panel.rowHeight));
                    event.accepted = true;
                }
            }

            delegate: Column {
                id: row

                required property var modelData
                required property int index

                readonly property bool menuOpen: panel.menuAddress === row.modelData.address
                readonly property bool renaming: panel.renameAddress === row.modelData.address
                readonly property bool rareDevice: BluetoothService.isRareDevice(row.modelData)
                readonly property bool showSection: row.index === 0
                    || row.rareDevice !== BluetoothService.isRareDevice(BluetoothService.devices[row.index - 1])
                // Laufender Vorgang ("connect"/"disconnect"), letzter Fehler, Akku
                readonly property string busy: BluetoothService.busy(row.modelData)
                readonly property string error: BluetoothService.errorFor(row.modelData)
                readonly property int battery: BluetoothService.batteryLevel(row.modelData)
                readonly property bool spinning: row.busy !== "" || row.modelData.pairing
                // Solange etwas laeuft oder das Geraet blockiert ist, tut der Hauptknopf nichts
                readonly property bool locked: row.spinning || row.modelData.blocked
                // Audio-Profile gibt es nur fuer verbundene Audio-Geraete
                readonly property var audio: row.modelData.connected ? BluetoothService.audioInfo(row.modelData) : null
                readonly property var profiles: row.audio?.profiles ?? []
                readonly property bool autoConnect: BluetoothService.autoConnects(row.modelData)
                readonly property var actions: row.modelData.paired ? [
                    { action: "rename", icon: "edit", label: I18n.tr("Umbenennen") },
                    {
                        action: "auto",
                        icon: row.autoConnect ? "sync_disabled" : "sync",
                        label: row.autoConnect ? I18n.tr("Nicht automatisch verbinden") : I18n.tr("Automatisch verbinden")
                    },
                    {
                        action: "trust",
                        icon: row.modelData.trusted ? "heart_minus" : "favorite",
                        label: row.modelData.trusted ? I18n.tr("Vertrauen entziehen") : I18n.tr("Vertrauen")
                    },
                    {
                        action: "block",
                        icon: row.modelData.blocked ? "lock_open" : "block",
                        label: row.modelData.blocked ? I18n.tr("Freigeben") : I18n.tr("Blockieren")
                    },
                    { action: "forget", icon: "delete", label: I18n.tr("Entfernen"), danger: true }
                ] : []

                function runPrimary(): void {
                    panel.menuAddress = "";
                    panel.renameAddress = "";
                    if (row.locked)
                        return;
                    if (row.modelData.connected)
                        BluetoothService.disconnectDevice(row.modelData);
                    else if (row.modelData.paired)
                        BluetoothService.connectDevice(row.modelData);
                    else
                        BluetoothService.beginPairing(row.modelData);
                }

                function runAction(action: string): void {
                    panel.menuAddress = "";
                    if (action === "rename")
                        panel.renameAddress = row.modelData.address;
                    else if (action === "auto")
                        BluetoothService.setAutoConnect(row.modelData, !row.autoConnect);
                    else if (action === "trust")
                        BluetoothService.toggleTrusted(row.modelData);
                    else if (action === "block")
                        BluetoothService.toggleBlocked(row.modelData);
                    else if (action === "forget")
                        BluetoothService.forget(row.modelData);
                }

                function setProfile(name: string): void {
                    panel.menuAddress = "";
                    BluetoothService.setAudioProfile(row.modelData, name);
                }

                width: ListView.view.width
                z: row.menuOpen ? 100 : 0
                spacing: row.showSection ? 4 : 0

                Item {
                    width: parent.width
                    height: row.showSection ? 20 : 0
                    visible: row.showSection

                    Text {
                        font.family: Config.font
                        anchors {
                            left: parent.left
                            leftMargin: 8
                            bottom: parent.bottom
                        }
                        text: row.rareDevice ? I18n.tr("Selten genutzte Geräte") : I18n.tr("Geräte")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    width: parent.width
                    height: panel.rowHeight
                    radius: 14
                    color: row.modelData.connected ? Colors.alpha(Colors.primary, 0.16)
                         : rowArea.containsMouse ? Colors.shade(Colors.background, 0.08)
                         : Colors.shade(Colors.background, 0.05)

                    MouseArea {
                        id: rowArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.runPrimary()
                    }

                    Text {
                        id: deviceIcon

                        anchors {
                            left: parent.left
                            leftMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        text: BluetoothService.deviceIcon(row.modelData)
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 20
                        color: row.modelData.connected ? Colors.primary : Colors.fgSurfaceVariant
                        opacity: row.modelData.blocked ? 0.5 : 1
                    }

                    Column {
                        anchors {
                            left: deviceIcon.right
                            leftMargin: 12
                            right: primaryButton.left
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            font.family: Config.font
                            width: parent.width
                            text: BluetoothService.deviceName(row.modelData)
                            color: Colors.fgBackground
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        // Status, dahinter Akku als Symbol + Prozent
                        Row {
                            width: parent.width
                            spacing: 4

                            Text {
                                id: statusText

                                font.family: Config.font
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Math.max(0, parent.width
                                    - (batteryIcon.visible ? batteryIcon.width + batteryText.width + 2 * parent.spacing : 0)))
                                text: {
                                    if (row.error !== "")
                                        return row.error;
                                    if (row.busy === "connect")
                                        return I18n.tr("Verbinde…");
                                    if (row.busy === "disconnect")
                                        return I18n.tr("Trenne…");
                                    const parts = [];
                                    if (row.modelData.blocked)
                                        parts.push(I18n.tr("Blockiert"));
                                    else if (row.modelData.connected)
                                        parts.push(I18n.tr("Verbunden"));
                                    else if (row.modelData.pairing)
                                        parts.push(I18n.tr("Kopplung läuft"));
                                    else if (row.modelData.paired)
                                        parts.push(I18n.tr("Gekoppelt"));
                                    else
                                        parts.push(I18n.tr("Verfügbar"));
                                    if (row.modelData.trusted && !row.modelData.blocked)
                                        parts.push(I18n.tr("vertraut"));
                                    if (row.autoConnect && !row.modelData.blocked)
                                        parts.push(I18n.tr("automatisch"));
                                    return parts.join(" · ");
                                }
                                color: row.error !== "" ? Colors.error
                                     : row.busy !== "" ? Colors.primary : Colors.fgSurfaceVariant
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Text {
                                id: batteryIcon

                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.battery >= 0
                                text: BluetoothService.batteryIcon(row.battery)
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 13
                                color: row.battery <= 10 ? Colors.error : Colors.fgSurfaceVariant
                            }

                            Text {
                                id: batteryText

                                font.family: Config.font
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.battery >= 0
                                text: `${row.battery} %`
                                color: row.battery <= 10 ? Colors.error : Colors.fgSurfaceVariant
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle {
                        id: primaryButton

                        anchors {
                            right: menuButton.visible ? menuButton.left : parent.right
                            rightMargin: menuButton.visible ? 4 : 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: 28
                        height: 28
                        radius: 14
                        color: primaryArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"
                        opacity: row.modelData.blocked ? 0.4 : 1

                        Text {
                            id: primaryIcon

                            anchors.centerIn: parent
                            text: row.spinning ? "progress_activity"
                                : row.modelData.blocked ? "block"
                                : row.modelData.connected ? "link_off"
                                : row.modelData.paired ? "bluetooth_connected" : "add_link"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: row.spinning ? Colors.primary
                                 : row.modelData.connected ? Colors.error : Colors.fgSurfaceVariant

                            // Dreht, solange verbunden/getrennt/gekoppelt wird
                            RotationAnimator {
                                target: primaryIcon
                                from: 0
                                to: 360
                                duration: 900
                                loops: Animation.Infinite
                                running: row.spinning && primaryIcon.visible
                                onRunningChanged: if (!running)
                                    primaryIcon.rotation = 0
                            }
                        }

                        MouseArea {
                            id: primaryArea

                            anchors.fill: parent
                            enabled: !row.locked
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row.runPrimary()
                        }
                    }

                    Rectangle {
                        id: menuButton

                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: 28
                        height: 28
                        visible: row.actions.length > 0
                        radius: 14
                        color: row.menuOpen ? Colors.alpha(Colors.fgSurface, 0.14)
                             : menuArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "more_vert"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: Colors.fgSurfaceVariant
                        }

                        MouseArea {
                            id: menuArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.toggleMenu(row.modelData.address, row.index)
                        }
                    }

                    // Geraetemenue: oben das Audioprofil (falls vorhanden),
                    // darunter die Aktionen. Inhalt entsteht erst beim Aufklappen
                    Rectangle {
                        anchors {
                            top: parent.bottom
                            topMargin: 4
                            right: parent.right
                        }
                        width: Math.min(parent.width, row.profiles.length > 0 ? 300 : 240)
                        height: row.menuOpen ? menuLoader.implicitHeight + 12 : 0
                        visible: height > 0
                        z: 200
                        radius: 14
                        color: Colors.surfaceContainer
                        border.width: 1
                        border.color: Colors.outlineVariant
                        clip: true

                        Loader {
                            id: menuLoader

                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 6
                            }
                            active: row.menuOpen

                            sourceComponent: Column {
                                id: actionColumn

                                spacing: 2

                                Item {
                                    width: actionColumn.width
                                    height: 18
                                    visible: row.profiles.length > 0

                                    Text {
                                        font.family: Config.font
                                        anchors {
                                            left: parent.left
                                            leftMargin: 10
                                            bottom: parent.bottom
                                            bottomMargin: 2
                                        }
                                        text: I18n.tr("Audioprofil")
                                        color: Colors.fgSurfaceVariant
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Repeater {
                                    model: row.profiles

                                    BluetoothProfileRow {
                                        width: actionColumn.width
                                        current: (row.audio?.active ?? "") === modelData.name
                                        onTriggered: row.setProfile(modelData.name)
                                    }
                                }

                                Rectangle {
                                    width: actionColumn.width
                                    height: 1
                                    visible: row.profiles.length > 0
                                    color: Colors.outlineVariant
                                }

                                Repeater {
                                    model: row.actions

                                    Action {
                                        width: actionColumn.width
                                        onTriggered: row.runAction(modelData.action)
                                    }
                                }
                            }
                        }
                    }
                }

                // Umbenennen: Eingabezeile unter dem Geraet (wie das Passwortfeld
                // in WifiPanel). Enter uebernimmt, Esc bricht ab, leer setzt den
                // Geraetenamen zurueck. Entsteht nur, solange getippt wird
                Loader {
                    width: parent.width
                    height: row.renaming ? 46 : 0
                    active: row.renaming
                    visible: active

                    sourceComponent: Item {
                        Rectangle {
                            id: renameField

                            function submit(): void {
                                BluetoothService.rename(row.modelData, renameInput.text);
                                panel.renameAddress = "";
                            }

                            anchors.fill: parent
                            anchors.topMargin: 4
                            radius: 14
                            color: Colors.shade(Colors.background, 0.08)
                            border.width: 1
                            border.color: renameInput.activeFocus ? Colors.primary : "transparent"

                            Text {
                                id: renameIcon

                                anchors {
                                    left: parent.left
                                    leftMargin: 14
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "edit"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 16
                                color: Colors.fgSurfaceVariant
                            }

                            TextInput {
                                id: renameInput
                                font.family: Config.font

                                anchors {
                                    left: renameIcon.right
                                    leftMargin: 10
                                    right: renameButtons.left
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                maximumLength: 64
                                color: Colors.fgBackground
                                font.pixelSize: 12
                                selectionColor: Colors.alpha(Colors.primary, 0.35)
                                clip: true

                                // Fokus wie beim PIN-Feld erst nach dem Aufbau holen
                                Component.onCompleted: {
                                    renameInput.text = row.modelData.name ?? "";
                                    renameInput.selectAll();
                                    Qt.callLater(() => renameInput.forceActiveFocus());
                                }

                                Keys.onEscapePressed: panel.renameAddress = ""
                                Keys.onReturnPressed: renameField.submit()
                                Keys.onEnterPressed: renameField.submit()

                                Text {
                                    anchors.fill: parent
                                    visible: renameInput.text === ""
                                    text: row.modelData.deviceName || row.modelData.address
                                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                    font: renameInput.font
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: renameButtons

                                anchors {
                                    right: parent.right
                                    rightMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 2

                                // Zurueck zum Geraetenamen – nur wenn ein eigener Name gesetzt ist
                                Rectangle {
                                    width: 28
                                    height: 28
                                    visible: (row.modelData.deviceName ?? "") !== ""
                                             && row.modelData.name !== row.modelData.deviceName
                                    radius: 14
                                    color: resetArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "restart_alt"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 16
                                        color: Colors.fgSurfaceVariant
                                    }

                                    MouseArea {
                                        id: resetArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            BluetoothService.rename(row.modelData, "");
                                            panel.renameAddress = "";
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: Colors.primary

                                    Text {
                                        anchors.centerIn: parent
                                        text: "check"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 16
                                        color: Colors.fgPrimary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: renameField.submit()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            font.family: Config.font
            anchors.centerIn: parent
            visible: list.count === 0 && !pairingDialog.visible
            text: !BluetoothService.enabled ? I18n.tr("Bluetooth ist aus")
                : BluetoothService.discovering ? I18n.tr("Suche nach Geräten…") : I18n.tr("Keine Geräte gefunden")
            color: Colors.fgSurfaceVariant
            font.pixelSize: 12
        }

        MouseArea {
            anchors.fill: parent
            visible: pairingDialog.visible
            z: 499
            // Eingaben hinter dem Kopplungsdialog abfangen.
            onWheel: wheel => wheel.accepted = true
        }

        Rectangle {
            id: pairingDialog

            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 370)
            height: 210
            visible: panel.active && BluetoothService.pairingDevice !== null
            z: 500
            radius: 18
            color: Colors.surfaceContainer
            border.width: 1
            border.color: Colors.outlineVariant

            MouseArea {
                anchors.fill: parent
            }

            Text {
                id: pairingTitle
                font.family: Config.font

                anchors {
                    top: parent.top
                    topMargin: 12
                    left: parent.left
                    leftMargin: 14
                    right: parent.right
                    rightMargin: 14
                }
                text: BluetoothService.deviceName(BluetoothService.pairingDevice)
                color: Colors.fgBackground
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                font.family: Config.font
                anchors {
                    top: pairingTitle.bottom
                    topMargin: 3
                    left: pairingTitle.left
                    right: pairingTitle.right
                }
                text: BluetoothService.pairingMessage
                color: BluetoothService.pairingRequest === "error" ? Colors.error : Colors.fgSurfaceVariant
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Text {
                anchors.centerIn: parent
                visible: BluetoothService.pairingPasskey !== ""
                text: BluetoothService.pairingPasskey
                font.family: Config.font
                font.pixelSize: 28
                font.letterSpacing: 5
                font.weight: Font.DemiBold
                color: Colors.primary
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 134
                visible: BluetoothService.pairingRequest === "display" && BluetoothService.pairingEntered > 0
                text: I18n.tr("%1 von 6 Ziffern eingegeben").arg(BluetoothService.pairingEntered)
                font.family: Config.font
                font.pixelSize: 11
                color: Colors.fgSurfaceVariant
            }

            Rectangle {
                id: pinField

                anchors {
                    left: parent.left
                    leftMargin: 12
                    right: parent.right
                    rightMargin: 12
                    bottom: submitButton.top
                    bottomMargin: 8
                }
                height: 34
                visible: BluetoothService.pairingInputRequired
                radius: 12
                color: Colors.shade(Colors.background, 0.06)
                border.width: 1
                border.color: pinInput.activeFocus ? Colors.primary : Colors.outlineVariant

                TextInput {
                    id: pinInput
                    font.family: Config.font

                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: BluetoothService.pairingRequest === "passkey" ? TextInput.Normal : TextInput.Password
                    maximumLength: BluetoothService.pairingRequest === "passkey" ? 6 : 16
                    validator: RegularExpressionValidator {
                        regularExpression: BluetoothService.pairingRequest === "passkey" ? /[0-9]{1,6}/ : /[^\x00\r\n]{1,16}/
                    }
                    inputMethodHints: BluetoothService.pairingRequest === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhSensitiveData
                    color: Colors.fgBackground
                    selectionColor: Colors.alpha(Colors.primary, 0.35)
                    font.pixelSize: 12
                    Keys.onReturnPressed: submitButton.submit()
                    Keys.onEnterPressed: submitButton.submit()
                    Keys.onEscapePressed: BluetoothService.cancelPairing()

                    Text {
                        anchors.fill: parent
                        visible: pinInput.text === ""
                        text: BluetoothService.pairingRequest === "passkey" ? I18n.tr("Passkey (1–6 Ziffern)") : "PIN"
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                        font: pinInput.font
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Rectangle {
                id: submitButton

                function submit(): void {
                    if (!pinInput.acceptableInput)
                        return;
                    BluetoothService.submitPin(pinInput.text);
                    pinInput.text = "";
                }

                anchors {
                    right: parent.right
                    rightMargin: 12
                    bottom: parent.bottom
                    bottomMargin: 12
                }
                width: 86
                height: 34
                visible: BluetoothService.pairingInputRequired
                radius: 12
                color: !pinInput.acceptableInput ? Colors.alpha(Colors.fgSurface, 0.1) : Colors.primary

                Text {
                    font.family: Config.font
                    anchors.centerIn: parent
                    text: I18n.tr("Senden")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: !pinInput.acceptableInput ? Colors.fgSurfaceVariant : Colors.fgPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: submitButton.submit()
                }
            }

            Row {
                anchors {
                    left: parent.left
                    leftMargin: 12
                    bottom: parent.bottom
                    bottomMargin: 12
                }
                spacing: 8

                Rectangle {
                    width: 82
                    height: 32
                    radius: 12
                    color: Colors.alpha(Colors.fgSurface, 0.1)

                    Text {
                        font.family: Config.font
                        anchors.centerIn: parent
                        text: BluetoothService.pairingRequest === "error" ? I18n.tr("Schließen") : I18n.tr("Abbrechen")
                        color: Colors.fgBackground
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: BluetoothService.cancelPairing()
                    }
                }

                Rectangle {
                    width: 82
                    height: 32
                    visible: BluetoothService.pairingRequest === "confirm" || BluetoothService.pairingRequest === "authorize"
                    radius: 12
                    color: Colors.primary

                    Text {
                        font.family: Config.font
                        anchors.centerIn: parent
                        text: BluetoothService.pairingRequest === "authorize" ? I18n.tr("Erlauben") : I18n.tr("Bestätigen")
                        color: Colors.fgPrimary
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: BluetoothService.confirmPairing(true)
                    }
                }
            }
        }

        Connections {
            target: BluetoothService

            function onPairingRequestChanged(): void {
                pinInput.text = "";
                if (panel.active && BluetoothService.pairingInputRequired)
                    Qt.callLater(() => pinInput.forceActiveFocus());
            }
        }
    }
}
