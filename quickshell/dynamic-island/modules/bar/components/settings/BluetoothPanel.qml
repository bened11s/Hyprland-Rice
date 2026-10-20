pragma ComponentBehavior: Bound
import QtQuick

import qs.modules.services.bluetooth

import qs
import qs.modules.services.config

Item {
    id: panel

    property bool active: false
    property string menuAddress: ""
    readonly property bool pairingInputOpen: active && BluetoothService.pairingInputRequired
    readonly property real rowHeight: 50
    readonly property real listHeight: 268

    signal closed()

    implicitHeight: header.height + 6 + listWrapper.height

    // In der Pille entsteht die Seite erst beim Oeffnen, also bereits aktiv –
    // dann gibt es kein Wechsel-Signal, die Startarbeit wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        if (!active) {
            panel.menuAddress = "";
            BluetoothService.setDiscovering(false);
            if (BluetoothService.pairingDevice)
                BluetoothService.cancelPairing();
        } else {
            if (BluetoothService.enabled && !BluetoothService.discovering)
                Qt.callLater(() => BluetoothService.setDiscovering(true));
            if (BluetoothService.pairingInputRequired)
                Qt.callLater(() => pinInput.forceActiveFocus());
        }
    }

    component Action: Rectangle {
        id: actionRow

        required property var modelData
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
                verticalCenter: parent.verticalCenter
            }
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: actionRow.modelData.icon
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15
                color: actionRow.modelData.danger ? Colors.error : Colors.fgSurfaceVariant
            }

            Text {
                font.family: Config.font
                anchors.verticalCenter: parent.verticalCenter
                text: actionRow.modelData.label
                font.pixelSize: 12
                color: actionRow.modelData.danger ? Colors.error : Colors.fgBackground
            }
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
                readonly property bool rareDevice: BluetoothService.isRareDevice(row.modelData)
                readonly property bool showSection: row.index === 0
                    || row.rareDevice !== BluetoothService.isRareDevice(BluetoothService.devices[row.index - 1])
                readonly property var actions: row.modelData.paired ? [
                    {
                        action: "trust",
                        icon: row.modelData.trusted ? "heart_minus" : "favorite",
                        label: row.modelData.trusted ? "Vertrauen entziehen" : "Vertrauen"
                    },
                    { action: "forget", icon: "delete", label: "Entfernen", danger: true }
                ] : []

                function runPrimary(): void {
                    panel.menuAddress = "";
                    if (row.modelData.connected)
                        BluetoothService.disconnectDevice(row.modelData);
                    else if (row.modelData.paired)
                        BluetoothService.connectDevice(row.modelData);
                    else
                        BluetoothService.beginPairing(row.modelData);
                }

                function runAction(action: string): void {
                    panel.menuAddress = "";
                    if (action === "trust")
                        BluetoothService.toggleTrusted(row.modelData);
                    else if (action === "forget")
                        BluetoothService.forget(row.modelData);
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
                        text: row.rareDevice ? "Selten genutzte Geräte" : "Geräte"
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

                        Text {
                            font.family: Config.font
                            width: parent.width
                            text: {
                                const parts = [];
                                if (row.modelData.connected)
                                    parts.push("Verbunden");
                                else if (row.modelData.pairing)
                                    parts.push("Kopplung läuft");
                                else if (row.modelData.paired)
                                    parts.push("Gekoppelt");
                                else
                                    parts.push("Verfügbar");
                                if (row.modelData.trusted)
                                    parts.push("vertraut");
                                if (row.modelData.batteryAvailable)
                                    parts.push(`${Math.round(row.modelData.battery * 100)}%`);
                                return parts.join(" · ");
                            }
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 11
                            elide: Text.ElideRight
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

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.connected ? "link_off"
                                : row.modelData.pairing ? "progress_activity"
                                : row.modelData.paired ? "bluetooth_connected" : "add_link"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: row.modelData.connected ? Colors.error : Colors.fgSurfaceVariant
                        }

                        MouseArea {
                            id: primaryArea

                            anchors.fill: parent
                            enabled: !row.modelData.pairing
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

                    Rectangle {
                        anchors {
                            top: parent.bottom
                            topMargin: 4
                            right: parent.right
                        }
                        width: Math.min(parent.width, 240)
                        height: row.menuOpen ? row.actions.length * 30 + (row.actions.length - 1) * 2 + 12 : 0
                        visible: height > 0
                        z: 200
                        radius: 14
                        color: Colors.surfaceContainer
                        border.width: 1
                        border.color: Colors.outlineVariant
                        clip: true

                        Column {
                            id: actionColumn

                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 6
                            }
                            spacing: 2

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
        }

        Column {
            anchors.centerIn: parent
            visible: list.count === 0 && !pairingDialog.visible
            spacing: 8
            width: Math.min(parent.width - 32, 220)

            Text {
                font.family: Config.font
                anchors.horizontalCenter: parent.horizontalCenter
                text: !BluetoothService.enabled ? "Bluetooth ist aus"
                    : BluetoothService.discovering ? "Suche nach Geräten…" : "Keine Geräte gefunden"
                color: Colors.fgSurfaceVariant
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: BluetoothService.enabled && !BluetoothService.discovering
                width: Math.min(parent.width, 140)
                height: 30
                radius: 15
                color: scanEmptyArea.containsMouse ? Colors.alpha(Colors.primary, 0.12) : Colors.alpha(Colors.primary, 0.08)

                Text {
                    font.family: Config.font
                    anchors.centerIn: parent
                    text: "Geräte suchen"
                    color: Colors.primary
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: scanEmptyArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: BluetoothService.setDiscovering(true)
                }
            }
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
                text: `${BluetoothService.pairingEntered} von 6 Ziffern eingegeben`
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
                        text: BluetoothService.pairingRequest === "passkey" ? "Passkey (1–6 Ziffern)" : "PIN"
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
                    text: "Senden"
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
                        text: BluetoothService.pairingRequest === "error" ? "Schließen" : "Abbrechen"
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
                        text: BluetoothService.pairingRequest === "authorize" ? "Erlauben" : "Bestätigen"
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
