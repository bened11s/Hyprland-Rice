pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.config
import qs.modules.services.hypr
import qs.modules.settings.keybinds
import "keybinds/KeyLayout.js" as Layout

// Einstellungsseite Tastenkürzel (Config.meta editor "keybinds").
//
// Oben die Tastatur-Vorschau: sie zeigt je Ebene (Modifier-Maske, Klick auf
// Super/Strg/Alt/Shift schaltet) was auf jeder Taste liegt; die Tasten des
// gewaehlten Befehls leuchten. Darunter links die Liste aller Befehle (Suche,
// Filter), rechts der gewaehlte Befehl mit seinen Kombinationen und den
// Knoepfen zum Neu-Belegen, An/Aus, Zuruecksetzen, Entfernen.
//
// Zwei Wege zu einer neuen Belegung: Aufnehmen (KeyCapture, Hyprland steht
// solange in einer leeren Submap, Esc bricht ab) oder "Auf Tastatur wählen"
// (`pick`): der naechste Klick auf eine freie Taste der Vorschau speichert
// Ebene + Taste. Beides schreibt ueber Keybinds.qml in keybinds.json.
Item {
    id: editor

    implicitHeight: content.implicitHeight

    // ---- Zustand ----
    property string selectedId: ""
    // Ref der ersten Kombination des gewaehlten Befehls: ueberlebt eine
    // Umbenennung (die id ist die Beschreibung) und findet ein frisch
    // angelegtes Kuerzel nach dem naechsten Refresh (pendingRef)
    property string selectedRef: ""
    property string pendingRef: ""
    property int mask: 64
    // Laufendes "Auf Tastatur wählen": { mode, ref, title, payload } | null
    property var pick: null
    property string pickError: ""
    property bool adding: false
    property alias listQuery: list.queryText

    readonly property var selected: {
        const byRef = editor.selectedRef !== "" ? HyprBinds.commands.find(c => c.combos.some(x => x.ref === editor.selectedRef)) : null;
        return byRef ?? HyprBinds.commands.find(c => c.id === editor.selectedId) ?? null;
    }
    // Waehrend der Aufnahme folgt die Ebene den gehaltenen Modifiern
    readonly property int shownMask: capture.active ? capture.heldMask : editor.mask
    readonly property bool narrow: editor.width < 760
    readonly property real paneHeight: 480
    // Fuer Tests: Tastatur, Aufnahme, Liste
    readonly property alias keyboard: board
    readonly property alias captureItem: capture
    readonly property alias listItem: list
    // Oberste Ebene fuer Hinweise/Tooltips/Kontextmenue – KbIconButton findet
    // sie ueber die Elternkette (kbOverlay)
    readonly property Item kbOverlay: overlay

    // Canon "64:q" -> Belegung, einmal fuer alle Ebenen
    readonly property var index: {
        const out = {};
        for (const c of HyprBinds.commands)
            for (const combo of c.combos) {
                // Ein aktiver Bind hat Vorrang vor einem abgeschalteten auf derselben Taste
                const prev = out[combo.canon];
                if (prev && !prev.disabled && combo.disabled)
                    continue;
                out[combo.canon] = { id: c.id, ref: combo.ref, title: c.title, group: c.group, disabled: combo.disabled, changed: combo.changed, source: combo.source, unnamed: false, keys: combo.keys };
            }
        for (const u of HyprBinds.unnamed)
            if (!out[u.canon])
                out[u.canon] = { id: "", ref: "", title: "", group: "", disabled: false, changed: false, source: "config", unnamed: true, keys: [] };
        return out;
    }

    // Volltext je Befehl fuer die Suche: Titel/Text/Gruppe (deutsch und
    // uebersetzt), Tasten, Befehlstext
    readonly property var searchIndex: {
        const out = {};
        for (const c of HyprBinds.commands) {
            const parts = [c.title, I18n.tr(c.title), c.text, I18n.tr(c.text), c.group, I18n.tr(c.group), c.pluginName];
            for (const combo of c.combos)
                parts.push(combo.keysText, combo.keys.join(" "));
            const action = HyprBinds.actionOf(c);
            if (action)
                parts.push(action.text);
            out[c.id] = parts.join(" ").toLowerCase();
        }
        return out;
    }

    // Tasten des gewaehlten Befehls auf der gezeigten Ebene (Modifier links +
    // Taste); Kombinationen anderer Ebenen stehen im Display/Detail
    readonly property var litKeys: {
        const out = {};
        if (!editor.selected)
            return out;
        for (const combo of editor.selected.combos) {
            if (combo.modmask !== editor.shownMask)
                continue;
            out[combo.key] = true;
            if (combo.modmask & 64)
                out.super_l = true;
            if (combo.modmask & 4)
                out.control_l = true;
            if (combo.modmask & 8)
                out.alt_l = true;
            if (combo.modmask & 1)
                out.shift_l = true;
        }
        return out;
    }

    // keepMask: Ebene nicht wechseln (Klick auf eine Taste der Vorschau)
    function select(id: string, keepMask: bool): void {
        editor.pendingRef = "";
        editor.selectedId = id;
        const c = HyprBinds.commands.find(x => x.id === id);
        editor.selectedRef = c?.combos[0]?.ref ?? "";
        if (c && c.combos.length > 0 && !keepMask)
            editor.mask = c.combos[0].modmask;
        list.scrollTo(id);
    }

    // Auswahl ueber eine Ref (neues Kuerzel / Zusatztaste nach dem Speichern):
    // der Befehl erscheint erst mit dem naechsten Refresh
    function selectRef(ref: string): void {
        if (ref === "")
            return;
        editor.selectedRef = ref;
        editor.pendingRef = ref;
        editor.resolvePending();
    }

    function resolvePending(): void {
        if (editor.pendingRef === "")
            return;
        for (const c of HyprBinds.commands) {
            const combo = c.combos.find(x => x.ref === editor.pendingRef);
            if (combo) {
                editor.pendingRef = "";
                editor.selectedId = c.id;
                editor.mask = combo.modmask;
                list.scrollTo(c.id);
                return;
            }
        }
    }

    Connections {
        target: HyprBinds

        function onCommandsChanged(): void {
            editor.resolvePending();
        }
    }

    function startPick(mode: string, ref: string, title: string, payload: var): void {
        capture.cancel();
        editor.pick = { mode, ref, title, payload: payload ?? null };
        editor.pickError = "";
    }

    function cancelPick(): void {
        editor.pick = null;
        editor.pickError = "";
    }

    // Klick auf eine Taste der Vorschau
    function keyClicked(id: string): void {
        // Dieselbe Aufloesung wie die Vorschau (Zweitnamen: ß fuer backslash, kp_7 fuer kp_home)
        const info = board.infoFor(id);
        if (editor.pick) {
            if (!Layout.pickable(id)) {
                editor.pickError = I18n.tr("Diese Taste lässt sich nicht belegen");
                return;
            }
            // Die eigene Taste noch einmal waehlen ist kein Konflikt; abgeschaltete
            // Binds blockieren nicht (wie HyprBinds.conflict)
            const own = editor.pick.mode === "set" && info && info.ref === editor.pick.ref;
            if (info && !info.disabled && !own) {
                editor.pickError = I18n.tr("Schon belegt: %1").arg(info.unnamed ? I18n.tr("einem Bind ohne Beschreibung") : `${I18n.tr(info.group)} › ${I18n.tr(info.title)}`);
                return;
            }
            const plain = editor.mask & (64 | 4 | 8);
            if (plain === 0 && !Layout.standalone(id)) {
                editor.pickError = I18n.tr(editor.mask & 1 ? "Nur Shift reicht nicht – das braucht man zum Tippen" : "Ohne Super/Strg/Alt nur F-Tasten, Druck und Medientasten");
                return;
            }
            const error = capture.saveAs(editor.pick.mode, editor.pick.ref, Layout.keysText(editor.mask, id), editor.pick.payload);
            if (error !== "") {
                editor.pickError = error;
                return;
            }
            if (editor.pick.mode === "new")
                editor.closeForm();
            if (editor.pick.mode !== "set")
                editor.selectRef(capture.savedRef);
            editor.pick = null;
            editor.pickError = "";
            return;
        }
        if (info && !info.unnamed)
            editor.select(info.id, true);
    }

    // ---- Kontextmenue ----
    function copyText(text: string): void {
        if (Quickshell.clipboardText !== undefined)
            Quickshell.clipboardText = text;
        else
            Quickshell.execDetached(["wl-copy", text]);
    }

    // Zeilen fuer einen Befehl und (optional) eine seiner Kombinationen
    function menuRows(command: var, combo: var): var {
        const rows = [];
        const title = I18n.tr(command.title);
        if (command.runnable)
            rows.push({ title: I18n.tr("Ausführen"), icon: "play_arrow", action: () => HyprBinds.runCommand(command) });
        if (combo && combo.editable) {
            rows.push({ title: I18n.tr("Neu aufnehmen"), icon: "radio_button_checked", action: () => capture.start("set", combo.ref, title, null) });
            rows.push({ title: I18n.tr("Auf Tastatur wählen"), icon: "ads_click", action: () => editor.startPick("set", combo.ref, title, null) });
        }
        const config = command.combos.find(c => c.source === "config") ?? null;
        if (config && config.editable)
            rows.push({ title: I18n.tr("Weitere Taste aufnehmen"), icon: "add", action: () => capture.start("extra", config.ref, title, null) });
        if (combo && combo.editable)
            rows.push({
                title: combo.disabled ? I18n.tr("Einschalten") : I18n.tr("Ausschalten"),
                icon: combo.disabled ? "visibility" : "visibility_off",
                action: () => {
                    if (combo.disabled)
                        detail.actionError = HyprBinds.enableChecked(combo.ref);
                    else
                        Keybinds.setDisabled(combo.ref, true);
                }
            });
        if (combo && (combo.changed || combo.disabled) && (combo.source === "config" || combo.source === "plugin"))
            rows.push({ title: I18n.tr("Zurücksetzen"), icon: "undo", action: () => detail.actionError = HyprBinds.resetChecked(combo.ref) });
        if (command.source === "custom") {
            const ref = command.combos.find(c => c.source === "custom")?.ref ?? "";
            if (ref !== "")
                rows.push({ title: I18n.tr("Kürzel löschen"), icon: "delete", danger: true, confirm: true, action: () => Keybinds.removeCustom(ref) });
        }
        if (combo && combo.source === "extra")
            rows.push({ title: I18n.tr("Zusatztaste löschen"), icon: "delete", danger: true, confirm: true, action: () => Keybinds.removeCustom(combo.ref) });
        const origin = config ? HyprBinds.originOf(config.ref) : null;
        if (origin)
            rows.push({ title: I18n.tr("In Config öffnen"), icon: "open_in_new", action: () => Quickshell.execDetached(["kitty", "-e", "nvim", "+" + origin.line, origin.file]) });
        const action = HyprBinds.actionOf(command);
        if (action && action.text)
            rows.push({ title: I18n.tr("Befehl kopieren"), icon: "content_copy", action: () => editor.copyText(action.text) });
        return rows;
    }

    // Menue an einer Stelle des Overlays oeffnen; waehlt den Befehl mit aus
    function openContextMenu(command: var, combo: var, x: real, y: real): void {
        if (capture.active || !command)
            return;
        editor.select(command.id, true);
        const rows = editor.menuRows(command, combo);
        if (rows.length === 0)
            return;
        menu.rows = rows;
        const h = rows.length * 31 + menu.pad * 2;
        menu.x = Math.round(Math.max(0, Math.min(overlay.width - menu.width, x)));
        menu.y = Math.round(Math.max(0, Math.min(overlay.height - h, y)));
        menu.open = true;
    }

    function closeMenu(): void {
        menu.close();
    }

    function closeForm(): void {
        editor.adding = false;
        newName.text = "";
        newExec.text = "";
    }

    readonly property bool formReady: newName.text.trim() !== "" && newExec.text.trim() !== ""

    Component.onCompleted: HyprBinds.refresh()
    onVisibleChanged: if (visible) HyprBinds.refresh()
    Component.onDestruction: capture.cancel()

    // ---- Aufnahme ----
    KeyCapture {
        id: capture

        onFinished: {
            editor.closeForm();
            if (capture.savedRef.startsWith("custom:") || capture.savedRef.startsWith("extra:"))
                editor.selectRef(capture.savedRef);
            else if (editor.selected && editor.selected.combos.length > 0)
                editor.mask = editor.selected.combos[0].modmask;
        }
    }

    Connections {
        target: capture

        function onActiveChanged(): void {
            if (capture.active) {
                editor.pick = null;
                editor.pickError = "";
                catcher.forceActiveFocus();
            }
        }
    }

    Item {
        id: catcher

        focus: capture.active
        Keys.onPressed: e => capture.press(e)
        Keys.onReleased: e => capture.release(e)

        // Klick ins Fenster oder Fensterwechsel: Fokus zurueck, sonst kaeme
        // Esc nicht mehr an und Hyprland bliebe bis zum Timeout in der Submap
        onActiveFocusChanged: {
            if (!activeFocus && capture.active)
                Qt.callLater(() => {
                    if (capture.active)
                        catcher.forceActiveFocus();
                });
        }
    }

    // Hyprland-Profil: Aenderungen wirken nur unter "simple"
    property string profile: "simple"

    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/profile"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: editor.profile = text().trim()
    }

    Column {
        id: content

        width: parent.width
        spacing: 12
        bottomPadding: 6

        // ---- Hinweis: anderes Profil ----
        Rectangle {
            width: parent.width
            visible: editor.profile !== "" && editor.profile !== "simple"
            height: visible ? profileText.implicitHeight + 20 : 0
            radius: 10
            color: Colors.alpha(Colors.tertiary, 0.12)
            border.width: 1
            border.color: Colors.alpha(Colors.tertiary, 0.4)

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                text: "warning"
                color: Colors.tertiary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 18
            }

            Text {
                id: profileText

                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 40
                    rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                text: I18n.tr("Hyprland läuft mit dem Profil „%1“ – Änderungen hier wirken erst im Profil „simple“.").arg(editor.profile)
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }

        // ---- Banner: Aufnahme / Auf Tastatur wählen ----
        Rectangle {
            id: banner

            readonly property bool shown: capture.active || editor.pick !== null
            readonly property string error: capture.active ? capture.error : editor.pickError

            width: parent.width
            height: banner.shown ? 48 : 0
            visible: height > 0
            clip: true
            radius: 10
            color: Colors.alpha(Colors.primary, 0.1)
            border.width: 1
            border.color: Colors.alpha(Colors.primary, 0.45)

            Behavior on height {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }

            Text {
                id: bannerIcon

                anchors {
                    left: parent.left
                    leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                text: capture.active ? "radio_button_checked" : "ads_click"
                color: capture.active && capture.done === "" ? Colors.error : Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 18
            }

            // Gehaltene / gespeicherte Tasten
            Row {
                id: bannerCaps

                anchors {
                    left: bannerIcon.right
                    leftMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                visible: capture.active && (capture.done !== "" || capture.held.length > 0)
                spacing: 4

                Repeater {
                    model: capture.active ? (capture.done !== "" ? capture.done.split("+").map(p => {
                        const t = p.trim();
                        const names = { SUPER: "Super", CTRL: I18n.tr("Strg"), ALT: "Alt", SHIFT: "Shift" };
                        return names[t] ?? HyprBinds.keyLabel(t) ?? t;
                    }) : capture.held) : []

                    Keycap {
                        required property string modelData

                        anchors.verticalCenter: parent?.verticalCenter
                        text: I18n.tr(modelData)
                        accent: capture.done !== ""
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: capture.active && capture.done === "" && capture.held.length > 0
                    text: "+ …"
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 12
                }
            }

            // Anleitung – oder der Fehler an ihrer Stelle; laeuft nie unter den Knopf
            Text {
                anchors {
                    left: bannerCaps.visible ? bannerCaps.right : bannerIcon.right
                    leftMargin: 10
                    right: bannerCancel.left
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                text: {
                    if (banner.error !== "")
                        return banner.error;
                    if (capture.active)
                        return capture.done !== "" ? I18n.tr("„%1“ liegt jetzt auf").arg(capture.title)
                             : I18n.tr("Drücke die neue Kombination für „%1“ – Esc bricht ab").arg(capture.title);
                    if (editor.pick)
                        return I18n.tr("Klicke eine freie Taste für „%1“ – Super, Strg, Alt und Shift wechseln die Ebene").arg(editor.pick.title);
                    return "";
                }
                color: banner.error !== "" ? Colors.error : Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 12
                font.weight: banner.error !== "" ? Font.Medium : Font.Normal
                elide: Text.ElideRight
            }

            KbChip {
                id: bannerCancel

                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                size: 26
                icon: "close"
                label: I18n.tr("Abbrechen")
                onClicked: {
                    capture.cancel();
                    editor.cancelPick();
                }
            }
        }

        // ---- Tastatur ----
        VirtualKeyboard {
            id: board

            width: parent.width
            mask: editor.shownMask
            index: editor.index
            litKeys: editor.litKeys
            pick: editor.pick !== null
            interactive: !capture.active
            statusTitle: editor.selected ? `${I18n.tr(editor.selected.group)} › ${I18n.tr(editor.selected.title)}` : ""
            statusKeys: editor.selected?.combos[0]?.keys ?? []
            tipLayer: overlay
            onKeyClicked: id => editor.keyClicked(id)
            onModifierToggled: bit => editor.mask = editor.mask ^ bit
            onKeyContext: (id, item) => {
                const info = board.infoFor(id);
                if (!info || info.unnamed)
                    return;
                const c = HyprBinds.commands.find(x => x.id === info.id);
                if (!c)
                    return;
                const combo = c.combos.find(x => x.ref === info.ref) ?? c.combos[0];
                const p = overlay.mapFromItem(item, item.width / 2, item.height + 4);
                editor.openContextMenu(c, combo, p.x, p.y);
            }
        }

        // Legende der Lichtfarben
        Row {
            anchors.right: parent.right
            spacing: 14

            Repeater {
                model: [
                    { color: Colors.primary, label: "Config" },
                    { color: board.pluginLight, label: "Plugin" },
                    { color: board.customLight, label: "Eigenes" },
                    { color: board.changedLight, label: "Geändert" },
                    { color: board.unnamedLight, label: "Ohne Beschreibung" },
                    { color: Colors.error, label: "Aus" }
                ]

                Row {
                    id: legend

                    required property var modelData

                    spacing: 5

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 3.5
                        color: legend.modelData.color
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr(legend.modelData.label)
                        color: Colors.fgSurfaceVariant
                        font.family: Config.font
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ---- Eigenes Kuerzel ----
        Rectangle {
            width: parent.width
            height: editor.adding ? 48 : 0
            visible: height > 0
            enabled: !capture.active
            clip: true
            radius: 10
            color: Colors.alpha(Colors.fgSurface, 0.04)
            border.width: 1
            border.color: Colors.alpha(Colors.outline, 0.2)

            Behavior on height {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }

            Row {
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                KbField {
                    id: newName

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(140, parent.width * 0.26)
                    icon: "label"
                    placeholder: I18n.tr("Name")
                    onAccepted: newExec.input.forceActiveFocus()
                    onEscaped: editor.closeForm()
                }

                KbField {
                    id: newExec

                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - newName.width - newRecord.width - newPick.width - newClose.width - parent.spacing * 4
                    icon: "terminal"
                    placeholder: I18n.tr("Befehl, z.B. kitty btop")
                    mono: true
                    onAccepted: if (editor.formReady) newRecord.clicked()
                    onEscaped: editor.closeForm()
                }

                KbChip {
                    id: newRecord

                    anchors.verticalCenter: parent.verticalCenter
                    enabled: editor.formReady
                    icon: "radio_button_checked"
                    label: I18n.tr("Aufnehmen")
                    primary: true
                    onClicked: capture.start("new", "", newName.text.trim(), { title: newName.text.trim(), exec: newExec.text.trim() })
                }

                KbChip {
                    id: newPick

                    anchors.verticalCenter: parent.verticalCenter
                    enabled: editor.formReady
                    icon: "ads_click"
                    label: I18n.tr("Auf Tastatur wählen")
                    onClicked: editor.startPick("new", "", newName.text.trim(), { title: newName.text.trim(), exec: newExec.text.trim() })
                }

                KbIconButton {
                    id: newClose

                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    onClicked: editor.closeForm()
                }
            }
        }

        // ---- Liste + Details ----
        // Waehrend der Aufnahme gesperrt: ein Klick ins Suchfeld naehme dem
        // Faenger den Fokus (Esc braeche nicht mehr ab)
        Item {
            width: parent.width
            height: editor.narrow ? editor.paneHeight * 2 + 12 : editor.paneHeight
            enabled: !capture.active
            opacity: capture.active ? 0.5 : 1

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration }
            }

            CommandList {
                id: list

                anchors {
                    left: parent.left
                    top: parent.top
                }
                width: editor.narrow ? parent.width : Math.max(320, Math.round(parent.width * 0.4))
                height: editor.paneHeight
                selectedId: editor.selected?.id ?? ""
                searchIndex: editor.searchIndex
                adding: editor.adding
                onSelected: id => editor.select(id)
                onContextRequested: (id, x, y) => {
                    const c = HyprBinds.commands.find(k => k.id === id);
                    if (!c)
                        return;
                    const combo = c.combos.find(k => k.editable) ?? c.combos[0] ?? null;
                    const p = overlay.mapFromItem(list, x, y);
                    editor.openContextMenu(c, combo, p.x, p.y);
                }
                onAddToggled: {
                    editor.adding = !editor.adding;
                    if (editor.adding)
                        newName.input.forceActiveFocus();
                }
            }

            CommandDetail {
                id: detail

                anchors {
                    left: editor.narrow ? parent.left : list.right
                    right: parent.right
                    top: editor.narrow ? list.bottom : parent.top
                    leftMargin: editor.narrow ? 0 : 16
                    topMargin: editor.narrow ? 12 : 0
                }
                height: editor.paneHeight
                command: editor.selected
                capture: capture
                onPickRequested: (mode, ref, title, payload) => editor.startPick(mode, ref, title, payload)
            }
        }
    }

    // ================= Overlay: Hinweise, Tasten-Tooltip, Kontextmenue =================
    Item {
        id: overlay

        anchors.fill: parent
        z: 100

        property Item hintItem: null
        property string hintText: ""

        function showHint(item: Item, text: string): void {
            overlay.hintItem = item;
            overlay.hintText = text;
        }

        function hideHint(item: Item): void {
            if (overlay.hintItem === item)
                overlay.hintItem = null;
        }

        // Klick daneben schliesst das Menue (Rad geht durch)
        MouseArea {
            anchors.fill: parent
            visible: menu.open
            acceptedButtons: Qt.AllButtons
            onPressed: mouse => {
                menu.close();
                mouse.accepted = true;
            }
            onWheel: wheel => {
                menu.close();
                wheel.accepted = false;
            }
        }

        // Hinweis eines KbIconButton
        Rectangle {
            id: hintBox

            readonly property rect at: overlay.hintItem ? overlay.hintItem.mapToItem(overlay, 0, 0, overlay.hintItem.width, overlay.hintItem.height) : Qt.rect(0, 0, 0, 0)
            readonly property bool below: hintBox.at.y + hintBox.at.height + 4 + height <= overlay.height

            visible: overlay.hintItem !== null && overlay.hintText !== ""
            x: Math.round(Math.max(0, Math.min(overlay.width - width, hintBox.at.x + hintBox.at.width / 2 - width / 2)))
            y: Math.round(hintBox.below ? hintBox.at.y + hintBox.at.height + 4 : hintBox.at.y - height - 4)
            width: hintLabel.implicitWidth + 14
            height: 22
            radius: 6
            color: Colors.surfaceBright
            border.width: 1
            border.color: Colors.alpha(Colors.outline, 0.4)

            Text {
                id: hintLabel

                anchors.centerIn: parent
                text: overlay.hintText
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 11
            }
        }

        KbMenu {
            id: menu
        }
    }
}
