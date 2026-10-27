pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.services.clipboard
import qs.modules.launcher.clipboard

// Zwischenablage-Verlauf der Notch. Gleiche Schnittstelle wie PowerPanel
// (topOffset, cardRadius, inset, active -> outerWidth/outerHeight).
//
// Oben ein Suchfeld, darunter Angeheftetes (eigene Kopien, ueberleben das
// Leeren) und der Verlauf aus cliphist, neueste zuerst. Enter/Klick kopiert
// den markierten Eintrag zurueck in die Ablage und schliesst. Rechts in der
// Zeile (nur beim Ueberfahren/Markieren) Anheften und Loeschen, dasselbe im
// Rechtsklick-Menue; Tab klappt den ganzen Text eines Eintrags auf.
// "Verlauf leeren" rechts im Kopf fragt mit einem zweiten Klick nach.
// Aufruf: SUPER+V, `>zwischenablage`.
Item {
    id: panel

    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    readonly property real maxOuterHeight: searchRow.height + 1 + panel.maxListHeight + 12 + inset

    readonly property real maxListHeight: 460
    readonly property real rowHeight: 36

    readonly property string query: search.text.trim().toLowerCase()

    // Markierte Zeile (Pfeiltasten, Maus-Hover zieht mit)
    property int current: 0
    // Aufgeklappter Texteintrag: Schluessel der Zeile und der ganze Text
    property string expandedKey: ""
    property string expandedText: ""
    property bool expandedTruncated: false
    // Rechtsklick-Menue: Zeile (-1 = zu) und Position im Panel
    property int menuIndex: -1
    property real menuX: 0
    property real menuY: 0
    // "Verlauf leeren" wartet auf den zweiten Klick
    property bool wipeArmed: false
    // Kopiert gerade – nach dem Rueckruf schliessen
    property bool copying: false

    // Solange die Liste offen ist, laedt der Dienst beim Oeffnen frisch und
    // beobachtet die Ablage
    DemandRequest {
        demand: Clipboard.demand
        active: panel.active
    }

    // Angeheftetes zuerst, dann der Verlauf – beides nach Suchtext gefiltert.
    // Bilder treffen auf "bild"/"image" und ihr Format, sonst nur ohne Suche.
    readonly property var rows: {
        const q = panel.query;
        const out = [];
        const matches = r => q === "" || (r.kind === "text"
            ? r.full.toLowerCase().includes(q)
            : ("bild image " + (r.fmt ?? "")).includes(q));
        for (const p of Clipboard.pins) {
            const full = p.text ?? "";
            const r = { key: "p" + p.key, section: "pin", kind: p.kind, id: "", pinKey: p.key,
                        text: full.split("\n")[0], full, pinned: true, path: p.path ?? "",
                        w: 0, h: 0, size: "", fmt: "" };
            if (matches(r))
                out.push(r);
        }
        for (const e of Clipboard.entries) {
            const r = { key: "e" + e.id, section: "hist", kind: e.kind, id: e.id, pinKey: "",
                        text: e.text ?? "", full: e.text ?? "", pinned: e.pinned === true, path: "",
                        w: e.w ?? 0, h: e.h ?? 0, size: e.size ?? "", fmt: e.fmt ?? "" };
            if (matches(r))
                out.push(r);
        }
        return out;
    }
    readonly property bool hasPins: panel.rows.length > 0 && panel.rows[0].section === "pin"
    readonly property var currentRow: panel.rows[panel.current] ?? null

    implicitWidth: 620
    implicitHeight: searchRow.height + 1 + listWrapper.implicitHeight

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

    onActiveChanged: {
        if (active) {
            search.text = "";
            panel.current = 0;
            list.contentY = 0;
            search.forceActiveFocus();
        } else {
            panel.closeMenu();
            panel.wipeArmed = false;
            panel.expandedKey = "";
            panel.copying = false;
        }
    }

    onQueryChanged: panel.select(0)
    onRowsChanged: {
        if (panel.current >= panel.rows.length)
            panel.select(Math.max(0, panel.rows.length - 1));
        if (panel.menuIndex >= panel.rows.length)
            panel.closeMenu();
    }

    // Nach dem Zurueckkopieren schliessen
    Connections {
        target: Clipboard

        function onCopied(): void {
            if (panel.copying)
                LauncherState.close();
        }

        // Kopieren fehlgeschlagen – nicht auf den Rueckruf warten
        function onLastErrorChanged(): void {
            if (Clipboard.lastError !== "")
                panel.copying = false;
        }
    }

    Timer {
        id: disarmWipe

        interval: 3000
        onTriggered: panel.wipeArmed = false
    }

    // ---- Aktionen ----
    function select(index: int): void {
        panel.current = index;
        if (index >= 0 && index < panel.rows.length)
            list.positionViewAtIndex(index, ListView.Contain);
    }

    function move(delta: int): void {
        const count = panel.rows.length;
        if (count === 0)
            return;
        panel.select((panel.current + delta + count) % count);
    }

    function copyRow(row: var): void {
        if (!row || panel.copying)
            return;
        panel.copying = true;
        if (row.section === "pin")
            Clipboard.copyPin(row.pinKey);
        else
            Clipboard.copy(row.id);
    }

    function removeRow(row: var): void {
        if (!row)
            return;
        if (row.key === panel.expandedKey)
            panel.expandedKey = "";
        if (row.section === "pin")
            Clipboard.unpin(row.pinKey);
        else
            Clipboard.remove(row.id);
    }

    function togglePinRow(row: var): void {
        if (!row)
            return;
        if (row.section === "pin")
            Clipboard.unpin(row.pinKey);
        else
            Clipboard.togglePin(row.id);
    }

    function toggleExpand(row: var): void {
        if (!row || row.kind !== "text")
            return;
        if (panel.expandedKey === row.key) {
            panel.expandedKey = "";
            return;
        }
        panel.expandedKey = row.key;
        panel.expandedTruncated = false;
        if (row.section === "pin") {
            panel.expandedText = row.full;
            return;
        }
        panel.expandedText = row.text;
        Clipboard.fullText(row.id, (text, truncated) => {
            if (panel.expandedKey !== row.key)
                return;
            panel.expandedText = text;
            panel.expandedTruncated = truncated;
        });
    }

    function openMenu(index: int, x: real, y: real): void {
        panel.wipeArmed = false;
        panel.select(index);
        panel.menuX = x;
        panel.menuY = y;
        panel.menuIndex = index;
    }

    function closeMenu(): void {
        panel.menuIndex = -1;
    }

    function wipe(): void {
        if (panel.wipeArmed) {
            panel.wipeArmed = false;
            panel.expandedKey = "";
            Clipboard.wipe();
        } else {
            panel.closeMenu();
            panel.wipeArmed = true;
            disarmWipe.restart();
        }
        search.forceActiveFocus();
    }

    function scrollBy(dy: real): void {
        const max = Math.max(0, list.contentHeight - list.height);
        const from = scrollAnim.running ? scrollAnim.to : list.contentY;
        scrollAnim.stop();
        scrollAnim.from = list.contentY;
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
            text: "content_paste"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 19
            color: Colors.fgSurfaceVariant
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

            Keys.onEscapePressed: {
                if (panel.menuIndex >= 0)
                    panel.closeMenu();
                else if (panel.wipeArmed)
                    panel.wipeArmed = false;
                else
                    LauncherState.close();
            }
            Keys.onUpPressed: panel.move(-1)
            Keys.onDownPressed: panel.move(1)
            Keys.onReturnPressed: panel.copyRow(panel.currentRow)
            Keys.onEnterPressed: panel.copyRow(panel.currentRow)
            Keys.onTabPressed: panel.toggleExpand(panel.currentRow)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Delete && (search.text === "" || (event.modifiers & Qt.ShiftModifier))) {
                    panel.removeRow(panel.currentRow);
                    event.accepted = true;
                } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                    panel.togglePinRow(panel.currentRow);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    panel.move(-8);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    panel.move(8);
                    event.accepted = true;
                }
            }

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: I18n.tr("Suchen…")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font: search.font
                verticalAlignment: Text.AlignVCenter
            }
        }

        Row {
            id: tools

            anchors {
                right: parent.right
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.wipeArmed ? I18n.tr("Verlauf leeren?")
                    : Clipboard.entries.length === 1 ? I18n.tr("1 Eintrag")
                    : I18n.tr("%1 Einträge").arg(Clipboard.entries.length)
                visible: panel.wipeArmed || Clipboard.loaded
                color: panel.wipeArmed ? Colors.error : Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 12
                font.weight: panel.wipeArmed ? Font.DemiBold : Font.Normal
                rightPadding: 4
            }

            ClipIconButton {
                anchors.verticalCenter: parent.verticalCenter
                shown: Clipboard.entries.length > 0
                icon: panel.wipeArmed ? "check" : "delete_sweep"
                danger: true
                armed: panel.wipeArmed
                onClicked: panel.wipe()
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

    // ---- Liste ----
    Item {
        id: listWrapper

        anchors {
            top: separator.bottom
            left: parent.left
            right: parent.right
        }
        // Leer richtet sich die Hoehe nach dem Hinweis (siehe LauncherPanel)
        implicitHeight: panel.rows.length === 0
            ? emptyHint.implicitHeight + 24
            : Math.min(panel.maxListHeight, list.contentHeight + 12)

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: 6
            clip: true
            spacing: 2
            model: panel.rows
            reuseItems: true
            boundsBehavior: Flickable.StopAtBounds
            // Kein Highlight-Nachfuehren (siehe LauncherPanel.qml)
            highlightFollowsCurrentItem: false
            currentIndex: panel.current

            // Abschnitte nur, wenn es Angeheftetes gibt – sonst ist der
            // Verlauf die ganze Liste
            section.property: panel.hasPins ? "section" : ""
            section.delegate: Item {
                id: sectionHeader

                required property string section

                width: ListView.view.width
                height: 24

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        bottom: parent.bottom
                        bottomMargin: 4
                    }
                    text: sectionHeader.section === "pin" ? I18n.tr("Angeheftet") : I18n.tr("Verlauf")
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            // Mausrad: weich animiert, drei Zeilen pro Rastung
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

                target: list
                property: "contentY"
                duration: Appearance.fadeDuration
                easing.type: Easing.OutCubic
            }

            delegate: ClipRow {
                width: ListView.view.width
                selected: panel.current === index
                expanded: panel.expandedKey === modelData.key
                fullText: expanded ? panel.expandedText : ""
                truncated: expanded && panel.expandedTruncated

                onActivated: panel.copyRow(modelData)
                onHovered: if (panel.menuIndex < 0) panel.current = index
                onPinToggled: panel.togglePinRow(modelData)
                onRemoved: panel.removeRow(modelData)
                onContextRequested: (x, y) => {
                    const pos = mapToItem(panel, x, y);
                    panel.openMenu(index, pos.x, pos.y);
                }
            }
        }

        Text {
            id: emptyHint

            anchors.centerIn: parent
            visible: panel.rows.length === 0
            text: Clipboard.lastError !== "" ? Clipboard.lastError
                : !Clipboard.loaded ? ""
                : panel.query !== "" ? I18n.tr("Keine Treffer")
                : I18n.tr("Keine Einträge")
            color: Clipboard.lastError !== "" ? Colors.error : Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 12
        }
    }

    // ---- Rechtsklick-Menue ----
    // Klick daneben schliesst
    MouseArea {
        anchors.fill: parent
        visible: panel.menuIndex >= 0
        acceptedButtons: Qt.AllButtons
        onPressed: panel.closeMenu()
        onWheel: wheel => wheel.accepted = true
    }

    ClipMenu {
        id: menu

        readonly property var row: panel.rows[panel.menuIndex] ?? null

        open: panel.menuIndex >= 0
        x: Math.max(0, Math.min(panel.width - width, panel.menuX))
        y: Math.max(0, Math.min(panel.height - height, panel.menuY))
        rows: {
            const r = menu.row;
            if (!r)
                return [];
            const out = [];
            if (r.kind === "text")
                out.push({ title: panel.expandedKey === r.key ? I18n.tr("Einklappen") : I18n.tr("Ganz anzeigen"),
                           icon: panel.expandedKey === r.key ? "unfold_less" : "unfold_more",
                           action: () => { panel.closeMenu(); panel.toggleExpand(r); } });
            out.push({ title: r.pinned ? I18n.tr("Lösen") : I18n.tr("Anheften"),
                       icon: r.pinned ? "keep_off" : "keep",
                       action: () => { panel.closeMenu(); panel.togglePinRow(r); } });
            if (r.section !== "pin")
                out.push({ title: I18n.tr("Löschen"), icon: "delete", danger: true,
                           action: () => { panel.closeMenu(); panel.removeRow(r); } });
            return out;
        }
    }
}
