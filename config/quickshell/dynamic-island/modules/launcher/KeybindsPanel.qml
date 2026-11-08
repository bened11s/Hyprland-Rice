pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.hypr
import qs.modules.settings

// Tastenkuerzel-Uebersicht der Notch. Gleiche Schnittstelle wie PowerPanel
// (topOffset, cardRadius, inset, active -> outerWidth/outerHeight).
//
// Die Eintraege kommen live aus Hyprland (HyprBinds): jeder Bind mit
// Beschreibung "Gruppe|Text" in hypr/profiles/simple.lua landet hier, dazu
// die Kuerzel aktiver Plugins (Manifest `keybinds`) und eigene. Oben ein
// Suchfeld, darunter die Gruppen in drei Spalten (aufgefuellt nach Hoehe).
// Klick auf eine Zeile (oder Enter: erster Treffer der Suche) schliesst die
// Uebersicht und fuehrt den Bind aus. Abgeschaltete Kuerzel fehlen.
//
// Nur Suchen und Ausfuehren – belegt, an/aus, eigene Kuerzel macht die
// Einstellungsseite Tastenkürzel (KeybindsEditor) mit Tastatur-Vorschau:
// "Bearbeiten" (oder Strg+E) schliesst die Notch und oeffnet sie.
// Aufruf: SUPER+K, `>tasten`.
Item {
    id: panel

    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    readonly property real maxOuterHeight: searchRow.height + 1 + panel.maxBodyHeight + inset

    readonly property int columnCount: 3
    readonly property real padding: 18
    readonly property real columnGap: 22
    readonly property real rowHeight: 26
    readonly property real groupHeader: 30
    readonly property real groupGap: 14
    readonly property real maxBodyHeight: 760

    readonly property string query: search.text.trim().toLowerCase()

    // Zur Einstellungsseite: erst die Notch zu, sonst liegt sie ueber dem Fenster
    function openEditor(): void {
        LauncherState.close();
        SettingsState.openPage("keybinds", {});
    }

    // Nach Suchtext gefiltert: passt der Gruppenname, bleibt sie ganz, sonst
    // nur die passenden Zeilen. Abgeschaltete Tasten bleiben draussen.
    readonly property var filtered: {
        const q = panel.query;
        const out = [];
        for (const group of HyprBinds.groups) {
            let entries = group.entries.filter(e => !e.disabled)
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
        if (panel.query === "")
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
    implicitHeight: searchRow.height + 1 + body.height

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

    onActiveChanged: {
        if (active) {
            search.text = "";
            flick.contentY = 0;
            HyprBinds.refresh();
            search.forceActiveFocus();
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
            text: "keyboard"
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
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 14
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            Keys.onEscapePressed: LauncherState.close()
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
                    panel.openEditor();
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

        Row {
            id: tools

            anchors {
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
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
                icon: "edit"
                label: I18n.tr("Bearbeiten")
                onClicked: panel.openEditor()
            }
        }
    }

    Rectangle {
        id: separator

        anchors {
            top: searchRow.bottom
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

                readonly property bool clickable: row.modelData.clickable
                readonly property bool isFirst: row.modelData === panel.firstHit

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
                    opacity: row.clickable && (rowArea.containsMouse || row.isFirst) ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 90 }
                    }
                }

                MouseArea {
                    id: rowArea

                    anchors.fill: parent
                    anchors.leftMargin: -6
                    anchors.rightMargin: -6
                    enabled: row.clickable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.run(row.modelData)
                }

                Text {
                    id: label

                    anchors {
                        left: parent.left
                        right: keys.left
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: I18n.tr(row.modelData.text)
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
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

                        Row {
                            id: combo

                            required property var modelData
                            required property int index

                            anchors.verticalCenter: parent?.verticalCenter
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
                    }
                }
            }
        }
    }

    component Keycap: Rectangle {
        id: cap

        required property string modelData
        // Neu belegt (Einstellungen)
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
}
