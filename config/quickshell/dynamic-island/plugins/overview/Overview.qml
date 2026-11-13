pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

import qs
import qs.modules.services.config

// Vollbild-Ansicht der Workspace-Uebersicht. Lebt nur, solange sie offen ist
// (Main.qml baut sie beim Oeffnen und zerstoert sie nach `finished`); Daten
// und Aktionen kommen aus Main (`main`), die Notch-Ansicht nutzt dieselben.
//
// Je Bildschirm ein Overlay. Oben Tabs: einer je Bildschirm (vorgewaehlt der
// eigene) und – falls es welche mit Fenstern gibt – einer fuer die
// Scratchpads (Special-Workspaces). Darunter die Workspaces des Tabs als
// Kacheln, jede ein verkleinerter Bildschirm: das Wallpaper (abgedunkelt,
// damit die Luecken zwischen den Fenstern nicht als heller Rand leuchten)
// und darauf die Fenster an ihrer echten Stelle, als Screencopy.
//
// Maus:
//   Klick Kachel        Workspace zeigen       Klick Fenster   fokussieren
//   Mittelklick Fenster schliessen             Fenster ziehen  auf andere
//   Kachel "+"          neuer Workspace        Kachel (auch "+") verschieben;
//   Klick daneben       zu                     ueber einem Tab haltend wechselt er
// Tasten (auf dem fokussierten Bildschirm):
//   (Tastatur hat der Bildschirm unter der Maus; Fenster lassen sich auch
//   auf Kacheln des anderen Bildschirms ziehen)
//   Pfeile waehlen, Enter/Leertaste geht hin, 1–9/0 direkt, N neuer
//   Workspace, Tab/Umschalt+Tab Tabs, Esc zu. SUPER+Tab schliesst wieder.
//
// Rahmen: die Auswahl ist ein Ring mit etwas Abstand AUSSEN um die Kachel –
// innen gezeichnet lag er auf den Fenstern und mit deren eigenem Rand und
// der Wallpaper-Luecke dazwischen sah es nach doppeltem Rahmen aus.
Scope {
    id: root

    property var plugin: null
    property var main: null

    // Ausblenden laeuft (Main: `fullOpen` ist dann schon false)
    property bool closing: false
    // Treibt die Ein-/Ausblende
    property bool shown: false
    signal finished

    // Bildschirm, auf dem geoeffnet wurde
    property string startMonitor: ""
    // Bildschirm mit der Tastatur: folgt der Maus
    property string keyMonitor: root.startMonitor
    // Overlay je Bildschirmname – fuer das Ziehen ueber Bildschirmgrenzen
    property var wins: ({})
    // { toplevel, from (Eintrag), w, h, source, src (Overlay) } waehrend ein
    // Fenster gezogen wird – geteilt, damit jedes Overlay Ziel sein kann
    property var drag: null

    Component.onCompleted: {
        if (root.startMonitor === "")
            root.startMonitor = Hyprland.focusedMonitor?.name ?? "";
        Qt.callLater(() => root.shown = true);
    }

    function close(): void {
        if (root.closing)
            return;
        root.closing = true;
        root.shown = false;
        closeTimer.restart();
    }

    function reopen(): void {
        closeTimer.stop();
        root.closing = false;
        root.shown = true;
    }

    Timer {
        id: closeTimer

        interval: 130
        onTriggered: root.finished()
    }

    Variants {
        model: root.main.allScreens ? Quickshell.screens : Quickshell.screens.filter(s => s.name === root.startMonitor)

        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property HyprlandMonitor hmon: Hyprland.monitorFor(win.modelData)
            readonly property bool primary: win.modelData.name === root.keyMonitor
            Component.onDestruction: if (root.wins[win.modelData.name] === win) delete root.wins[win.modelData.name]

            screen: win.modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "dynamic-island-overview"
            WlrLayershell.keyboardFocus: win.primary && !root.closing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // ---- Tabs ----
            readonly property var tabs: root.main.tabs ?? []
            property string tabKey: win.modelData.name
            readonly property int tabIndex: Math.max(0, win.tabs.findIndex(t => t.key === win.tabKey))
            readonly property var tab: win.tabs[win.tabIndex] ?? null

            function switchTab(delta: int): void {
                if (win.tabs.length === 0)
                    return;
                const i = (win.tabIndex + delta + win.tabs.length) % win.tabs.length;
                win.tabKey = win.tabs[i].key;
            }

            readonly property var entries: root.main.entriesForTab(win.tab) ?? []

            // Seitenverhaeltnis der Kacheln: Bildschirm des Tabs (Scratchpads:
            // dieser hier)
            readonly property HyprlandMonitor shapeMonitor: win.tab?.monitor ?? win.hmon
            readonly property real aspect: win.shapeMonitor && win.shapeMonitor.height > 0
                ? win.shapeMonitor.width / win.shapeMonitor.height : 16 / 9

            // ---- Auswahl (Tastatur) ----
            property int selected: 0

            function selectActive(): void {
                const i = win.entries.findIndex(e => e.active);
                win.selected = i >= 0 ? i : 0;
            }

            // Bis man selbst waehlt, steht die Auswahl auf dem aktiven
            // Workspace – auch wenn die Liste erst nach dem Aufbau kommt
            property bool picked: false
            onEntriesChanged: if (!win.picked) win.selectActive()
            onTabKeyChanged: {
                win.picked = false;
                win.selectActive();
            }
            Component.onCompleted: {
                root.wins[win.modelData.name] = win;
                win.selectActive();
            }

            function activate(i: int): void {
                const e = win.entries[i];
                if (e)
                    root.main.goTo(e);
            }

            // ---- Raster ----
            readonly property real gap: 32
            readonly property real headerH: 30
            readonly property real areaW: win.width * 0.88
            readonly property real areaH: win.height - tabBar.y - tabBar.height - 56 - 56
            readonly property var layout: {
                const n = Math.max(1, win.entries.length);
                let best = { cols: 1, w: 0 };
                for (let cols = 1; cols <= n; cols++) {
                    const rows = Math.ceil(n / cols);
                    const byW = (win.areaW - win.gap * (cols - 1)) / cols;
                    const byH = ((win.areaH - win.gap * (rows - 1)) / rows - win.headerH) * win.aspect;
                    const w = Math.min(byW, byH, win.width * 0.4);
                    if (w > best.w + 0.5)
                        best = { cols, w };
                }
                return best;
            }
            readonly property int cols: win.layout.cols
            readonly property real tileW: Math.floor(win.layout.w)
            readonly property real tileH: Math.floor(win.tileW / win.aspect)

            // Zeilen als Index-Listen, damit die letzte mittig stehen kann
            readonly property var rows: {
                const out = [];
                for (let i = 0; i < win.entries.length; i += win.cols) {
                    const row = [];
                    for (let j = i; j < Math.min(i + win.cols, win.entries.length); j++)
                        row.push(j);
                    out.push(row);
                }
                return out;
            }

            function moveSelection(dx: int, dy: int): void {
                win.picked = true;
                const n = win.entries.length;
                if (n === 0)
                    return;
                if (dy === 0) {
                    win.selected = (win.selected + dx + n) % n;
                    return;
                }
                const next = win.selected + dy * win.cols;
                if (next >= 0 && next < n)
                    win.selected = next;
                else if (dy > 0 && Math.floor(win.selected / win.cols) < win.rows.length - 1)
                    win.selected = n - 1;
            }

            // ---- Ziehen ----
            readonly property var drag: root.drag
            property point dragPos: Qt.point(0, 0)
            // Zeiger beim Ziehen gerade ueber diesem Overlay
            property bool dragHere: false
            property int dropIndex: -1
            property string hoverTab: ""
            // Kachel-Items je Index (fuer das Ziel unter dem Zeiger)
            property var tileItems: ({})
            property var tabItems: ({})

            function hitTest(items: var, p: point): string {
                for (const key in items) {
                    const item = items[key];
                    if (!item)
                        continue;
                    const local = item.mapFromItem(win.contentItem, p.x, p.y);
                    if (local.x >= 0 && local.y >= 0 && local.x <= item.width && local.y <= item.height)
                        return key;
                }
                return "";
            }

            function beginDrag(t: var, from: var, w: real, h: real, source: Item, p: point): void {
                root.drag = { toplevel: t, from, w, h, source, src: win };
                win.dragPos = p;
            }

            // Overlay unter einem Punkt dieses Overlays (auch jenseits seines
            // Rands: beim Ziehen bekommt die Quelle den Zeiger weiter) und
            // der Punkt dort
            function overlayAt(p: point): var {
                const g = Qt.point(win.modelData.x + p.x, win.modelData.y + p.y);
                for (const name in root.wins) {
                    const o = root.wins[name];
                    const s = o.modelData;
                    if (g.x >= s.x && g.y >= s.y && g.x < s.x + s.width && g.y < s.y + s.height)
                        return { win: o, p: Qt.point(g.x - s.x, g.y - s.y) };
                }
                return null;
            }

            function moveDrag(p: point): void {
                win.dragPos = p;
                const hit = win.overlayAt(p);
                for (const name in root.wins)
                    if (root.wins[name] !== hit?.win)
                        root.wins[name].hoverDrop(null);
                hit?.win.hoverDrop(hit.p);
            }

            // Ziel unter dem Zeiger merken (null = Zeiger ist woanders)
            function hoverDrop(p: var): void {
                win.dragHere = p !== null;
                if (p === null) {
                    win.dropIndex = -1;
                    win.hoverTab = "";
                    springTab.stop();
                    return;
                }
                win.dragPos = p;
                const tile = win.hitTest(win.tileItems, p);
                win.dropIndex = tile === "" ? -1 : Number(tile);

                const tabHit = win.hitTest(win.tabItems, p);
                if (tabHit !== win.hoverTab) {
                    win.hoverTab = tabHit;
                    if (tabHit !== "" && tabHit !== win.tabKey)
                        springTab.restart();
                    else
                        springTab.stop();
                }
            }

            function endDrag(): void {
                const d = root.drag;
                let target = null;
                for (const name in root.wins) {
                    const o = root.wins[name];
                    target = target ?? o.entries[o.dropIndex] ?? null;
                    o.hoverDrop(null);
                }
                root.drag = null;
                if (!d || !target)
                    return;
                if (target.kind === "ws" && target.id === d.from.id)
                    return;
                root.main.moveWindow(d.toplevel, target);
            }

            // Beim Ziehen ueber einem Tab kurz halten = Tab wechseln
            Timer {
                id: springTab

                interval: 380
                onTriggered: if (win.drag && win.hoverTab !== "") win.tabKey = win.hoverTab
            }

            // ================= Inhalt =================
            Item {
                id: content

                anchors.fill: parent
                focus: true
                opacity: root.shown ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: root.shown ? 170 : 120; easing.type: Easing.OutCubic }
                }

                // Tastatur folgt der Maus auf diesen Bildschirm
                HoverHandler {
                    onHoveredChanged: if (hovered && !root.drag) root.keyMonitor = win.modelData.name
                }

                Keys.onPressed: event => {
                    const k = event.key;
                    if (k === Qt.Key_Escape) {
                        root.main.hide();
                    } else if (k === Qt.Key_Left) {
                        win.moveSelection(-1, 0);
                    } else if (k === Qt.Key_Right) {
                        win.moveSelection(1, 0);
                    } else if (k === Qt.Key_Up) {
                        win.moveSelection(0, -1);
                    } else if (k === Qt.Key_Down) {
                        win.moveSelection(0, 1);
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                        win.activate(win.selected);
                    } else if (k === Qt.Key_Backtab || (k === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                        win.switchTab(-1);
                    } else if (k === Qt.Key_Tab) {
                        win.switchTab(1);
                    } else if (k === Qt.Key_N) {
                        const i = win.entries.findIndex(e => e.kind === "new");
                        if (i >= 0)
                            win.activate(i);
                    } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
                        const label = k === Qt.Key_0 ? "10" : `${k - Qt.Key_0}`;
                        const i = win.entries.findIndex(e => e.label === label);
                        if (i >= 0)
                            win.activate(i);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // ---- Hintergrund: Wallpaper weich und abgedunkelt ----
                Image {
                    id: bgImage

                    anchors.fill: parent
                    source: root.main.wallThumb
                    sourceSize: Qt.size(480, 270)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: true
                    visible: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: bgImage
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    saturation: 0.1
                    autoPaddingEnabled: false
                }

                Rectangle {
                    anchors.fill: parent
                    color: Colors.alpha(Colors.background, 0.62)
                }

                // Klick ins Leere: zu
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: root.main.hide()
                }

                // ---- Tabs ----
                Rectangle {
                    id: tabBar

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 56
                    width: tabRow.implicitWidth + 12
                    height: 48
                    radius: height / 2
                    color: Colors.alpha(Colors.surface, 0.82)
                    border.width: 1
                    border.color: Colors.alpha(Colors.outline, 0.25)

                    scale: root.shown ? 1 : 0.94
                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    // Nicht durchklicken (sonst schliesst der Hintergrund)
                    MouseArea {
                        anchors.fill: parent
                    }

                    Row {
                        id: tabRow

                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: win.tabs

                            delegate: Rectangle {
                                id: tabItem

                                required property var modelData
                                required property int index

                                readonly property bool current: tabItem.index === win.tabIndex
                                readonly property bool dropHover: win.drag !== null && win.hoverTab === tabItem.modelData.key
                                readonly property HyprlandMonitor mon: tabItem.modelData.monitor

                                Component.onCompleted: win.tabItems[tabItem.modelData.key] = tabItem
                                Component.onDestruction: delete win.tabItems[tabItem.modelData.key]

                                width: tabLabel.implicitWidth + 36
                                height: 36
                                radius: height / 2
                                color: tabItem.current ? Colors.primary
                                    : tabItem.dropHover ? Colors.alpha(Colors.primary, 0.3)
                                    : tabArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08)
                                    : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                Text {
                                    id: tabLabel

                                    anchors.centerIn: parent
                                    text: tabItem.modelData.kind === "special" ? I18n.tr("Scratchpads")
                                        : tabItem.mon?.name ?? ""
                                    font.family: Config.font
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: tabItem.current ? Colors.fgPrimary : Colors.fgSurface
                                }

                                MouseArea {
                                    id: tabArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.tabKey = tabItem.modelData.key
                                }
                            }
                        }
                    }
                }

                // ---- Kacheln ----
                Column {
                    id: grid

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: tabBar.y + tabBar.height + 56
                       + Math.max(0, (win.areaH - (win.rows.length * (win.tileH + win.headerH) + (win.rows.length - 1) * win.gap)) / 2)
                    spacing: win.gap

                    scale: root.shown ? 1 : 0.96
                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Repeater {
                        model: win.rows

                        delegate: Row {
                            id: rowItem

                            required property var modelData

                            anchors.horizontalCenter: parent?.horizontalCenter
                            spacing: win.gap

                            Repeater {
                                model: rowItem.modelData

                                delegate: Item {
                                    id: tile

                                    required property int modelData
                                    readonly property int index: tile.modelData
                                    readonly property var entry: win.entries[tile.index] ?? null
                                    readonly property bool isNew: tile.entry?.kind === "new"
                                    readonly property HyprlandMonitor mon: tile.entry?.monitor ?? win.hmon
                                    readonly property var wins: tile.entry && !tile.isNew ? root.main.windowsOn(tile.entry.id) : []

                                    // Logische Groesse des Bildschirms -> Kachel
                                    readonly property real monW: tile.mon ? tile.mon.width / Math.max(0.1, tile.mon.scale) : 2560
                                    readonly property real s: win.tileW / tile.monW

                                    readonly property bool selected: win.selected === tile.index && win.primary
                                    readonly property bool hovered: tileHover.hovered && !win.drag
                                    readonly property bool dropTarget: win.drag !== null && win.dropIndex === tile.index
                                        && !(tile.entry?.kind === "ws" && tile.entry.id === win.drag.from.id)

                                    width: win.tileW
                                    height: win.tileH + win.headerH

                                    Component.onCompleted: win.tileItems[tile.index] = tile
                                    Component.onDestruction: if (win.tileItems[tile.index] === tile) delete win.tileItems[tile.index]

                                    HoverHandler {
                                        id: tileHover
                                    }

                                    // -- Kopfzeile: Nummer (aktiv = Akzentfarbe) --
                                    Row {
                                        id: header

                                        x: 4
                                        height: win.headerH - 8
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: tile.entry?.special ? "layers" : ""
                                            visible: text !== ""
                                            font.family: "Material Symbols Outlined"
                                            font.pixelSize: 16
                                            color: Colors.primary
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: tile.isNew ? I18n.tr("Neuer Workspace") : tile.entry?.label ?? ""
                                            font.family: Config.font
                                            font.pixelSize: tile.isNew || tile.entry?.special ? 13 : 15
                                            font.weight: Font.Bold
                                            color: tile.entry?.active ? Colors.primary : Colors.fgSurface
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            // Nummer, die der neue Workspace bekommt
                                            visible: tile.isNew
                                            text: tile.isNew ? `${tile.entry.label}` : ""
                                            font.family: Config.font
                                            font.pixelSize: 11
                                            color: Colors.fgSurfaceVariant
                                        }
                                    }

                                    // -- Der verkleinerte Bildschirm --
                                    Item {
                                        id: screenArea

                                        y: win.headerH
                                        width: win.tileW
                                        height: win.tileH

                                        RectangularShadow {
                                            anchors.fill: parent
                                            radius: 12
                                            blur: 24
                                            offset.y: 6
                                            color: Qt.rgba(0, 0, 0, 0.35)
                                        }

                                        ClippingRectangle {
                                            id: clipper

                                            anchors.fill: parent
                                            radius: 12
                                            color: Colors.background

                                            // Abgedunkelt: zwischen den Fenstern liegen nur
                                            // die Luecken, hell leuchteten die als Rahmen
                                            Image {
                                                anchors.fill: parent
                                                visible: !tile.isNew
                                                source: root.main.wallThumb
                                                sourceSize: Qt.size(480, 270)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: false
                                                cache: true
                                                opacity: tile.wins.length > 0 ? 0.3 : 0.85
                                            }

                                            // "+": leere Flaeche mit grossem Plus
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: tile.isNew
                                                color: Colors.alpha(Colors.surfaceBright, tile.hovered || tile.selected ? 0.55 : 0.35)

                                                Behavior on color {
                                                    ColorAnimation { duration: 120 }
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "add"
                                                    font.family: "Material Symbols Outlined"
                                                    font.pixelSize: Math.min(64, win.tileH * 0.32)
                                                    color: tile.hovered || tile.selected ? Colors.primary : Colors.fgSurfaceVariant
                                                }
                                            }

                                            // Klick auf die Kachel (unter den Fenstern)
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.activate(tile.index)
                                            }

                                            // -- Fenster --
                                            Repeater {
                                                model: tile.wins

                                                delegate: Item {
                                                    id: wnd

                                                    required property var modelData
                                                    readonly property var o: wnd.modelData.lastIpcObject ?? {}
                                                    readonly property bool dragged: win.drag !== null && win.drag.toplevel === wnd.modelData

                                                    x: Math.round(((wnd.o.at?.[0] ?? 0) - (tile.mon?.x ?? 0)) * tile.s)
                                                    y: Math.round(((wnd.o.at?.[1] ?? 0) - (tile.mon?.y ?? 0)) * tile.s)
                                                    width: Math.max(8, Math.round((wnd.o.size?.[0] ?? 0) * tile.s))
                                                    height: Math.max(8, Math.round((wnd.o.size?.[1] ?? 0) * tile.s))
                                                    opacity: wnd.dragged ? 0.3 : 1

                                                    ClippingRectangle {
                                                        id: preview

                                                        anchors.fill: parent
                                                        radius: 6
                                                        color: Colors.surfaceContainer

                                                        ScreencopyView {
                                                            id: cap

                                                            anchors.fill: parent
                                                            captureSource: root.closing ? null : wnd.modelData.wayland
                                                            // Live nur, wo man hinschaut (Main.preview)
                                                            // `live` nur bei "alle": es kopiert je Monitor-Frame (180 Hz),
                                                            // schon ein ruhiges Fenster kostete so ~8 % CPU. Bei "auswahl"
                                                            // selbst getaktet (Main: fastTick 30 fps, tick 1/s)
                                                            live: root.main.preview === "alle"
                                                            paintCursor: false

                                                            Connections {
                                                                target: root.main.preview === "auswahl" ? root.main : null

                                                                function onTick(): void {
                                                                    if (!tile.selected && !tile.hovered && cap.hasContent)
                                                                        cap.captureFrame();
                                                                }
                                                                function onFastTick(): void {
                                                                    if ((tile.selected || tile.hovered) && cap.hasContent)
                                                                        cap.captureFrame();
                                                                }
                                                            }
                                                        }

                                                        // Ohne Bild (noch keins, oder das Fenster
                                                        // laesst sich nicht abgreifen): grosses Symbol
                                                        IconImage {
                                                            anchors.centerIn: parent
                                                            visible: !cap.hasContent
                                                            implicitSize: Math.max(16, Math.min(56, Math.min(wnd.width, wnd.height) * 0.4))
                                                            source: root.main.iconFor(wnd.o.class ?? "")
                                                        }
                                                    }

                                                    // App-Symbol unten links
                                                    IconImage {
                                                        x: 6
                                                        y: wnd.height - height - 6
                                                        visible: cap.hasContent && wnd.width > 60 && wnd.height > 40
                                                        implicitSize: Math.max(14, Math.min(26, wnd.height * 0.18))
                                                        source: root.main.iconFor(wnd.o.class ?? "")
                                                    }

                                                    // Feiner Rand (nebeneinander liegende Fenster
                                                    // laufen sonst ineinander), beim Drueberfahren
                                                    // in der Akzentfarbe
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 6
                                                        color: winArea.containsMouse && !win.drag ? Colors.alpha(Colors.primary, 0.08) : "transparent"
                                                        border.width: winArea.containsMouse && !win.drag ? 2 : 1
                                                        border.color: winArea.containsMouse ? Colors.primary : Colors.alpha(Colors.outline, 0.3)
                                                    }

                                                    MouseArea {
                                                        id: winArea

                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                                        cursorShape: win.drag ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                                                        property point pressAt
                                                        property bool wasDrag: false

                                                        onPressed: event => {
                                                            winArea.pressAt = Qt.point(event.x, event.y);
                                                            winArea.wasDrag = false;
                                                        }
                                                        onPositionChanged: event => {
                                                            if (!winArea.pressed || !(event.buttons & Qt.LeftButton))
                                                                return;
                                                            const p = winArea.mapToItem(content, event.x, event.y);
                                                            if (!win.drag && Math.hypot(event.x - winArea.pressAt.x, event.y - winArea.pressAt.y) > 8) {
                                                                winArea.wasDrag = true;
                                                                win.beginDrag(wnd.modelData, tile.entry, wnd.width, wnd.height, preview, p);
                                                            }
                                                            if (win.drag)
                                                                win.moveDrag(p);
                                                        }
                                                        onReleased: {
                                                            if (win.drag)
                                                                win.endDrag();
                                                        }
                                                        onClicked: event => {
                                                            if (winArea.wasDrag)
                                                                return;
                                                            if (event.button === Qt.MiddleButton)
                                                                root.main.closeWindow(wnd.modelData);
                                                            else
                                                                root.main.focusWindow(wnd.modelData);
                                                        }
                                                    }

                                                    // Titel beim Drueberfahren
                                                    Rectangle {
                                                        anchors {
                                                            horizontalCenter: parent.horizontalCenter
                                                            bottom: parent.bottom
                                                            bottomMargin: 6
                                                        }
                                                        visible: winArea.containsMouse && !win.drag && wnd.height > 50
                                                        width: Math.min(wnd.width - 12, titleText.implicitWidth + 16)
                                                        height: 22
                                                        radius: 11
                                                        color: Colors.alpha(Colors.surface, 0.92)

                                                        Text {
                                                            id: titleText

                                                            anchors.centerIn: parent
                                                            width: Math.min(implicitWidth, parent.width - 16)
                                                            text: wnd.o.title ?? ""
                                                            elide: Text.ElideRight
                                                            font.family: Config.font
                                                            font.pixelSize: 11
                                                            color: Colors.fgSurface
                                                        }
                                                    }
                                                }
                                            }

                                            // Ablageziel: leicht eingefaerbt
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: tile.dropTarget
                                                color: Colors.alpha(Colors.primary, 0.16)
                                            }
                                        }

                                        // Kante der Kachel: eine feine Linie, innen
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 12
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Colors.alpha(Colors.outline, 0.3)
                                        }

                                        // Auswahl-/Ziel-Ring mit Abstand aussen – zuletzt, sonst legt sich
                                        // der Schatten darueber
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            radius: 18
                                            color: "transparent"
                                            border.width: 2
                                            border.color: tile.dropTarget || tile.selected ? Colors.primary
                                                : Colors.alpha(Colors.primary, 0.45)
                                            opacity: tile.dropTarget || tile.selected || tile.hovered ? 1 : 0

                                            Behavior on opacity {
                                                NumberAnimation { duration: 120 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Gezogenes Fenster am Zeiger ----
                ShaderEffectSource {
                    id: ghost

                    readonly property real gw: win.drag ? Math.min(280, win.drag.w) : 0
                    readonly property real gh: win.drag ? ghost.gw * win.drag.h / Math.max(1, win.drag.w) : 0

                    // nur im Quell-Overlay: die Vorschau lebt in dessen Szene
                    visible: win.drag !== null && win.drag.src === win
                    sourceItem: win.drag?.source ?? null
                    live: true
                    width: ghost.gw
                    height: ghost.gh
                    x: win.dragPos.x - ghost.gw / 2
                    y: win.dragPos.y - ghost.gh / 2
                    opacity: 0.9
                    z: 100
                }

                // Auf dem anderen Bildschirm: dort eine eigene Kopie des Fensters
                ScreencopyView {
                    visible: win.dragHere && win.drag.src !== win
                    captureSource: visible ? win.drag.toplevel.wayland : null
                    paintCursor: false
                    width: ghost.gw
                    height: ghost.gh
                    x: win.dragPos.x - ghost.gw / 2
                    y: win.dragPos.y - ghost.gh / 2
                    opacity: 0.9
                    z: 100
                }
            }
        }
    }
}
