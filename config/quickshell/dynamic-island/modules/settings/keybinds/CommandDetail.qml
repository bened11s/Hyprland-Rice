pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config
import qs.modules.services.hypr

// Der gewaehlte Befehl: Titel, Quelle, was er tut, wo er in der Config
// steht, und je Kombination die Tasten mit Aufnehmen / Auf Tastatur waehlen
// / An-Aus / Zuruecksetzen / Entfernen. Eigene Kuerzel lassen sich hier
// umbenennen und ihr Befehl aendern.
//
// Aufnehmen laeuft ueber `capture` (KeyCapture des Editors), "Auf Tastatur
// wählen" meldet der Editor-Ebene, die den naechsten Klick auf eine freie
// Taste speichert (pickRequested).
Item {
    id: detail

    // Eintrag aus HyprBinds.commands oder null
    property var command: null
    required property var capture

    signal pickRequested(string mode, string ref, string title, var payload)

    readonly property bool has: detail.command !== null
    readonly property string title: detail.has ? I18n.tr(detail.command.title) : ""
    readonly property var action: detail.has ? HyprBinds.actionOf(detail.command) : null
    // Erste Config-Kombination: Herkunft und Anker fuer Zusatztasten
    readonly property var configCombo: detail.has ? (detail.command.combos.find(c => c.source === "config") ?? null) : null
    readonly property var origin: detail.configCombo ? HyprBinds.originOf(detail.configCombo.ref) : null
    readonly property bool isCustom: detail.has && detail.command.source === "custom"
    // Maus-Taste/-Rad (nur fuer die Anzeige "Maus"; ob sich eine Kombination
    // aendern laesst, sagt combo.editable)
    function isMouse(combo: var): bool {
        return combo !== null && (combo.mouse === true || String(combo.key).startsWith("mouse"));
    }
    readonly property string customRef: detail.isCustom ? (detail.command.combos.find(c => c.source === "custom")?.ref ?? "") : ""
    // Fehler von Einschalten/Zuruecksetzen (Kombination inzwischen belegt)
    property string actionError: ""

    readonly property string sourceLabel: !detail.has ? ""
        : detail.command.source === "plugin" ? I18n.tr("Plugin „%1“").arg(detail.command.pluginName || "?")
        : detail.command.source === "custom" ? I18n.tr("Eigenes Kürzel")
        : I18n.tr("Hyprland-Config")

    readonly property string kindLabel: {
        switch (detail.action?.kind ?? "") {
        case "exec": return I18n.tr("Befehl");
        case "dispatch": return I18n.tr("Dispatcher");
        case "global": return I18n.tr("Global");
        case "lua": return I18n.tr("Lua");
        }
        return "";
    }

    function openOrigin(): void {
        if (detail.origin)
            Quickshell.execDetached(["kitty", "-e", "nvim", "+" + detail.origin.line, detail.origin.file]);
    }

    // Eigene Kuerzel: Felder folgen dem Befehl – aber nur, wenn ein anderes
    // Kuerzel gewaehlt wird. Der Handler feuert bei jedem HyprBinds-Refresh,
    // getippter Text bliebe sonst nicht stehen. (isCustom ist im Handler noch
    // der alte Wert, darum direkt am Befehl pruefen.)
    property string shownCustomRef: ""

    onCommandChanged: {
        detail.actionError = "";
        const custom = detail.command?.source === "custom";
        const ref = custom ? (detail.command.combos.find(c => c.source === "custom")?.ref ?? "") : "";
        if (ref === detail.shownCustomRef)
            return;
        detail.shownCustomRef = ref;
        if (ref !== "") {
            nameField.text = detail.command.custom?.title ?? "";
            execField.text = detail.command.custom?.exec ?? "";
        }
    }
    readonly property bool customDirty: detail.isCustom
        && (nameField.text.trim() !== (detail.command.custom?.title ?? "") || execField.text.trim() !== (detail.command.custom?.exec ?? ""))

    function saveCustom(): void {
        if (detail.customRef !== "" && nameField.text.trim() !== "" && execField.text.trim() !== "")
            Keybinds.editCustom(detail.customRef, nameField.text.trim(), execField.text.trim());
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.alpha(Colors.fgSurface, 0.06)
        clip: true

        // ---- Leer ----
        Column {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: !detail.has
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "keyboard_alt"
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.5)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 40
            }

            Text {
                width: parent.width
                text: I18n.tr("Wähle einen Befehl aus der Liste oder klicke eine belegte Taste.")
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 12
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ---- Inhalt ----
        Flickable {
            id: flick

            anchors {
                fill: parent
                margins: 14
            }
            visible: detail.has
            clip: true
            contentWidth: width
            contentHeight: column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            WheelHandler {
                enabled: flick.contentHeight > flick.height
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;
                    const max = Math.max(0, flick.contentHeight - flick.height);
                    flick.contentY = Math.max(0, Math.min(max, flick.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            Column {
                id: column

                width: flick.width
                spacing: 12

                // Kopf: Titel, Quelle, Ausfuehren
                Item {
                    width: parent.width
                    height: head.implicitHeight

                    Column {
                        id: head

                        anchors {
                            left: parent.left
                            right: runChip.visible ? runChip.left : parent.right
                            rightMargin: 10
                        }
                        spacing: 3

                        Text {
                            width: parent.width
                            text: detail.title
                            color: Colors.fgSurface
                            font.family: Config.font
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: detail.has ? `${I18n.tr(detail.command.group)} · ${detail.sourceLabel}` : ""
                            color: Colors.fgSurfaceVariant
                            font.family: Config.font
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    KbChip {
                        id: runChip

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        visible: detail.has && detail.command.runnable
                        icon: "play_arrow"
                        label: I18n.tr("Ausführen")
                        primary: true
                        onClicked: HyprBinds.runCommand(detail.command)
                    }
                }

                // Eigenes Kuerzel: Name und Befehl aendern
                Column {
                    width: parent.width
                    visible: detail.isCustom
                    spacing: 6

                    KbField {
                        id: nameField

                        width: parent.width
                        icon: "label"
                        placeholder: I18n.tr("Name")
                        onAccepted: detail.saveCustom()
                    }

                    KbField {
                        id: execField

                        width: parent.width
                        icon: "terminal"
                        placeholder: I18n.tr("Shell-Befehl")
                        mono: true
                        onAccepted: detail.saveCustom()
                    }

                    Row {
                        spacing: 6

                        KbChip {
                            icon: "check"
                            label: I18n.tr("Speichern")
                            primary: true
                            enabled: detail.customDirty && nameField.text.trim() !== "" && execField.text.trim() !== ""
                            onClicked: detail.saveCustom()
                        }

                        KbChip {
                            icon: "delete"
                            label: I18n.tr("Kürzel entfernen")
                            danger: true
                            onClicked: if (detail.customRef !== "") Keybinds.removeCustom(detail.customRef)
                        }
                    }
                }

                // Was der Befehl tut
                Rectangle {
                    width: parent.width
                    visible: detail.action !== null && !detail.isCustom
                    height: actionCol.implicitHeight + 20
                    radius: 10
                    color: Qt.darker(Colors.surface, 1.2)
                    border.width: 1
                    border.color: Colors.alpha(Colors.background, 0.6)

                    Column {
                        id: actionCol

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 10
                        }
                        spacing: 6

                        Row {
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: kindText.implicitWidth + 12
                                height: 18
                                radius: 5
                                color: Colors.alpha(Colors.primary, 0.16)

                                Text {
                                    id: kindText

                                    anchors.centerIn: parent
                                    text: detail.kindLabel
                                    color: Colors.primary
                                    font.family: Config.font
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: detail.origin !== null
                                text: detail.origin ? `${detail.origin.file.split("/").pop()}:${detail.origin.line}` : ""
                                color: Colors.fgSurfaceVariant
                                font.family: Config.font
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            width: parent.width
                            text: detail.action?.text ?? ""
                            color: Colors.fgSurface
                            font.family: "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 8
                            elide: Text.ElideRight
                        }

                        KbChip {
                            visible: detail.origin !== null
                            size: 24
                            icon: "open_in_new"
                            label: I18n.tr("In Config öffnen")
                            onClicked: detail.openOrigin()
                        }
                    }
                }

                // ---- Kombinationen ----
                Text {
                    text: I18n.tr("Tasten")
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: detail.has ? detail.command.combos : []

                    Rectangle {
                        id: comboRow

                        required property var modelData

                        readonly property var combo: comboRow.modelData
                        readonly property bool readOnly: !comboRow.combo.editable
                        readonly property bool resettable: (comboRow.combo.changed || comboRow.combo.disabled)
                            && (comboRow.combo.source === "config" || comboRow.combo.source === "plugin")
                        readonly property bool removable: comboRow.combo.source === "extra"
                        readonly property string status: {
                            const parts = [];
                            if (detail.isMouse(comboRow.combo))
                                parts.push(I18n.tr("Maus"));
                            if (comboRow.combo.source === "extra")
                                parts.push(I18n.tr("Zusatztaste"));
                            if (comboRow.combo.changed)
                                parts.push(I18n.tr("geändert"));
                            if (comboRow.combo.disabled)
                                parts.push(I18n.tr("aus"));
                            return parts.join(" · ");
                        }

                        width: column.width
                        height: 44
                        radius: 10
                        color: Colors.alpha(Colors.fgSurface, 0.05)
                        border.width: 1
                        border.color: Colors.alpha(Colors.fgSurface, comboRow.combo.disabled ? 0.04 : 0.08)

                        Row {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 4

                            Repeater {
                                model: comboRow.combo.keys

                                Keycap {
                                    required property string modelData

                                    anchors.verticalCenter: parent?.verticalCenter
                                    text: modelData
                                    accent: comboRow.combo.changed
                                    dim: comboRow.combo.disabled
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: comboRow.status !== ""
                                text: comboRow.status
                                color: comboRow.combo.disabled ? Colors.fgSurfaceVariant : Colors.primary
                                font.family: Config.font
                                font.pixelSize: 10
                                leftPadding: 6
                            }
                        }

                        Row {
                            anchors {
                                right: parent.right
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 2

                            KbIconButton {
                                visible: !comboRow.readOnly
                                icon: "radio_button_checked"
                                hint: I18n.tr("Neu aufnehmen")
                                onClicked: detail.capture.start("set", comboRow.combo.ref, detail.title, null)
                            }

                            KbIconButton {
                                visible: !comboRow.readOnly
                                icon: "ads_click"
                                hint: I18n.tr("Auf Tastatur wählen")
                                onClicked: detail.pickRequested("set", comboRow.combo.ref, detail.title, null)
                            }

                            KbIconButton {
                                visible: !comboRow.readOnly
                                icon: comboRow.combo.disabled ? "visibility_off" : "visibility"
                                hint: comboRow.combo.disabled ? I18n.tr("Einschalten") : I18n.tr("Ausschalten")
                                checked: comboRow.combo.disabled
                                onClicked: {
                                    if (comboRow.combo.disabled)
                                        detail.actionError = HyprBinds.enableChecked(comboRow.combo.ref);
                                    else {
                                        Keybinds.setDisabled(comboRow.combo.ref, true);
                                        detail.actionError = "";
                                    }
                                }
                            }

                            KbIconButton {
                                visible: comboRow.resettable
                                icon: "undo"
                                hint: I18n.tr("Zurücksetzen")
                                onClicked: detail.actionError = HyprBinds.resetChecked(comboRow.combo.ref)
                            }

                            KbIconButton {
                                visible: comboRow.removable
                                icon: "delete"
                                hint: I18n.tr("Entfernen")
                                danger: true
                                onClicked: Keybinds.removeCustom(comboRow.combo.ref)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: comboRow.readOnly
                                text: I18n.tr("nur lesend")
                                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                font.family: Config.font
                                font.pixelSize: 10
                                rightPadding: 6
                            }
                        }
                    }
                }

                // Einschalten/Zuruecksetzen ging nicht: die Kombination hat ein anderer
                Text {
                    width: parent.width
                    visible: detail.actionError !== ""
                    text: detail.actionError
                    color: Colors.error
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                // Weitere Taste (nur Befehle der Config)
                Row {
                    visible: detail.configCombo !== null && detail.configCombo.editable
                    spacing: 6

                    KbChip {
                        icon: "add"
                        label: I18n.tr("Weitere Taste aufnehmen")
                        onClicked: detail.capture.start("extra", detail.configCombo.ref, detail.title, null)
                    }

                    KbChip {
                        icon: "ads_click"
                        label: I18n.tr("Auf Tastatur wählen")
                        onClicked: detail.pickRequested("extra", detail.configCombo.ref, detail.title, null)
                    }
                }
            }
        }
    }
}
