pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.network
import qs.modules.services.core

import qs
import qs.modules.services.config

// WLAN-Ansicht der Settings-Karte: Liste der Netze, verbinden, Passwort
// aendern, vergessen. Die Karte zeigt entweder die Kacheln oder das hier
// (siehe Settings.qml); die Daten kommen aus dem Network-Dienst.
Item {
    id: panel

    property bool active: false
    signal closed()

    // Welche Zeile ihr Menue bzw. ihr Passwortfeld offen hat (SSID oder "")
    property string menuSsid: ""
    property string passwordSsid: ""

    readonly property real rowHeight: 50
    // Feste Hoehe statt "so hoch wie der Inhalt": waehrend des ersten Scans
    // ist die Liste leer, die Karte waere winzig – und wer die Maus dorthin
    // bewegt, wo die Liste gleich auftaucht, waere schon draussen und haette
    // sie wieder zugeklappt.
    readonly property real listHeight: 268

    implicitHeight: header.height + 6 + listWrapper.height + (statusText.visible ? statusText.height + 6 : 0)

    // Netzliste regelmaessig neu lesen, solange das Panel offen ist
    DemandRequest {
        demand: Network.demand
        active: panel.active
    }

    // In der Pille entsteht die Seite erst beim Oeffnen, also bereits aktiv –
    // dann gibt es kein Wechsel-Signal, die Startarbeit wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        panel.menuSsid = "";
        panel.passwordSsid = "";
        list.contentY = 0;   // oben anfangen – das verbundene Netz steht vorn
        if (active)
            Network.refresh(true);
    }

    // Zeile im Aktions-Menue einer Zeile. Inline-Komponenten muessen auf
    // der obersten Ebene der Datei stehen – steckte sie (wie zuerst) im
    // Flow, legt Qt sie stillschweigend nicht an und das Menue blieb leer.
    component Action: Rectangle {
        id: actionRow

        required property var modelData

        signal triggered()

        implicitHeight: 30
        radius: 12
        color: actionArea.containsMouse ? Colors.alpha(actionRow.modelData.danger ? Colors.error : Colors.fgSurface, 0.16)
                                        : "transparent"

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

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

    function rowTapped(net: var, index: int): void {
        if (net.active) {
            // Verbundenes Netz: nur das Menue, Trennen ist eine bewusste Geste
            panel.toggleMenu(net.ssid, index);
        } else if (net.saved) {
            Network.connect(net, "");
        } else if (net.secured) {
            panel.passwordSsid = panel.passwordSsid === net.ssid ? "" : net.ssid;
            panel.menuSsid = "";
        } else {
            Network.connect(net, "");
        }
    }

    function toggleMenu(ssid: string, index: int): void {
        const opening = panel.menuSsid !== ssid;
        panel.menuSsid = opening ? ssid : "";
        panel.passwordSsid = "";
        // Das Menue haengt an seiner Zeile – steht die unten am Rand, scrollt
        // die Liste nach, damit es nicht abgeschnitten im Clip endet
        if (opening)
            Qt.callLater(() => list.positionViewAtIndex(index, ListView.Beginning));
    }

    // ---- Kopfzeile ----
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
            radius: height / 2
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
            text: "WLAN"
            color: Colors.fgBackground
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: rescanButton

            anchors {
                right: radioToggle.left
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            width: 30
            height: 30
            radius: height / 2
            color: rescanArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"
            opacity: Network.radioOn ? 1 : 0.4

            Text {
                id: rescanIcon

                anchors.centerIn: parent
                text: "refresh"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
                color: Colors.fgSurfaceVariant

                RotationAnimator {
                    target: rescanIcon
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: (Network.busy || Network.scanning) && rescanIcon.visible
                    onRunningChanged: if (!running)
                        rescanIcon.rotation = 0
                }
            }

            MouseArea {
                id: rescanArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: Network.radioOn
                onClicked: Network.refresh(true)
            }
        }

        // Funk an/aus als Schiebeschalter
        Rectangle {
            id: radioToggle

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            width: 40
            height: 22
            radius: height / 2
            color: Network.radioOn ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.18)

            Behavior on color {
                ColorAnimation { duration: 140 }
            }

            Rectangle {
                width: 16
                height: 16
                radius: 8
                y: 3
                x: Network.radioOn ? parent.width - width - 3 : 3
                color: Network.radioOn ? Colors.fgPrimary : Colors.fgSurfaceVariant

                Behavior on x {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Network.setRadio(!Network.radioOn)
            }
        }
    }

    // ---- Meldung ----
    Text {
        id: statusText
        font.family: Config.font

        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
        }
        text: Network.status
        visible: text !== ""
        color: text.startsWith("Error") || text.indexOf("Fehl") >= 0 ? Colors.error : Colors.fgSurfaceVariant
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    // ---- LAN ----
    // Kabelanschluesse stehen ueber der WLAN-Liste; ohne Netzwerkkarte faellt
    // der Abschnitt weg. Er nimmt der Liste Platz, statt die Karte wachsen zu
    // lassen (siehe listHeight).
    Column {
        id: wiredSection

        anchors {
            top: statusText.visible ? statusText.bottom : header.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
        }
        visible: Network.wired.length > 0
        height: visible ? implicitHeight : 0
        spacing: 4

        Repeater {
            model: Network.wired

            Rectangle {
                id: wiredRow

                required property var modelData

                readonly property bool canConnect: !wiredRow.modelData.connected
                    && !wiredRow.modelData.connecting && wiredRow.modelData.available

                width: wiredSection.width
                height: panel.rowHeight
                radius: 14
                color: wiredRow.modelData.connected ? Colors.alpha(Colors.primary, 0.16)
                     : wiredRow.canConnect && wiredArea.containsMouse ? Colors.shade(Colors.background, 0.08)
                     : Colors.shade(Colors.background, 0.05)
                opacity: wiredRow.modelData.available ? 1 : 0.6

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                // Klick verbindet; Trennen nur ueber den Knopf, wie beim WLAN
                MouseArea {
                    id: wiredArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: wiredRow.canConnect ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (wiredRow.canConnect)
                        Network.connectWired(wiredRow.modelData)
                }

                Text {
                    id: wiredIcon

                    anchors {
                        left: parent.left
                        leftMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    text: "lan"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    color: wiredRow.modelData.connected ? Colors.primary : Colors.fgSurfaceVariant
                }

                Column {
                    anchors {
                        left: wiredIcon.right
                        leftMargin: 12
                        right: wiredButton.visible ? wiredButton.left : parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    Text {
                        font.family: Config.font
                        width: parent.width
                        text: wiredRow.modelData.connected && wiredRow.modelData.connection !== ""
                              ? wiredRow.modelData.connection : "LAN"
                        color: Colors.fgBackground
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        font.family: Config.font
                        width: parent.width
                        text: [Network.wiredStateText(wiredRow.modelData), wiredRow.modelData.device,
                               wiredRow.modelData.ip].filter(s => s !== "").join(" · ")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: wiredButton

                    anchors {
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    width: 28
                    height: 28
                    visible: wiredRow.modelData.connected || wiredRow.canConnect
                    radius: height / 2
                    color: wiredButtonArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: wiredRow.modelData.connected ? "link_off" : "link"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16
                        color: wiredRow.modelData.connected ? Colors.error : Colors.fgSurfaceVariant
                    }

                    MouseArea {
                        id: wiredButtonArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wiredRow.modelData.connected ? Network.disconnectWired(wiredRow.modelData)
                                                               : Network.connectWired(wiredRow.modelData)
                    }
                }
            }
        }
    }

    // ---- Liste ----
    Item {
        id: listWrapper

        anchors {
            top: wiredSection.visible ? wiredSection.bottom
                 : statusText.visible ? statusText.bottom : header.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
        }
        height: panel.listHeight - (wiredSection.visible ? wiredSection.height + 6 : 0)

        ListView {
            id: list

            anchors.fill: parent
            clip: true
            spacing: 4
            model: Network.radioOn ? Network.networks : []
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

                readonly property bool menuOpen: panel.menuSsid === row.modelData.ssid
                readonly property bool passwordOpen: panel.passwordSsid === row.modelData.ssid

                // Verfuegbare Aktionen dieses Netzes – bewusst hier auf der
                // Zeile berechnet, nicht ueber visible-Bindungen an den
                // Menue-Eintraegen: die evaluierten bei Inline-Komponenten in
                // der eingeklappten (unsichtbaren) Karte einmal falsch und
                // wurden nie wieder aktualisiert, das Menue blieb dauerhaft zu
                readonly property var actions: {
                    const net = row.modelData;
                    const items = [];
                    if (net.saved && net.secured)
                        items.push({ action: "password", icon: "key", label: "Passwort ändern" });
                    if (net.duplicate && net.stale.length > 0)
                        items.push({ action: "dropStale", icon: "cleaning_services",
                                     label: `${net.stale.length} doppeltes Profil entfernen` });
                    if (net.saved)
                        items.push({ action: "forget", icon: "delete", label: "Vergessen", danger: true });
                    return items;
                }

                function runAction(action: string): void {
                    const net = row.modelData;
                    if (action === "password")
                        panel.passwordSsid = net.ssid;
                    else if (action === "dropStale")
                        Network.dropStale(net);
                    else if (action === "forget")
                        Network.forget(net);
                    panel.menuSsid = "";
                }

                function runConnectionAction(): void {
                    if (row.modelData.active)
                        Network.disconnect(row.modelData);
                    else
                        Network.connect(row.modelData, "");
                    panel.menuSsid = "";
                }

                width: ListView.view.width
                spacing: 4
                z: row.menuOpen ? 100 : 0

                // Zeile selbst
                Rectangle {
                    width: parent.width
                    height: panel.rowHeight
                    radius: 14
                    color: row.modelData.active ? Colors.alpha(Colors.primary, 0.16)
                         : rowArea.containsMouse ? Colors.shade(Colors.background, 0.08)
                         : Colors.shade(Colors.background, 0.05)

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    MouseArea {
                        id: rowArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.rowTapped(row.modelData, row.index)
                    }

                    Text {
                        id: signalIcon

                        anchors {
                            left: parent.left
                            leftMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        text: Network.signalIcon(row.modelData)
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 20
                        color: row.modelData.active ? Colors.primary : Colors.fgSurfaceVariant
                    }

                    Column {
                        anchors {
                            left: signalIcon.right
                            leftMargin: 12
                            right: lockIcon.visible ? lockIcon.left
                                                   : connectionButton.visible ? connectionButton.left
                                                   : menuButton.visible ? menuButton.left : parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            font.family: Config.font
                            width: parent.width
                            text: row.modelData.ssid
                            color: Colors.fgBackground
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            font.family: Config.font
                            width: parent.width
                            text: {
                                const net = row.modelData;
                                const parts = [];
                                if (net.active)
                                    parts.push("Verbunden");
                                else if (net.saved)
                                    parts.push("Gespeichert");
                                if (!net.inRange)
                                    parts.push("nicht in Reichweite");
                                else
                                    parts.push(`${net.signal}%`);
                                if (net.duplicate)
                                    parts.push(`${net.profiles.length} Profile`);
                                return parts.join(" · ");
                            }
                            color: row.modelData.duplicate ? Colors.error : Colors.fgSurfaceVariant
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: lockIcon

                        anchors {
                            right: connectionButton.visible ? connectionButton.left
                                                            : menuButton.visible ? menuButton.left : parent.right
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.modelData.secured ? "lock" : "lock_open"
                        visible: row.modelData.inRange
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 14
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                    }

                    Rectangle {
                        id: connectionButton

                        anchors {
                            right: menuButton.visible ? menuButton.left : parent.right
                            rightMargin: menuButton.visible ? 4 : 8
                            verticalCenter: parent.verticalCenter
                        }
                        width: 28
                        height: 28
                        visible: row.modelData.active || (row.modelData.saved && row.modelData.inRange)
                        radius: height / 2
                        color: connectionArea.containsMouse
                               ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.active ? "link_off" : "wifi"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                            color: row.modelData.active ? Colors.error : Colors.fgSurfaceVariant
                        }

                        MouseArea {
                            id: connectionArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row.runConnectionAction()
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
                        radius: height / 2
                        color: row.menuOpen ? Colors.alpha(Colors.fgSurface, 0.14)
                             : menuArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.1)
                             : "transparent"

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
                            onClicked: panel.toggleMenu(row.modelData.ssid, row.index)
                        }
                    }

                    // Das Menue liegt ueber den folgenden WLAN-Zeilen. Es ist
                    // kein Kind des Column-Layouts und vergroessert die Zeile
                    // deshalb nicht.
                    Rectangle {
                        id: actionMenu

                        anchors {
                            top: parent.bottom
                            topMargin: 4
                            right: parent.right
                        }
                        width: Math.min(parent.width, 240)
                        height: row.menuOpen && row.actions.length > 0
                                ? row.actions.length * 30 + (row.actions.length - 1) * 2 + 12 : 0
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

                // Passwortfeld
                Rectangle {
                    width: parent.width
                    height: row.passwordOpen ? 42 : 0
                    visible: height > 0
                    radius: 14
                    color: Colors.shade(Colors.background, 0.08)
                    clip: true

                    onVisibleChanged: if (visible)
                        password.forceActiveFocus()

                    Text {
                        id: keyIcon

                        anchors {
                            left: parent.left
                            leftMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        text: "key"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16
                        color: Colors.fgSurfaceVariant
                    }

                    TextInput {
                        id: password
                        font.family: Config.font

                        anchors {
                            left: keyIcon.right
                            leftMargin: 10
                            right: connectButton.left
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        echoMode: TextInput.Password
                        color: Colors.fgBackground
                        font.pixelSize: 12
                        selectionColor: Colors.alpha(Colors.primary, 0.35)
                        clip: true

                        Keys.onEscapePressed: panel.passwordSsid = ""
                        Keys.onReturnPressed: connectButton.submit()
                        Keys.onEnterPressed: connectButton.submit()

                        Text {
                            anchors.fill: parent
                            visible: password.text === ""
                            text: "Passwort"
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                            font: password.font
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        id: connectButton

                        function submit(): void {
                            if (password.text === "")
                                return;
                            Network.connect(row.modelData, password.text);
                            password.text = "";
                            panel.passwordSsid = "";
                        }

                        anchors {
                            right: parent.right
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        width: 88
                        height: 30
                        radius: height / 2
                        color: password.text === "" ? Colors.alpha(Colors.fgSurface, 0.1) : Colors.primary

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        Text {
                            font.family: Config.font
                            anchors.centerIn: parent
                            text: "Verbinden"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: password.text === "" ? Colors.fgSurfaceVariant : Colors.fgPrimary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: connectButton.submit()
                        }
                    }
                }

            }
        }

        Text {
            font.family: Config.font
            anchors.centerIn: parent
            visible: list.count === 0
            text: Network.radioOn ? (Network.loaded ? "Keine Netze gefunden" : "Suche…") : "WLAN ist aus"
            color: Colors.fgSurfaceVariant
            font.pixelSize: 12
        }
    }
}
