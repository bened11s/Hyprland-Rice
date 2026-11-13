pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.widgets
import qs.modules.services.config
import qs.modules.services.vpn

// Block unter "VPN > VPN-Anbieter" (Config.meta editor "vpn"): das Register
// aus services/vpn/Vpn.qml als Karten – eingebaute nur mit Status und
// Installiert-Marke, eigene zum Bearbeiten und Loeschen – darunter
// "Anbieter hinzufügen" samt Vorlagen und das Formular (Name, Symbol,
// Befehle, Regex, Probelauf). Gespeichert wird ueber Vpn.addCustom/
// updateCustom/removeCustom in Config.vpn.custom.
Column {
    id: editor

    spacing: 6
    bottomPadding: 8

    // ---- Zustand ----
    property bool formOpen: false
    // id des eigenen Anbieters im Formular, "" = neuer Anbieter
    property string editing: ""
    // id, deren Loeschen gerade bestaetigt werden will (3 s, dann wieder scharf)
    property string trashArmed: ""

    property string fName: ""
    property string fIcon: "vpn_key"
    property string fConnect: ""
    property string fDisconnect: ""
    property string fStatus: ""
    property string fRegex: ""

    readonly property bool canSave: editor.fName.trim() !== "" && editor.fConnect.trim() !== ""
    readonly property bool canTest: editor.fStatus.trim() !== "" && !(Vpn.testResult?.running ?? false)

    readonly property var icons: ["vpn_key", "shield", "lock", "public", "wifi_lock", "security", "dns", "travel_explore"]

    // Vorlagen fuers Formular – Befehle sind Vorschlaege, die man anpasst
    readonly property var presets: [
        {
            title: "WireGuard", icon: "shield", name: "WireGuard",
            connect: "wg-quick up wg0", disconnect: "wg-quick down wg0",
            status: "ip link show wg0", connectedRegex: "wg0"
        },
        {
            title: "Tailscale", icon: "dns", name: "Tailscale",
            connect: "tailscale up", disconnect: "tailscale down",
            status: "tailscale status", connectedRegex: "100\\.\\d+\\.\\d+\\.\\d+"
        },
        {
            title: "NetworkManager", icon: "public", name: "NetworkManager-VPN",
            connect: "nmcli con up id \"VPN\"", disconnect: "nmcli con down id \"VPN\"",
            status: "nmcli -t -f NAME,TYPE con show --active", connectedRegex: "vpn|wireguard"
        }
    ]

    function openForm(id: string, values: var): void {
        editor.editing = id;
        editor.fName = String(values?.name ?? "");
        editor.fIcon = String(values?.icon ?? "") || "vpn_key";
        editor.fConnect = String(values?.connect ?? "");
        editor.fDisconnect = String(values?.disconnect ?? "");
        editor.fStatus = String(values?.status ?? "");
        editor.fRegex = String(values?.connectedRegex ?? "");
        editor.trashArmed = "";
        Vpn.clearTest();
        editor.formOpen = true;
    }

    function closeForm(): void {
        editor.formOpen = false;
        editor.editing = "";
        editor.trashArmed = "";
        Vpn.clearTest();
    }

    function save(): void {
        if (!editor.canSave)
            return;
        const obj = {
            name: editor.fName, icon: editor.fIcon, connect: editor.fConnect,
            disconnect: editor.fDisconnect, status: editor.fStatus, connectedRegex: editor.fRegex
        };
        if (editor.editing === "") {
            const id = Vpn.addCustom(obj);
            // Gleich benutzen – aber keinen laufenden Tunnel dafuer kappen
            if (!Vpn.connected)
                Vpn.selectProvider(id);
        } else {
            Vpn.updateCustom(editor.editing, obj);
        }
        editor.closeForm();
    }

    function armTrash(id: string): void {
        editor.trashArmed = id;
        disarmTrash.restart();
    }

    function removeProvider(id: string): void {
        editor.trashArmed = "";
        if (editor.editing === id)
            editor.closeForm();
        Vpn.removeCustom(id);
    }

    Timer {
        id: disarmTrash

        interval: 3000
        onTriggered: editor.trashArmed = ""
    }

    // ================= Register =================

    Repeater {
        model: Vpn.providers

        Rectangle {
            id: prow

            required property var modelData
            readonly property string pid: String(prow.modelData.id)
            readonly property bool selected: Vpn.provider === prow.pid
            readonly property bool custom: !prow.modelData.builtin
            readonly property bool installed: prow.modelData.available === true
            readonly property var def: prow.custom ? Vpn.definition(prow.pid) : null
            readonly property bool armed: editor.trashArmed === prow.pid

            width: editor.width
            height: 46
            radius: 10
            color: prow.selected ? Colors.alpha(Colors.primary, 0.1)
                 : rowHover.hovered ? Colors.alpha(Colors.fgSurface, 0.05) : "transparent"
            border.width: 1
            border.color: prow.selected ? Colors.alpha(Colors.primary, 0.35) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
            Behavior on border.color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }

            HoverHandler {
                id: rowHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: Vpn.selectProvider(prow.pid)
            }

            Rectangle {
                id: iconBubble

                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                width: 30
                height: 30
                radius: 15
                color: prow.selected ? Colors.alpha(Colors.primary, 0.2) : Colors.alpha(Colors.fgSurface, 0.08)

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }

                Text {
                    anchors.centerIn: parent
                    text: prow.modelData.icon
                    color: prow.selected ? Colors.primary : Colors.fgBackground
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 17
                }
            }

            Column {
                anchors {
                    left: iconBubble.right
                    leftMargin: 10
                    right: actions.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1

                Row {
                    width: parent.width
                    spacing: 6

                    Text {
                        width: Math.min(implicitWidth, parent.width - (builtinTag.visible ? builtinTag.width + 6 : 0))
                        text: prow.modelData.name
                        color: Colors.fgBackground
                        font.family: Config.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // Eingebaute sind nicht zu bearbeiten
                    Rectangle {
                        id: builtinTag

                        anchors.verticalCenter: parent.verticalCenter
                        visible: !prow.custom
                        width: builtinLabel.implicitWidth + 10
                        height: 15
                        radius: 7.5
                        color: Colors.alpha(Colors.fgSurface, 0.08)

                        Text {
                            id: builtinLabel

                            anchors.centerIn: parent
                            text: I18n.tr("Eingebaut")
                            color: Colors.fgSurfaceVariant
                            font.family: Config.font
                            font.pixelSize: 9
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: (prow.installed ? I18n.tr("Installiert") : I18n.tr("Nicht installiert"))
                          + (prow.custom && prow.def ? "  ·  " + prow.def.connect : "")
                    color: prow.installed ? Colors.fgSurfaceVariant : Colors.secondary
                    font.family: Config.font
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Row {
                id: actions

                anchors {
                    right: parent.right
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4

                // Status nur beim gewaehlten Anbieter – nur den fragt der Dienst
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: prow.selected
                    width: statusLabel.implicitWidth + 16
                    height: 22
                    radius: 11
                    color: Vpn.connected ? Colors.alpha(Colors.primary, 0.18) : Colors.alpha(Colors.fgSurface, 0.08)

                    Behavior on color {
                        ColorAnimation { duration: Appearance.fadeDuration }
                    }

                    Text {
                        id: statusLabel

                        anchors.centerIn: parent
                        text: Vpn.statusText
                        color: Vpn.connected ? Colors.primary : Colors.fgSurfaceVariant
                        font.family: Config.font
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }

                Quiet {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: prow.custom
                    icon: "edit"
                    tint: Colors.fgSurfaceVariant
                    onClicked: editor.openForm(prow.pid, prow.def)
                }

                // Zweistufig: erst das Symbol, dann 3 s lang "Wirklich?"
                Quiet {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: prow.custom
                    icon: prow.armed ? "" : "delete"
                    label: prow.armed ? I18n.tr("Wirklich?") : ""
                    tint: prow.armed ? Colors.error : Colors.fgSurfaceVariant
                    onClicked: prow.armed ? editor.removeProvider(prow.pid) : editor.armTrash(prow.pid)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: prow.selected
                    text: "check"
                    color: Colors.primary
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 18
                }
            }
        }
    }

    // ================= Hinzufuegen + Vorlagen =================

    Flow {
        width: editor.width
        topPadding: 4
        spacing: 6

        ActionButton {
            icon: "add"
            label: I18n.tr("Anbieter hinzufügen")
            filled: !editor.formOpen
            onClicked: editor.formOpen && editor.editing === "" ? editor.closeForm() : editor.openForm("", null)
        }

        Text {
            height: 28
            leftPadding: 6
            verticalAlignment: Text.AlignVCenter
            text: I18n.tr("Vorlagen:")
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 10
        }

        Repeater {
            model: editor.presets

            ActionButton {
                id: presetButton

                required property var modelData

                icon: presetButton.modelData.icon
                label: presetButton.modelData.title
                onClicked: editor.openForm("", presetButton.modelData)
            }
        }
    }

    Text {
        width: editor.width
        topPadding: 2
        text: I18n.tr("Die Befehle laufen ohne Terminal über sh -c. Braucht einer Root-Rechte, erlaube ihn über polkit (pkexec) oder einen sudoers-Eintrag ohne Passwort.")
        color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
        font.family: Config.font
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }

    // ================= Formular =================

    Rectangle {
        id: form

        width: editor.width
        height: editor.formOpen ? formColumn.implicitHeight + 28 : 0
        visible: height > 0
        clip: true
        radius: 12
        color: Colors.alpha(Colors.fgSurface, 0.04)
        border.width: 1
        border.color: Colors.alpha(Colors.primary, 0.25)

        Behavior on height {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        Column {
            id: formColumn

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 14
            }
            spacing: 8

            Text {
                text: editor.editing === "" ? I18n.tr("Neuer Anbieter") : I18n.tr("Anbieter bearbeiten")
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            FormRow {
                label: I18n.tr("Name")

                Field {
                    width: parent.width
                    value: editor.fName
                    placeholder: I18n.tr("z. B. Mullvad")
                    onEdited: text => editor.fName = text
                    onAccepted: editor.save()
                }
            }

            FormRow {
                label: I18n.tr("Symbol")

                Row {
                    spacing: 4

                    Repeater {
                        model: editor.icons

                        Rectangle {
                            id: iconChip

                            required property string modelData
                            readonly property bool picked: editor.fIcon === iconChip.modelData

                            width: 28
                            height: 28
                            radius: 14
                            color: iconChip.picked ? Colors.primary
                                 : chipHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
                                 : Colors.alpha(Colors.fgSurface, 0.06)

                            Behavior on color {
                                ColorAnimation { duration: Appearance.fadeDuration }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: iconChip.modelData
                                color: iconChip.picked ? Colors.fgPrimary : Colors.fgBackground
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 16
                            }

                            HoverHandler {
                                id: chipHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: editor.fIcon = iconChip.modelData
                            }
                        }
                    }
                }
            }

            FormRow {
                label: I18n.tr("Verbinden")

                Field {
                    width: parent.width
                    mono: true
                    value: editor.fConnect
                    placeholder: "wg-quick up wg0"
                    onEdited: text => editor.fConnect = text
                }
            }

            FormRow {
                label: I18n.tr("Trennen")

                Field {
                    width: parent.width
                    mono: true
                    value: editor.fDisconnect
                    placeholder: "wg-quick down wg0"
                    onEdited: text => editor.fDisconnect = text
                }
            }

            FormRow {
                label: I18n.tr("Status")

                Field {
                    width: parent.width
                    mono: true
                    value: editor.fStatus
                    placeholder: "ip link show wg0"
                    onEdited: text => editor.fStatus = text
                }
            }

            FormRow {
                label: I18n.tr("Verbunden, wenn Ausgabe passt auf")

                Field {
                    width: parent.width
                    mono: true
                    value: editor.fRegex
                    placeholder: I18n.tr("Regex, leer = Exit-Code 0")
                    onEdited: text => editor.fRegex = text
                }
            }

            // Probelauf des Status-Befehls
            Row {
                spacing: 8

                ActionButton {
                    icon: "play_arrow"
                    label: I18n.tr("Testen")
                    enabled: editor.canTest
                    onClicked: Vpn.testStatus(editor.fStatus, editor.fRegex)
                }

                Row {
                    id: verdict

                    anchors.verticalCenter: parent.verticalCenter
                    visible: Vpn.testResult !== null
                    spacing: 5

                    readonly property bool running: Vpn.testResult?.running ?? false
                    readonly property bool ok: Vpn.testResult?.connected ?? false

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: verdict.running ? "hourglass_top" : verdict.ok ? "check_circle" : "cancel"
                        color: verdict.running ? Colors.fgSurfaceVariant : verdict.ok ? Colors.primary : Colors.error
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: verdict.running ? I18n.tr("Läuft…")
                            : (verdict.ok ? I18n.tr("Verbunden") : I18n.tr("Nicht verbunden"))
                              + "  ·  " + I18n.tr("Exit-Code %1").arg(Vpn.testResult?.code ?? 0)
                        color: verdict.running ? Colors.fgSurfaceVariant : verdict.ok ? Colors.primary : Colors.error
                        font.family: Config.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }

            Rectangle {
                width: parent.width
                visible: Vpn.testResult !== null && !(Vpn.testResult?.running ?? false)
                height: outputText.implicitHeight + 14
                radius: 9
                color: Colors.alpha(Colors.fgSurface, 0.06)

                Text {
                    id: outputText

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 7
                    }
                    readonly property string output: String(Vpn.testResult?.output ?? "")
                    text: output !== "" ? output : I18n.tr("(keine Ausgabe)")
                    color: output !== "" ? Colors.fgBackground : Colors.fgSurfaceVariant
                    font.family: "monospace"
                    font.pixelSize: 10
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }

            Item {
                width: parent.width
                height: 28

                Row {
                    anchors.left: parent.left
                    spacing: 6

                    ActionButton {
                        icon: "check"
                        label: I18n.tr("Speichern")
                        filled: true
                        enabled: editor.canSave
                        onClicked: editor.save()
                    }

                    ActionButton {
                        icon: "close"
                        label: I18n.tr("Abbrechen")
                        onClicked: editor.closeForm()
                    }
                }

                // Zweistufig wie in der Liste
                ActionButton {
                    anchors.right: parent.right
                    visible: editor.editing !== ""
                    icon: editor.trashArmed === editor.editing ? "warning" : "delete"
                    label: editor.trashArmed === editor.editing ? I18n.tr("Wirklich löschen?") : I18n.tr("Löschen")
                    tint: Colors.error
                    onClicked: editor.trashArmed === editor.editing ? editor.removeProvider(editor.editing)
                                                                    : editor.armTrash(editor.editing)
                }
            }
        }
    }

    // ================= Bausteine =================

    // Beschriftung links, Bedienelement rechts
    component FormRow: Item {
        id: formRow

        property string label: ""
        default property alias content: slot.data

        width: parent.width
        implicitHeight: Math.max(28, slot.childrenRect.height, labelText.implicitHeight)

        Text {
            id: labelText

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            width: 112
            text: formRow.label
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 10
            wrapMode: Text.Wrap
        }

        Item {
            id: slot

            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 120
                verticalCenter: parent.verticalCenter
            }
            height: childrenRect.height
        }
    }

    // Textfeld mit Rahmen; `value` von aussen, `edited(text)` bei jeder Eingabe
    component Field: Rectangle {
        id: field

        property string value: ""
        property bool mono: false
        property string placeholder: ""
        signal edited(string text)
        signal accepted()

        implicitHeight: 28
        implicitWidth: 120
        radius: 8
        color: Colors.alpha(Colors.fgSurface, 0.06)
        border.width: 1
        border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

        // Von aussen gesetzter Wert (Vorlage, anderer Anbieter) – auch im
        // fokussierten Feld; beim Tippen ist value schon gleich text
        onValueChanged: if (input.text !== field.value) input.text = field.value

        Behavior on border.color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        TextInput {
            id: input

            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 9
                rightMargin: 9
                verticalCenter: parent.verticalCenter
            }
            font.family: field.mono ? "monospace" : Config.font
            font.pixelSize: field.mono ? 11 : 12
            color: Colors.fgBackground
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            clip: true
            text: field.value
            onTextEdited: field.edited(text)
            onAccepted: field.accepted()
            Keys.onEscapePressed: event => {
                focus = false;
                event.accepted = true;
            }

            Text {
                anchors.fill: parent
                visible: input.text === ""
                text: field.placeholder
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font: input.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    // Knopf im Chip-Stil (wie in der Plugin-Verwaltung)
    component ActionButton: Rectangle {
        id: button

        required property string icon
        required property string label
        property color tint: Colors.fgSurface
        property bool filled: false
        signal clicked()

        implicitWidth: buttonRow.implicitWidth + 22
        implicitHeight: 28
        radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: button.filled ? (buttonHover.hovered ? Colors.alpha(Colors.primary, 0.85) : Colors.primary)
             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
             : Colors.alpha(Colors.fgSurface, 0.06)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
        Fade on opacity {}

        Row {
            id: buttonRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: button.icon
                color: button.filled ? Colors.fgPrimary : button.tint
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.font
                text: button.label
                color: button.filled ? Colors.fgPrimary : button.tint
                font.pixelSize: 11
                font.weight: button.filled ? Font.DemiBold : Font.Normal

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }
        }

        HoverHandler {
            id: buttonHover

            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: button.enabled
            onTapped: button.clicked()
        }
    }

    // Stiller Knopf: nur Symbol, auf Wunsch mit Text (wie in der Wallpaper-Verwaltung)
    component Quiet: Rectangle {
        id: quiet

        property string icon: ""
        property string label: ""
        property color tint: Colors.fgSurface
        signal clicked()

        implicitWidth: quietRow.implicitWidth + (quiet.label === "" ? 12 : 18)
        implicitHeight: 26
        radius: 8
        opacity: enabled ? 1 : 0.4
        color: quietHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Row {
            id: quietRow

            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: quiet.icon !== ""
                text: quiet.icon
                color: quiet.tint
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: quiet.label !== ""
                text: quiet.label
                color: quiet.tint
                font.family: Config.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        HoverHandler {
            id: quietHover

            cursorShape: quiet.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        // Exklusiv: sitzt in der Anbieter-Zeile, deren TapHandler sonst
        // mitfeuert (Bearbeiten/Loeschen waehlte den Anbieter mit aus)
        TapHandler {
            enabled: quiet.enabled
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: quiet.clicked()
        }
    }
}
