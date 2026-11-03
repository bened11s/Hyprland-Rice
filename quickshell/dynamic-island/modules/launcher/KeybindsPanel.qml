pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.hypr

// Tastenkuerzel-Uebersicht der Notch. Gleiche Schnittstelle wie PowerPanel
// (topOffset, cardRadius, inset, active -> outerWidth/outerHeight).
//
// Die Eintraege kommen live aus Hyprland (HyprBinds): jeder Bind mit
// Beschreibung "Gruppe|Text" in hypr/profiles/simple.lua landet hier, dazu
// die Kuerzel aktiver Plugins (Manifest `keybinds`) und eigene. Oben ein
// Suchfeld, darunter die Gruppen in drei Spalten (aufgefuellt nach Hoehe).
// Klick auf eine Zeile (oder Enter: erster Treffer der Suche) schliesst die
// Uebersicht und fuehrt den Bind aus.
//
// Bearbeiten (Stift oder Strg+E): Klick auf die Tasten nimmt eine neue
// Kombination auf (Hyprland steht solange in einer leeren Submap, siehe
// Keybinds.startCapture), das Auge schaltet einen Bind ab (ausserhalb des
// Bearbeitens dann ausgeblendet), der Pfeil setzt ihn zurueck. "Eigenes"
// legt ein Kuerzel mit Shell-Befehl an. Gespeichert wird in Keybinds.qml.
// Aufruf: SUPER+K, `>tasten`.
Item {
    id: panel

    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    readonly property real maxOuterHeight: searchRow.height + formRow.height + 1 + panel.maxBodyHeight + inset

    readonly property int columnCount: 3
    readonly property real padding: 18
    readonly property real columnGap: 22
    readonly property real rowHeight: 26
    readonly property real groupHeader: 30
    readonly property real groupGap: 14
    readonly property real maxBodyHeight: 760

    readonly property string query: search.text.trim().toLowerCase()

    // ---- Bearbeiten ----
    property bool editing: false
    // Formular fuer ein eigenes Kuerzel
    property bool adding: false
    // Laufende Aufnahme: Ref des Binds bzw. "new" fuer ein eigenes Kuerzel
    property string captureRef: ""
    property string captureTitle: ""
    property string captureError: ""
    // Gedrueckte Modifier waehrend der Aufnahme (Anzeige)
    property var captureHeld: []
    // Gespeichert, Hyprland bleibt bis zum Loslassen in der Submap
    property string captureDone: ""
    readonly property bool capturing: panel.captureRef !== ""

    function setEditing(on: bool): void {
        panel.cancelCapture();
        panel.editing = on;
        if (!on)
            panel.adding = false;
        search.forceActiveFocus();
    }

    function startCapture(ref: string, title: string): void {
        panel.captureRef = ref;
        panel.captureTitle = title;
        panel.captureError = "";
        panel.captureHeld = [];
        panel.captureDone = "";
        Keybinds.startCapture();
        catcher.forceActiveFocus();
    }

    function cancelCapture(): void {
        if (!panel.capturing)
            return;
        releaseWait.stop();
        panel.captureRef = "";
        panel.captureDone = "";
        Keybinds.stopCapture();
        if (panel.adding)
            nameInput.forceActiveFocus();
        else
            search.forceActiveFocus();
    }

    function finishCapture(): void {
        const wasNew = panel.captureRef === "new";
        panel.captureRef = "";
        panel.captureDone = "";
        Keybinds.stopCapture();
        if (wasNew) {
            panel.adding = false;
            nameInput.text = "";
            commandInput.text = "";
        }
        search.forceActiveFocus();
    }

    function captureKey(event: var): void {
        event.accepted = true;
        if (panel.captureDone !== "")
            return;
        const plainMods = Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier;
        if (event.key === Qt.Key_Escape && !(event.modifiers & plainMods)) {
            panel.cancelCapture();
            return;
        }
        const result = Keybinds.fromEvent(event);
        if (result.wait) {
            panel.captureHeld = panel.heldMods(event);
            return;
        }
        if (result.error) {
            panel.captureError = I18n.tr(result.error);
            return;
        }
        const conflict = HyprBinds.conflict(Keybinds.canonOf(result.keys), panel.captureRef);
        if (conflict !== "") {
            panel.captureError = I18n.tr("Schon belegt: %1").arg(conflict);
            return;
        }
        if (panel.captureRef === "new")
            Keybinds.addCustom(nameInput.text.trim(), commandInput.text.trim(), result.keys);
        else
            Keybinds.setKeys(panel.captureRef, result.keys);
        panel.captureDone = result.keys;
        panel.captureError = "";
        // Erst nach dem Loslassen aus der Submap: sonst loest das Loslassen
        // von SUPER noch das App-Menue (SUPER allein) aus
        releaseWait.restart();
    }

    function captureRelease(event: var): void {
        event.accepted = true;
        if (event.isAutoRepeat)
            return;
        // Beim Loslassen einer Modifier-Taste steht sie selbst je nach
        // Plattform noch in modifiers – hier herausrechnen
        const mods = panel.modsAfterRelease(event);
        if (panel.captureDone === "")
            panel.captureHeld = panel.modLabels(mods);
        else if (mods === 0)
            panel.finishCapture();
    }

    function ownMod(key: int): int {
        if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R)
            return Qt.MetaModifier;
        if (key === Qt.Key_Control)
            return Qt.ControlModifier;
        if (key === Qt.Key_Alt)
            return Qt.AltModifier;
        if (key === Qt.Key_Shift)
            return Qt.ShiftModifier;
        return 0;
    }

    function modsAfterRelease(event: var): int {
        const plain = Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier;
        return event.modifiers & plain & ~panel.ownMod(event.key);
    }

    function modLabels(mods: int): var {
        const out = [];
        if (mods & Qt.MetaModifier)
            out.push("Super");
        if (mods & Qt.ControlModifier)
            out.push(I18n.tr("Strg"));
        if (mods & Qt.AltModifier)
            out.push("Alt");
        if (mods & Qt.ShiftModifier)
            out.push("Shift");
        return out;
    }

    // Gedrueckt gehaltene Modifier inklusive der gerade gedrueckten Taste
    function heldMods(event: var): var {
        return panel.modLabels(event.modifiers | panel.ownMod(event.key));
    }

    // "SUPER + ALT + W" -> Tastenkappen wie in der Liste
    function capsOf(keys: string): var {
        const names = { SUPER: "Super", CTRL: I18n.tr("Strg"), ALT: "Alt", SHIFT: "Shift" };
        return keys.split("+").map(p => p.trim()).map(p => names[p] ?? HyprBinds.keyLabel(p));
    }

    // Nach Suchtext gefiltert: passt der Gruppenname, bleibt sie ganz, sonst
    // nur die passenden Zeilen. Abgeschaltete Tasten sieht man nur beim
    // Bearbeiten.
    readonly property var filtered: {
        const q = panel.query;
        const out = [];
        for (const group of HyprBinds.groups) {
            let entries = group.entries;
            if (!panel.editing)
                entries = entries.filter(e => !e.disabled)
                                 .map(e => e.combos.some(c => c.disabled)
                                      ? Object.assign({}, e, { combos: e.combos.filter(c => !c.disabled) }) : e);
            // Deutscher Text und Uebersetzung: die Suche trifft in beiden Sprachen
            if (q !== "" && !(group.name + " " + I18n.tr(group.name)).toLowerCase().includes(q))
                entries = entries.filter(e => (e.text + " " + I18n.tr(e.text) + " " + e.combos.map(c => c.keys.join(" ")).join(" "))
                                              .toLowerCase().includes(q));
            if (entries.length > 0)
                out.push({ name: group.name, entries });
        }
        return out;
    }

    // Spalten fuellen: jede Gruppe kommt in die bisher niedrigste Spalte.
    // Die Reihenfolge der Gruppen bleibt innerhalb einer Spalte erhalten.
    readonly property var columns: {
        const cols = [];
        const heights = [];
        for (let i = 0; i < panel.columnCount; i++) {
            cols.push([]);
            heights.push(0);
        }
        for (const group of panel.filtered) {
            const target = heights.indexOf(Math.min(...heights));
            cols[target].push(group);
            heights[target] += panel.groupHeight(group);
        }
        return cols;
    }

    // Was Enter ausloest: erster anklickbarer Treffer, nur waehrend gesucht wird
    readonly property var firstHit: {
        if (panel.query === "" || panel.editing)
            return null;
        for (const col of panel.columns)
            for (const group of col)
                for (const entry of group.entries)
                    if (entry.clickable)
                        return entry;
        return null;
    }

    // Erst zu, dann ausfuehren: "Schliessen" & Co. sollen das Fenster unter
    // der Notch treffen, und Shell-Kuerzel (SUPER+A ...) oeffnen sonst nur
    // kurz und werden vom Schliessen gleich wieder ueberdeckt
    function run(entry: var): void {
        if (!entry?.clickable)
            return;
        LauncherState.close();
        HyprBinds.run(entry);
    }

    function groupHeight(group: var): real {
        return panel.groupHeader + group.entries.length * panel.rowHeight + panel.groupGap;
    }

    readonly property real contentHeight: {
        let max = 0;
        for (const col of panel.columns)
            max = Math.max(max, col.reduce((sum, g) => sum + panel.groupHeight(g), 0));
        return max;
    }

    implicitWidth: 1080
    implicitHeight: searchRow.height + formRow.height + 1 + body.height

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset

    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    // Gilt bis kurz nach dem Aufklappen (siehe Gruppen-Loader unten)
    property bool opening: true

    Timer {
        running: panel.opening
        interval: 600
        onTriggered: panel.opening = false
    }
    Component.onDestruction: Keybinds.stopCapture()

    onActiveChanged: {
        if (active) {
            search.text = "";
            flick.contentY = 0;
            HyprBinds.refresh();
            search.forceActiveFocus();
        } else {
            panel.cancelCapture();
            panel.editing = false;
            panel.adding = false;
        }
    }

    function scrollBy(dy: real): void {
        const max = Math.max(0, flick.contentHeight - flick.height);
        const from = scrollAnim.running ? scrollAnim.to : flick.contentY;
        scrollAnim.stop();
        scrollAnim.from = flick.contentY;
        scrollAnim.to = Math.max(0, Math.min(max, from + dy));
        scrollAnim.start();
    }

    // Notbremse: Hyprland faellt nach 20 s selbst aus der Submap, die
    // Ansicht soll dann nicht weiter auf Tasten warten
    Timer {
        running: panel.capturing && panel.captureDone === ""
        interval: 19000
        onTriggered: panel.cancelCapture()
    }

    // Gespeichert, aber keine Loslassen-Meldung (Fokus weg o.ae.)
    Timer {
        id: releaseWait

        interval: 3000
        onTriggered: panel.finishCapture()
    }

    // ---- Suchzeile ----
    Item {
        id: searchRow

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 50

        Text {
            id: searchIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: panel.capturing ? "radio_button_checked" : panel.editing ? "edit" : "keyboard"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 20
            color: Colors.primary
        }

        TextInput {
            id: search

            anchors {
                left: searchIcon.right
                leftMargin: 12
                right: tools.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            visible: !panel.capturing
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 14
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            Keys.onEscapePressed: {
                if (panel.editing)
                    panel.setEditing(false);
                else
                    LauncherState.close();
            }
            Keys.onReturnPressed: panel.run(panel.firstHit)
            Keys.onEnterPressed: panel.run(panel.firstHit)
            Keys.onUpPressed: panel.scrollBy(-panel.rowHeight * 3)
            Keys.onDownPressed: panel.scrollBy(panel.rowHeight * 3)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageUp) {
                    panel.scrollBy(-flick.height * 0.8);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    panel.scrollBy(flick.height * 0.8);
                    event.accepted = true;
                } else if (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier)) {
                    panel.setEditing(!panel.editing);
                    event.accepted = true;
                }
            }

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: I18n.tr("Tastenkürzel durchsuchen")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font: search.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }

        // Aufnahme: nimmt alle Tasten, solange Hyprland in der leeren Submap steht
        Item {
            id: catcher

            anchors {
                left: searchIcon.right
                leftMargin: 12
                right: parent.right
                rightMargin: 18
                top: parent.top
                bottom: parent.bottom
            }
            visible: panel.capturing
            focus: false

            Keys.onPressed: event => panel.captureKey(event)
            Keys.onReleased: event => panel.captureRelease(event)

            Text {
                id: captureText

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                text: panel.captureDone !== "" ? I18n.tr("„%1“ liegt jetzt auf").arg(panel.captureTitle)
                    : I18n.tr("Neue Kombination für „%1“ drücken").arg(panel.captureTitle)
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 14
            }

            Row {
                anchors {
                    left: captureText.right
                    leftMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                spacing: 3

                Repeater {
                    model: panel.captureDone !== "" ? panel.capsOf(panel.captureDone) : panel.captureHeld

                    Keycap {
                        accent: panel.captureDone !== ""
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.captureDone === "" && panel.captureHeld.length > 0
                    text: "+ …"
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 12
                    leftPadding: 3
                }
            }

            Text {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                visible: panel.captureError !== ""
                text: panel.captureError
                color: Colors.error
                font.family: Config.font
                font.pixelSize: 12
            }

            // Klick daneben bricht ab
            TapHandler {
                onTapped: panel.cancelCapture()
            }
        }

        Row {
            id: tools

            anchors {
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            visible: !panel.capturing
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !panel.editing
                text: {
                    const n = panel.filtered.reduce((sum, g) => sum + g.entries.length, 0);
                    return n === 1 ? I18n.tr("1 Kürzel") : I18n.tr("%1 Kürzel").arg(n);
                }
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 12
                rightPadding: 6
            }

            ToolButton {
                visible: panel.editing
                icon: "add"
                label: I18n.tr("Eigenes")
                checked: panel.adding
                onClicked: {
                    panel.adding = !panel.adding;
                    if (panel.adding)
                        nameInput.forceActiveFocus();
                    else
                        search.forceActiveFocus();
                }
            }

            ToolButton {
                icon: panel.editing ? "check" : "edit"
                label: panel.editing ? I18n.tr("Fertig") : I18n.tr("Bearbeiten")
                checked: panel.editing
                onClicked: panel.setEditing(!panel.editing)
            }
        }
    }

    // ---- Eigenes Kuerzel: Name, Befehl, dann Taste ----
    Item {
        id: formRow

        anchors {
            top: searchRow.bottom
            left: parent.left
            right: parent.right
        }
        height: panel.adding && panel.editing ? 46 : 0
        visible: height > 0
        clip: true

        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                leftMargin: 14
                rightMargin: 14
            }
            height: 1
            color: Colors.alpha(Colors.outline, 0.2)
        }

        Row {
            anchors {
                left: parent.left
                leftMargin: 16
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            spacing: 10

            Field {
                id: nameField

                width: 220
                placeholder: I18n.tr("Name")
                icon: "label"
            }

            Field {
                id: commandField

                width: parent.width - nameField.width - recordButton.width - 2 * parent.spacing
                placeholder: I18n.tr("Befehl, z.B. kitty btop")
                icon: "terminal"
            }

            ToolButton {
                id: recordButton

                anchors.verticalCenter: parent.verticalCenter
                enabled: nameInput.text.trim() !== "" && commandInput.text.trim() !== ""
                icon: "keyboard"
                label: I18n.tr("Taste aufnehmen")
                checked: true
                onClicked: panel.startCapture("new", nameInput.text.trim())
            }
        }
    }

    // TextInputs der Felder (fuer Fokus und Werte)
    readonly property Item nameInput: nameField.input
    readonly property Item commandInput: commandField.input

    Rectangle {
        id: separator

        anchors {
            top: formRow.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.35)
    }

    // ---- Gruppen ----
    Item {
        id: body

        anchors {
            top: separator.bottom
            left: parent.left
            right: parent.right
        }
        height: panel.filtered.length === 0
            ? emptyHint.implicitHeight + 40
            : Math.min(panel.maxBodyHeight, panel.contentHeight + panel.padding)

        Flickable {
            id: flick

            anchors {
                fill: parent
                topMargin: panel.padding
                leftMargin: panel.padding
                rightMargin: panel.padding
            }
            clip: true
            contentWidth: width
            contentHeight: columnsRow.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;
                    panel.scrollBy(-delta * panel.rowHeight * 3);
                    event.accepted = true;
                }
            }

            NumberAnimation {
                id: scrollAnim

                target: flick
                property: "contentY"
                duration: 160
                easing.type: Easing.OutCubic
            }

            // Leere Spalten fallen weg, die uebrigen stehen mittig – bei
            // wenigen Treffern klebt sonst eine Gruppe am linken Rand
            Row {
                id: columnsRow

                x: Math.max(0, (flick.width - width) / 2)
                spacing: panel.columnGap

                Repeater {
                    model: panel.columns.filter(col => col.length > 0)

                    Column {
                        id: column

                        required property var modelData

                        width: (flick.width - panel.columnGap * (panel.columnCount - 1)) / panel.columnCount

                        Repeater {
                            model: column.modelData

                            // Beim Oeffnen asynchron: alle ~140 Zeilen am
                            // Stueck kosteten 48 ms, bevor die Karte ueberhaupt
                            // aufging. Die Hoehe steht vorher fest (groupHeight),
                            // die Karte springt also nicht. Beim Tippen wieder
                            // synchron, sonst flackerten die Treffer.
                            Loader {
                                id: groupLoader

                                required property var modelData

                                width: column.width
                                height: panel.groupHeight(groupLoader.modelData)
                                asynchronous: panel.opening

                                sourceComponent: GroupBlock {
                                    width: groupLoader.width
                                    modelData: groupLoader.modelData
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: emptyHint

            anchors.centerIn: parent
            visible: panel.filtered.length === 0
            text: HyprBinds.loaded ? I18n.tr("Keine Treffer") : I18n.tr("Lese Tastenkürzel…")
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 12
        }
    }

    // Eine Gruppe: Titel, darunter je Zeile Text links und Tasten rechts
    component GroupBlock: Column {
        id: block

        required property var modelData

        height: panel.groupHeight(block.modelData)

        Item {
            width: block.width
            height: panel.groupHeader

            Text {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    bottomMargin: 8
                }
                text: I18n.tr(block.modelData.name)
                color: Colors.primary
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        Repeater {
            model: block.modelData.entries

            Item {
                id: row

                required property var modelData

                readonly property bool clickable: row.modelData.clickable && !panel.editing
                readonly property bool isFirst: row.modelData === panel.firstHit
                readonly property bool editable: panel.editing && row.modelData.editable
                readonly property bool isCustom: row.modelData.source === "custom"
                // Zeile mit ihrer ersten Ref (an/aus und zuruecksetzen gelten
                // fuer alle Tasten der Zeile)
                readonly property var refs: row.modelData.combos.filter(c => c.editable).map(c => c.ref)

                width: block.width
                height: panel.rowHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -6
                    anchors.rightMargin: -6
                    radius: 6
                    color: rowArea.pressed ? Colors.alpha(Colors.primary, 0.22)
                         : row.isFirst ? Colors.alpha(Colors.primary, 0.14)
                         : Colors.alpha(Colors.fgSurface, 0.06)
                    opacity: (row.clickable || row.editable) && (rowHover.hovered || row.isFirst) ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 90 }
                    }
                }

                // Hover der ganzen Zeile – ein HoverHandler bleibt aktiv, auch
                // wenn die Maus auf einem Knopf darin steht (die MouseArea
                // gaebe das Hover an den Knopf ab, die Knoepfe verschwanden)
                HoverHandler {
                    id: rowHover

                    margin: 6
                }

                MouseArea {
                    id: rowArea

                    anchors.fill: parent
                    anchors.leftMargin: -6
                    anchors.rightMargin: -6
                    enabled: row.clickable || row.editable
                    hoverEnabled: true
                    cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (row.clickable) panel.run(row.modelData)
                }

                Text {
                    id: label

                    anchors {
                        left: parent.left
                        right: rowTools.left
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: I18n.tr(row.modelData.text)
                    color: Colors.fgSurface
                    opacity: row.modelData.disabled ? 0.4 : panel.editing && !row.modelData.editable ? 0.6 : 1
                    font.family: Config.font
                    font.pixelSize: 13
                    font.strikeout: row.modelData.disabled
                    elide: Text.ElideRight
                }

                // Beim Bearbeiten: Plugin-Herkunft, zuruecksetzen/loeschen, an/aus
                Row {
                    id: rowTools

                    anchors {
                        right: keys.left
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    visible: panel.editing
                    spacing: 2

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.source === "plugin"
                        text: "extension"
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 14
                        rightPadding: 2
                    }

                    IconButton {
                        visible: row.editable && !row.isCustom && row.modelData.changed
                        icon: "undo"
                        onClicked: row.refs.forEach(ref => Keybinds.reset(ref))
                    }

                    // Loeschen/Auge haben feste Plaetze und blenden nur ein –
                    // sonst rutschte der Pfeil daneben beim Ein-/Ausblenden
                    // unter der Maus weg
                    IconButton {
                        visible: row.editable && row.isCustom
                        shown: rowHover.hovered
                        icon: "delete"
                        danger: true
                        onClicked: row.refs.forEach(ref => Keybinds.removeCustom(ref))
                    }

                    IconButton {
                        visible: row.editable
                        shown: row.modelData.disabled || rowHover.hovered
                        icon: row.modelData.disabled ? "visibility_off" : "visibility"
                        onClicked: {
                            const off = !row.modelData.disabled;
                            row.refs.forEach(ref => Keybinds.setDisabled(ref, off));
                        }
                    }
                }

                Row {
                    id: keys

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    Repeater {
                        model: row.modelData.combos

                        Item {
                            id: combo

                            required property var modelData
                            required property int index

                            readonly property bool editable: panel.editing && combo.modelData.editable

                            anchors.verticalCenter: parent?.verticalCenter
                            width: comboRow.width
                            height: 24
                            opacity: combo.modelData.disabled ? 0.4 : 1

                            // Neu belegen: Rahmen um die Tasten beim Ueberfahren
                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -3
                                anchors.rightMargin: -3
                                radius: 7
                                color: comboArea.containsMouse ? Colors.alpha(Colors.primary, 0.14) : "transparent"
                                border.width: 1
                                border.color: Colors.alpha(Colors.primary, comboArea.containsMouse ? 0.7 : 0)
                                visible: combo.editable
                            }

                            Row {
                                id: comboRow

                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: combo.index > 0
                                    text: "/"
                                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                                    font.family: Config.font
                                    font.pixelSize: 11
                                    rightPadding: 3
                                }

                                Repeater {
                                    model: combo.modelData.keys

                                    Keycap {
                                        accent: combo.modelData.changed
                                    }
                                }
                            }

                            MouseArea {
                                id: comboArea

                                anchors.fill: parent
                                enabled: combo.editable
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.startCapture(combo.modelData.ref, I18n.tr(row.modelData.text))
                            }
                        }
                    }
                }
            }
        }
    }

    component Keycap: Rectangle {
        id: cap

        required property string modelData
        // Neu belegt / gerade aufgenommen
        property bool accent: false

        anchors.verticalCenter: parent?.verticalCenter
        width: Math.max(height, capText.implicitWidth + 12)
        height: 20
        radius: 5
        color: cap.accent ? Colors.alpha(Colors.primary, 0.16) : Colors.alpha(Colors.fgSurface, 0.07)
        border.width: 1
        border.color: cap.accent ? Colors.alpha(Colors.primary, 0.6) : Colors.alpha(Colors.outline, 0.45)

        Text {
            id: capText

            anchors.centerIn: parent
            text: cap.modelData
            color: cap.modelData === "Super" || cap.accent ? Colors.primary : Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 11
            font.weight: Font.Medium
        }
    }

    // Kleiner Symbolknopf in einer Zeile
    component IconButton: Item {
        id: ib

        property string icon
        property bool danger: false
        // false = Platz bleibt, Knopf unsichtbar und nicht klickbar
        property bool shown: true

        signal clicked

        anchors.verticalCenter: parent?.verticalCenter
        width: 22
        height: 22
        opacity: ib.shown ? 1 : 0
        enabled: ib.shown

        Behavior on opacity {
            NumberAnimation { duration: 90 }
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: ibArea.containsMouse ? Colors.alpha(ib.danger ? Colors.error : Colors.fgSurface, 0.12) : "transparent"
        }

        Text {
            anchors.centerIn: parent
            text: ib.icon
            color: ib.danger && ibArea.containsMouse ? Colors.error : Colors.fgSurfaceVariant
            font.family: "Material Symbols Outlined"
            font.pixelSize: 15
        }

        MouseArea {
            id: ibArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    // Knopf in der Suchzeile (Chip mit Symbol und Text)
    component ToolButton: Rectangle {
        id: tb

        property string icon
        property string label
        property bool checked: false

        signal clicked

        anchors.verticalCenter: parent?.verticalCenter
        width: tbRow.implicitWidth + 20
        height: 28
        radius: 14
        opacity: tb.enabled ? 1 : 0.45
        color: tb.checked ? Colors.alpha(Colors.primary, tbArea.containsMouse ? 0.28 : 0.18)
                          : Colors.alpha(Colors.fgSurface, tbArea.containsMouse ? 0.12 : 0.06)
        border.width: 1
        border.color: tb.checked ? Colors.alpha(Colors.primary, 0.5) : Colors.alpha(Colors.outline, 0.35)

        Row {
            id: tbRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.icon
                color: tb.checked ? Colors.primary : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.label
                color: tb.checked ? Colors.primary : Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: tbArea

            anchors.fill: parent
            enabled: tb.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }

    // Eingabefeld des Formulars
    component Field: Rectangle {
        id: field

        property string placeholder
        property string icon
        readonly property alias input: fieldInput

        function submit(): void {
            if (field === nameField)
                panel.commandInput.forceActiveFocus();
            else if (recordButton.enabled)
                recordButton.clicked();
        }

        anchors.verticalCenter: parent?.verticalCenter
        height: 30
        radius: 8
        color: Colors.alpha(Colors.fgSurface, 0.06)
        border.width: 1
        border.color: fieldInput.activeFocus ? Colors.alpha(Colors.primary, 0.6) : Colors.alpha(Colors.outline, 0.35)

        Text {
            id: fieldIcon

            anchors {
                left: parent.left
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: field.icon
            color: Colors.fgSurfaceVariant
            font.family: "Material Symbols Outlined"
            font.pixelSize: 15
        }

        TextInput {
            id: fieldInput

            anchors {
                left: fieldIcon.right
                leftMargin: 8
                right: parent.right
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 13
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            Keys.onEscapePressed: {
                panel.adding = false;
                search.forceActiveFocus();
            }
            Keys.onTabPressed: (field === nameField ? panel.commandInput : panel.nameInput).forceActiveFocus()
            Keys.onReturnPressed: field.submit()
            Keys.onEnterPressed: field.submit()

            Text {
                anchors.fill: parent
                visible: fieldInput.text === ""
                text: field.placeholder
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font: fieldInput.font
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
