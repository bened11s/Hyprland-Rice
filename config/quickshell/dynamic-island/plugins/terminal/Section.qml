pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.services.plugins
import qs.modules.services.wallpaper
import qs.modules.settings

import qs
import qs.modules.services.config

// Sektion des Terminal-Plugins in der Wallpaper-Auswahl (Manifest
// panels.wallpaper): links die fastfetch-Vorschau des Looks, den das
// markierte lokale Bild bekaeme (TerminalPreview.qml, echte Ausgabe von
// looks.py), rechts Look und Herkunft, darunter die Zeilen Bild / Ordner /
// Groesse (Popover-Listen) und Bearbeiten (Looks-Editor im Einstellungsfenster).
//
// Welcher Look gilt, rechnet WallManager.lookFor wie __terminal_look.fish im
// Modus "wallpaper"; die beiden Plugin-Schalter davor rechnet die Sektion
// nach: `theme` aus = immer Vocaloid, `folderLooks` aus = immer Schema.
// "scheme" zeigt looks.py aus dem AKTUELLEN Schema – fuer ein noch nicht
// gesetztes Bild also nur eine Naeherung.
//
// Vertrag mit dem Panel (plugins/README.md, "Sektionen"). Tasten, solange die
// Sektion die Tastatur hat (host.focused):
//   Esc               Popover zu, sonst Auswahl schliessen
//   Hoch/Runter       im Popover blaettern, sonst zurueck in die lokale Reihe
//   Tab, Shift+Tab    Zeile wechseln
//   Enter             Zeile oeffnen bzw. Eintrag uebernehmen
//   Links/Rechts      im lokalen Wallpaper weiterblaettern (host.moveBy)
//   Strg+Links/Rechts Stil des markierten lokalen Bilds (wie im Panel)
//   Strg+W            Sektion zu (bzw. naechste)
Item {
    id: section

    required property var plugin
    required property var host

    readonly property var svc: section.plugin.main
    readonly property bool focused: section.host.focused

    implicitHeight: 220

    // ---- Welcher Look ----
    readonly property string path: section.host.currentPath ?? ""
    readonly property string key: WallManager.keyFor(section.path)
    readonly property string folder: WallManager.folderOf(section.path)
    readonly property string folderName: section.folder.split("/").pop()
    readonly property bool themeOn: section.plugin.settings.theme === true
    readonly property bool foldersOn: section.plugin.settings.folderLooks === true
    readonly property bool looksActive: section.themeOn && section.foldersOn

    // { id, source } – source wie WallManager.lookFor, dazu "theme-aus" und
    // "ordner-aus" fuer die Plugin-Schalter
    readonly property var look: {
        if (!section.themeOn)
            return { id: "miku", source: "theme-aus" };
        if (!section.foldersOn)
            return { id: "scheme", source: "ordner-aus" };
        return section.path !== "" ? WallManager.lookFor(section.path) : { id: "scheme", source: "schema" };
    }
    readonly property string lookId: section.look.id

    // Eigene Zuordnungen von Bild und Ordner ("" = keine)
    readonly property string ownImage: {
        const own = WallManager.assignments[section.key] ?? "";
        return section.key !== "" && own !== "" && WallManager.exists(own) ? own : "";
    }
    readonly property string ownFolder: {
        const own = WallManager.assignments[WallManager.folderKey(section.folder)] ?? "";
        return section.folder !== "" && own !== "" && WallManager.exists(own) ? own : "";
    }

    // Looks-Editor (Plugin-Seite "terminal/looks"), nur solange es sie gibt
    readonly property string editorSection: Plugins.pageSection("terminal/looks")
    readonly property bool editorAvailable: Plugins.pageFor(section.editorSection) !== null
    // Zu bearbeiten: der geltende Look; beim Schema stattdessen einen fuer
    // den Ordner anlegen
    readonly property string editLook: section.lookId !== "scheme" ? section.lookId : ""

    function lookTitle(id: string): string {
        if (id === "scheme")
            return I18n.tr("Farbschema");
        return I18n.tr(WallManager.lookInfo(id)?.title ?? section.svc?.looks.find(l => l.id === id)?.title ?? id);
    }

    function sourceLabel(source: string): string {
        return I18n.tr(({
            bild: "für dieses Bild", ordner: "vom Ordner", name: "Ordner heißt wie der Look", schema: "kein eigener Look",
            "theme-aus": "„An Theme anpassen“ ist aus", "ordner-aus": "Ordner-Looks sind aus"
        })[source] ?? source);
    }

    // Logo-Karte eines Looks (Dienst zuerst, der kennt auch frisch angelegte)
    function cardFor(id: string): string {
        return section.svc?.looks.find(l => l.id === id)?.card || WallManager.lookInfo(id)?.card || "";
    }

    // Karte der Vorschau: beim Schema das Wallpaper selbst (3:4-Ausschnitt)
    readonly property string card: {
        if (section.size === "mini")
            return "";
        if (section.lookId !== "scheme")
            return section.cardFor(section.lookId);
        if (section.path === "")
            return "";
        return Wallpapers.thumbFor(section.key) || section.path;
    }

    function openEditor(): void {
        if (!section.editorAvailable)
            return;
        if (section.editLook !== "")
            SettingsState.openPage(section.editorSection, { look: section.editLook });
        else if (section.folder !== "")
            SettingsState.openPage(section.editorSection, { create: section.folderName });
        else
            return;
        section.host.close();
    }

    // ---- Vorschau ----
    readonly property var sizes: ["config", "compact", "mini"]
    readonly property var budgets: ({ config: [64, 23], compact: [50, 19], mini: [32, 7] })
    property string size: "compact"
    readonly property var budget: section.budgets[section.size]

    // Ergebnisse je "look/size"; die Sektion lebt nur aufgeklappt, der
    // Cache also auch – zum Blaettern reicht das
    property var previews: ({})
    readonly property string previewKey: section.lookId + "/" + section.size
    property var preview: null
    readonly property bool previewStale: section.previews[section.previewKey] === undefined

    function requestPreview(): void {
        const key = section.previewKey;
        const cached = section.previews[key];
        if (cached !== undefined) {
            section.preview = cached;
            return;
        }
        if (!section.svc)
            return;
        const id = section.lookId;
        const size = section.size;
        section.svc.call("preview", [size, "--raw", id], r => {
            const result = r.ok ? r : {
                lines: [[{ t: r.error ?? I18n.tr("Fehler"), fg: Colors.error.toString() }]],
                width: 0, height: 1, budget: { cols: section.budgets[size][0], rows: section.budgets[size][1] }, failed: true
            };
            const next = Object.assign({}, section.previews);
            next[id + "/" + size] = result;
            section.previews = next;
            if (section.previewKey === id + "/" + size)
                section.preview = result;
        });
    }

    Timer {
        id: previewTimer

        interval: 150
        onTriggered: section.requestPreview()
    }

    onPreviewKeyChanged: {
        const cached = section.previews[section.previewKey];
        if (cached !== undefined)
            section.preview = cached;
        else
            previewTimer.restart();
    }

    Component.onCompleted: {
        WallManager.ensureLoaded();
        section.svc?.refresh();
        section.requestPreview();
        if (section.focused)
            section.focusIn();
    }

    // ---- Tastatur ----
    // Die Zeilen rechts; `cursor` ist die markierte (nur sichtbar, solange
    // die Sektion die Tastatur hat)
    readonly property var rows: {
        const out = [
            { key: "bild", label: I18n.tr("Dieses Bild"),
              value: section.ownImage !== "" ? section.lookTitle(section.ownImage) : I18n.tr("Automatisch"),
              enabled: section.looksActive && section.key !== "", menu: true }
        ];
        if (section.folder !== "")
            out.push({ key: "ordner", label: I18n.tr("Ordner „%1“").arg(section.folderName),
                       value: section.ownFolder !== "" ? section.lookTitle(section.ownFolder) : I18n.tr("Automatisch"),
                       enabled: section.looksActive, menu: true });
        out.push({ key: "groesse", label: I18n.tr("Größe"), value: section.size, enabled: true, menu: true });
        if (section.editorAvailable && (section.editLook !== "" || section.folder !== ""))
            out.push({ key: "edit", label: section.editLook !== "" ? I18n.tr("Bearbeiten") : I18n.tr("Eigenen Look anlegen"),
                       value: "", enabled: true, menu: false });
        return out;
    }
    property int cursor: 0

    function activate(key: string): void {
        if (key === "edit")
            section.openEditor();
        else
            section.openMenu(key);
    }

    // forceActiveFocus greift nur bei sichtbarem Item – beim Aufklappen
    // blendet das Panel die Sektion erst ein, deshalb notfalls warten
    property bool wantFocus: false

    function focusIn(): void {
        section.wantFocus = true;
        section.applyFocus();
    }

    function applyFocus(): void {
        if (section.wantFocus && keys.visible) {
            section.wantFocus = false;
            keys.forceActiveFocus();
        }
    }

    onFocusedChanged: {
        if (section.focused)
            section.focusIn();
        else {
            section.wantFocus = false;
            section.closeMenu();
        }
    }

    // ---- Popover ----
    // "" = zu, sonst "bild" | "ordner" | "groesse"
    property string menu: ""
    property int menuCursor: 0

    function openMenu(kind: string): void {
        const row = section.rows.find(r => r.key === kind);
        if (!row || !row.enabled)
            return;
        section.menu = kind;
        section.menuCursor = Math.max(0, section.menuRows.findIndex(r => r.current));
    }

    function closeMenu(): void {
        section.menu = "";
    }

    readonly property string menuTitle: section.menu === "bild" ? I18n.tr("Dieses Bild")
        : section.menu === "ordner" ? I18n.tr("Ordner „%1“").arg(section.folderName)
        : section.menu === "groesse" ? I18n.tr("Größe") : ""

    // Eintraege: { title, desc, card, current, action }
    readonly property var menuRows: {
        const m = section.menu;
        if (m === "groesse")
            return section.sizes.map(s => ({
                title: s, desc: `${section.budgets[s][0]}×${section.budgets[s][1]}`, card: "",
                current: section.size === s,
                action: () => { section.size = s; section.closeMenu(); }
            }));
        if (m !== "bild" && m !== "ordner")
            return [];
        const forFolder = m === "ordner";
        const key = forFolder ? WallManager.folderKey(section.folder) : section.key;
        // Was "Automatisch" ergibt: fuer das Bild der Ordner, fuer den Ordner sein Name
        const fallback = forFolder
            ? (WallManager.conventionLook(section.folder) !== ""
                ? { id: WallManager.conventionLook(section.folder), source: "name" }
                : { id: "scheme", source: "schema" })
            : WallManager.folderLookFor(section.folder);
        const own = forFolder ? section.ownFolder : section.ownImage;
        const out = [{
            title: I18n.tr("Automatisch"), desc: section.lookTitle(fallback.id) + " · " + section.sourceLabel(fallback.source),
            card: section.cardFor(fallback.id), current: own === "",
            action: () => { WallManager.setLook(key, ""); section.closeMenu(); }
        }];
        for (const l of WallManager.looks)
            out.push({
                title: I18n.tr(l.title), desc: "", card: section.cardFor(l.id), current: own === l.id,
                action: () => { WallManager.setLook(key, l.id); section.closeMenu(); }
            });
        return out;
    }

    // ---- Tastatur-Senke ----
    // Die Sektion hat kein Suchfeld; dieses Item nimmt die Tastatur
    Item {
        id: keys

        anchors.fill: parent
        onVisibleChanged: section.applyFocus()

        Keys.onEscapePressed: {
            if (section.menu !== "")
                section.closeMenu();
            else
                section.host.close();
        }
        Keys.onUpPressed: {
            if (section.menu !== "")
                section.menuCursor = (section.menuCursor - 1 + section.menuRows.length) % section.menuRows.length;
            else
                section.host.leaveFocus();
        }
        Keys.onDownPressed: {
            if (section.menu !== "")
                section.menuCursor = (section.menuCursor + 1) % section.menuRows.length;
            else
                section.host.leaveFocus();
        }
        function enter(): void {
            if (section.menu !== "")
                section.menuRows[section.menuCursor]?.action();
            else
                section.activate(section.rows[section.cursor]?.key ?? "");
        }

        Keys.onReturnPressed: keys.enter()
        Keys.onEnterPressed: keys.enter()
        Keys.onTabPressed: {
            section.closeMenu();
            section.cursor = (section.cursor + 1) % section.rows.length;
        }
        Keys.onBacktabPressed: {
            section.closeMenu();
            section.cursor = (section.cursor - 1 + section.rows.length) % section.rows.length;
        }
        Keys.onLeftPressed: event => {
            if (event.modifiers & Qt.ControlModifier)
                section.host.cycleStyle(-1);
            else
                section.host.moveBy(-1);
        }
        Keys.onRightPressed: event => {
            if (event.modifiers & Qt.ControlModifier)
                section.host.cycleStyle(1);
            else
                section.host.moveBy(1);
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                section.host.toggle();
                event.accepted = true;
            }
        }
    }

    onRowsChanged: section.cursor = Math.min(section.cursor, Math.max(0, section.rows.length - 1))

    // Klick irgendwo in die Sektion: Tastatur hierher
    MouseArea {
        anchors.fill: parent
        onPressed: mouse => {
            section.host.takeFocus();
            mouse.accepted = false;
        }
    }

    // ---- Vorschau links (mittig in ihrer Flaeche), Spalte rechts fest ----
    // Die Spalte steht fest, damit beim Blaettern nichts springt: die Breite
    // des Terminal-Blocks haengt am Look und an der Groesse
    readonly property real pad: 12
    readonly property real columnWidth: 320
    readonly property real gap: 28
    readonly property real previewH: section.height - section.pad * 2
    readonly property real previewMaxW: column.x - section.gap - section.pad
    readonly property real fit: Math.min(1, section.previewH / Math.max(1, block.item?.naturalH ?? 1),
                                         section.previewMaxW / Math.max(1, block.item?.naturalW ?? 1))
    readonly property real previewW: Math.round((block.item?.naturalW ?? 0) * section.fit)

    Loader {
        id: block

        x: section.pad + Math.round((section.previewMaxW - section.previewW) / 2)
        y: Math.round((section.height - (block.item?.naturalH ?? 0) * section.fit) / 2)
        scale: section.fit
        transformOrigin: Item.TopLeft
        opacity: section.preview === null ? 0.4 : section.previewStale ? 0.6 : 1

        Behavior on opacity {
            NumberAnimation { duration: Appearance.fadeDuration }
        }

        source: section.plugin.url("TerminalPreview.qml")
        onLoaded: {
            block.item.budgetFrame = false;
            block.item.monoFont = Qt.fontFamilies().includes("CaskaydiaCove Nerd Font Mono")
                ? "CaskaydiaCove Nerd Font Mono" : "monospace";
            block.item.preview = Qt.binding(() => section.preview);
            block.item.cols = Qt.binding(() => section.budget[0]);
            block.item.rows = Qt.binding(() => section.budget[1]);
            block.item.card = Qt.binding(() => section.card);
            block.item.cardCrop = Qt.binding(() => section.lookId === "scheme");
        }
        onStatusChanged: if (block.status === Loader.Error) section.plugin.log("TerminalPreview.qml laedt nicht")
    }

    Item {
        id: column

        x: section.width - section.pad - section.columnWidth
        width: section.columnWidth
        anchors {
            top: parent.top
            bottom: parent.bottom
            topMargin: section.pad
            bottomMargin: section.pad
        }

        Column {
            id: head

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 2

            Text {
                width: parent.width
                text: section.lookTitle(section.lookId)
                font.family: Config.font
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Colors.fgSurface
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: section.sourceLabel(section.look.source)
                font.family: Config.font
                font.pixelSize: 11
                color: Colors.fgSurfaceVariant
                elide: Text.ElideRight
            }
        }

        Column {
            id: rowList

            anchors {
                top: head.bottom
                left: parent.left
                right: parent.right
                topMargin: 10
            }
            spacing: 2

            Repeater {
                model: section.rows

                Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool on: row.modelData.enabled
                    readonly property bool marked: section.focused && section.menu === "" && section.cursor === row.index

                    width: parent.width
                    height: 30
                    radius: 9
                    opacity: row.on ? 1 : 0.45
                    color: row.marked ? Colors.alpha(Colors.primary, 0.14)
                         : rowHover.hovered && row.on ? Colors.alpha(Colors.fgSurface, 0.08)
                         : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Appearance.fadeDuration }
                    }

                    Text {
                        id: rowLabel

                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        width: Math.min(implicitWidth, parent.width - 20 - rowTrail.width - 8)
                        text: row.modelData.label
                        font.family: Config.font
                        font.pixelSize: 12
                        color: row.marked ? Colors.primary : Colors.fgSurface
                        elide: Text.ElideRight
                    }

                    Row {
                        id: rowTrail

                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.value !== ""
                            text: row.modelData.value
                            font.family: Config.font
                            font.pixelSize: 11
                            color: Colors.fgSurfaceVariant
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.menu ? "unfold_more" : "chevron_right"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 15
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                        }
                    }

                    HoverHandler {
                        id: rowHover

                        cursorShape: row.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    TapHandler {
                        enabled: row.on
                        onTapped: {
                            section.cursor = row.index;
                            section.host.takeFocus();
                            section.activate(row.modelData.key);
                        }
                    }
                }
            }
        }
    }

    // ---- Popover ueber der Spalte ----
    // Klick daneben schliesst
    MouseArea {
        anchors.fill: parent
        visible: section.menu !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: section.closeMenu()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: popover

        readonly property real pad: 6
        readonly property bool withCards: section.menu !== "groesse"

        visible: section.menu !== ""
        x: column.x - 4
        y: 6
        width: section.columnWidth + 8
        height: Math.min(section.height - 12, popColumn.implicitHeight + popover.pad * 2)
        radius: 12
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.4)

        Flickable {
            id: popFlick

            anchors.fill: parent
            anchors.margins: popover.pad
            clip: true
            contentWidth: width
            contentHeight: popColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            // Markierten Eintrag im Blick halten
            function reveal(index: int): void {
                const it = popRepeater.itemAt(index);
                if (!it)
                    return;
                const top = popTitle.height + it.y;
                if (top < popFlick.contentY)
                    popFlick.contentY = top;
                else if (top + it.height > popFlick.contentY + popFlick.height)
                    popFlick.contentY = Math.min(popFlick.contentHeight - popFlick.height, top + it.height - popFlick.height);
            }

            Connections {
                target: section

                function onMenuCursorChanged(): void {
                    popFlick.reveal(section.menuCursor);
                }
            }

            WheelHandler {
                onWheel: event => {
                    const delta = event.angleDelta.y / 120;
                    const max = Math.max(0, popFlick.contentHeight - popFlick.height);
                    popFlick.contentY = Math.max(0, Math.min(max, popFlick.contentY - delta * 60));
                }
            }

            Column {
                id: popColumn

                width: parent.width
                spacing: 1

                Item {
                    id: popTitle

                    width: parent.width
                    height: 24

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 10
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        text: section.menuTitle
                        font.family: Config.font
                        font.pixelSize: 11
                        color: Colors.fgSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                Repeater {
                    id: popRepeater

                    model: section.menuRows

                    Rectangle {
                        id: entry

                        required property int index
                        required property var modelData

                        readonly property bool current: entry.modelData.current === true
                        readonly property bool marked: section.focused && section.menuCursor === entry.index

                        width: parent.width
                        height: popover.withCards ? 32 : 26
                        radius: 9
                        color: entry.marked ? Colors.alpha(Colors.primary, 0.14)
                             : entryHover.hovered ? Colors.alpha(Colors.fgSurface, 0.08)
                             : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }

                        // Links die 3:4-Logo-Karte (bei Looks)
                        Rectangle {
                            id: cardFrame

                            anchors {
                                left: parent.left
                                leftMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            width: popover.withCards ? 20 : 0
                            height: 26
                            visible: popover.withCards
                            radius: 4
                            color: Colors.alpha(Colors.fgSurface, 0.08)

                            Image {
                                id: cardImage

                                anchors.fill: parent
                                visible: false
                                source: (entry.modelData.card ?? "") !== "" ? "file://" + entry.modelData.card : ""
                                sourceSize: Qt.size(42, 56)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }

                            Item {
                                id: cardMask

                                anchors.fill: cardImage
                                layer.enabled: true
                                visible: false

                                Rectangle {
                                    anchors.fill: parent
                                    radius: cardFrame.radius
                                    color: "black"
                                }
                            }

                            MultiEffect {
                                anchors.fill: cardImage
                                visible: cardImage.status === Image.Ready
                                source: cardImage
                                maskEnabled: true
                                maskSource: cardMask
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: cardImage.status !== Image.Ready
                                text: entry.index === 0 ? "auto_awesome" : "palette"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 13
                                color: entry.current ? Colors.primary : Colors.fgSurfaceVariant
                            }
                        }

                        Column {
                            anchors {
                                left: cardFrame.right
                                right: check.left
                                leftMargin: popover.withCards ? 9 : 4
                                rightMargin: 4
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            Text {
                                width: parent.width
                                text: entry.modelData.title
                                font.family: Config.font
                                font.pixelSize: 11
                                font.weight: entry.current ? Font.DemiBold : Font.Normal
                                color: entry.current ? Colors.fgBackground : Colors.fgSurface
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: (entry.modelData.desc ?? "") !== ""
                                text: entry.modelData.desc ?? ""
                                font.family: Config.font
                                font.pixelSize: 9
                                color: Colors.fgSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            id: check

                            anchors {
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            width: entry.current ? implicitWidth : 0
                            visible: entry.current
                            text: "check"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 15
                            color: Colors.primary
                        }

                        HoverHandler {
                            id: entryHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: entry.modelData.action()
                        }
                    }
                }
            }
        }
    }
}
