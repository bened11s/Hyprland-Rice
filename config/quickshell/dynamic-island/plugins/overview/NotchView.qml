pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

import qs
import qs.modules.services.config

// Notch-Ansicht der Workspace-Uebersicht (Manifest `panels.notch`): dasselbe
// wie das Vollbild (Overview.qml), nur kompakt in der Karte der Notch – oben
// die Tabs als Chips, darunter eine Reihe kleiner Kacheln. Daten und
// Aktionen aus Main (`plugin.main`).
//
// Die Notch baut die Ansicht erst beim Oeffnen und gibt ihr die Tastatur
// (Bar.qml); Klick neben die Karte schliesst sie (Fangflaeche der Leiste).
// Tasten wie im Vollbild: Pfeile, Enter, 1–9/0, N, Tab, Esc. Der Knopf oben
// rechts (oder F) wechselt ins Vollbild.
Item {
    id: view

    required property var plugin
    required property var host

    readonly property var m: view.plugin.main

    readonly property HyprlandMonitor hmon: Hyprland.monitorFor(view.host.screen)

    // ---- Tabs ----
    readonly property var tabs: view.m?.tabs ?? []
    property string tabKey: view.host.screen?.name ?? ""
    readonly property int tabIndex: Math.max(0, view.tabs.findIndex(t => t.key === view.tabKey))
    readonly property var tab: view.tabs[view.tabIndex] ?? null
    readonly property var entries: view.m?.entriesForTab(view.tab) ?? []

    function switchTab(delta: int): void {
        if (view.tabs.length === 0)
            return;
        const i = (view.tabIndex + delta + view.tabs.length) % view.tabs.length;
        view.tabKey = view.tabs[i].key;
    }

    // ---- Masse ----
    readonly property HyprlandMonitor shapeMonitor: view.tab?.monitor ?? view.hmon
    readonly property real aspect: view.shapeMonitor && view.shapeMonitor.height > 0
        ? view.shapeMonitor.width / view.shapeMonitor.height : 16 / 9
    readonly property real tileW: 216
    readonly property real tileH: Math.round(view.tileW / view.aspect)
    readonly property real labelH: 24
    readonly property real gap: 14
    readonly property real pad: 16

    readonly property real rowWidth: view.entries.length * (view.tileW + view.gap) - view.gap

    // Die Karte waechst mit der Zahl der Kacheln (bis die Reihe scrollt)
    implicitWidth: Math.max(640, Math.min(1180, view.rowWidth + 2 * view.pad))
    implicitHeight: header.height + 1 + view.pad + view.labelH + view.tileH + view.pad

    // ---- Auswahl ----
    property int selected: 0

    function selectActive(): void {
        const i = view.entries.findIndex(e => e.active);
        view.selected = i >= 0 ? i : 0;
    }

    // Bis man selbst waehlt, steht die Auswahl auf dem aktiven Workspace
    property bool picked: false
    onEntriesChanged: if (!view.picked) view.selectActive()
    onTabKeyChanged: {
        view.picked = false;
        view.selectActive();
    }
    onSelectedChanged: list.positionViewAtIndex(view.selected, ListView.Contain)

    function activate(i: int): void {
        const e = view.entries[i];
        if (e)
            view.m.goTo(e);
    }

    focus: true
    Component.onCompleted: {
        view.selectActive();
        view.forceActiveFocus();
    }

    Keys.onPressed: event => {
        const k = event.key;
        const n = view.entries.length;
        if (k === Qt.Key_Escape) {
            view.host.close();
        } else if ((k === Qt.Key_Left || k === Qt.Key_Up) && n > 0) {
            view.picked = true;
            view.selected = (view.selected - 1 + n) % n;
        } else if ((k === Qt.Key_Right || k === Qt.Key_Down) && n > 0) {
            view.picked = true;
            view.selected = (view.selected + 1) % n;
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            view.activate(view.selected);
        } else if (k === Qt.Key_Backtab || (k === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
            view.switchTab(-1);
        } else if (k === Qt.Key_Tab) {
            view.switchTab(1);
        } else if (k === Qt.Key_F) {
            view.m.showFull();
        } else if (k === Qt.Key_N) {
            const i = view.entries.findIndex(e => e.kind === "new");
            if (i >= 0)
                view.activate(i);
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            const label = k === Qt.Key_0 ? "10" : `${k - Qt.Key_0}`;
            const i = view.entries.findIndex(e => e.label === label);
            if (i >= 0)
                view.activate(i);
        } else {
            return;
        }
        event.accepted = true;
    }

    // ---- Ziehen (wie im Vollbild, nur innerhalb der Karte) ----
    property var drag: null
    property point dragPos: Qt.point(0, 0)
    property int dropIndex: -1
    property string hoverTab: ""
    property var tileItems: ({})
    property var tabItems: ({})

    function hitTest(items: var, p: point): string {
        for (const key in items) {
            const item = items[key];
            if (!item)
                continue;
            const local = item.mapFromItem(view, p.x, p.y);
            if (local.x >= 0 && local.y >= 0 && local.x <= item.width && local.y <= item.height)
                return key;
        }
        return "";
    }

    function moveDrag(p: point): void {
        view.dragPos = p;
        const tile = view.hitTest(view.tileItems, p);
        view.dropIndex = tile === "" ? -1 : Number(tile);
        const tabHit = view.hitTest(view.tabItems, p);
        if (tabHit !== view.hoverTab) {
            view.hoverTab = tabHit;
            if (tabHit !== "" && tabHit !== view.tabKey)
                springTab.restart();
            else
                springTab.stop();
        }
    }

    function endDrag(): void {
        const d = view.drag;
        const target = view.entries[view.dropIndex];
        view.drag = null;
        view.dropIndex = -1;
        view.hoverTab = "";
        springTab.stop();
        if (!d || !target)
            return;
        if (target.kind === "ws" && target.id === d.from.id)
            return;
        view.m.moveWindow(d.toplevel, target);
    }

    Timer {
        id: springTab

        interval: 380
        onTriggered: if (view.drag && view.hoverTab !== "") view.tabKey = view.hoverTab
    }

    // ================= Kopfzeile =================
    Item {
        id: header

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 50

        Row {
            anchors {
                left: parent.left
                leftMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Repeater {
                model: view.tabs

                delegate: Rectangle {
                    id: chip

                    required property var modelData
                    required property int index

                    readonly property bool current: chip.index === view.tabIndex
                    readonly property bool dropHover: view.drag !== null && view.hoverTab === chip.modelData.key
                    readonly property HyprlandMonitor mon: chip.modelData.monitor

                    Component.onCompleted: view.tabItems[chip.modelData.key] = chip
                    Component.onDestruction: delete view.tabItems[chip.modelData.key]

                    width: chipLabel.implicitWidth + 24
                    height: 30
                    radius: height / 2
                    color: chip.current ? Colors.primary
                        : chip.dropHover ? Colors.alpha(Colors.primary, 0.3)
                        : chipArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08)
                        : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        id: chipLabel

                        anchors.centerIn: parent
                        text: chip.modelData.kind === "special" ? I18n.tr("Scratchpads") : chip.mon?.name ?? ""
                        font.family: Config.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: chip.current ? Colors.fgPrimary : Colors.fgSurface
                    }

                    MouseArea {
                        id: chipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.tabKey = chip.modelData.key
                    }
                }
            }
        }

        // Ins Vollbild
        Rectangle {
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            width: 32
            height: 32
            radius: height / 2
            color: fullArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"

            Behavior on color {
                ColorAnimation { duration: 90 }
            }

            Text {
                anchors.centerIn: parent
                text: "open_in_full"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
                color: fullArea.containsMouse ? Colors.primary : Colors.fgSurfaceVariant
            }

            MouseArea {
                id: fullArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: view.m.showFull()
            }
        }
    }

    Rectangle {
        id: separator

        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.35)
    }

    // ================= Kacheln =================
    ListView {
        id: list

        anchors {
            top: separator.bottom
            topMargin: view.pad
            horizontalCenter: parent.horizontalCenter
        }
        // Der Ring der Auswahl ragt 4 px heraus: Rand dafuer, dann clippen
        width: Math.min(view.rowWidth, parent.width - 2 * view.pad) + 12
        height: view.labelH + view.tileH + 6
        leftMargin: 6
        rightMargin: 6
        orientation: ListView.Horizontal
        spacing: view.gap
        clip: true
        interactive: view.rowWidth > list.width && view.drag === null
        boundsBehavior: Flickable.StopAtBounds
        model: view.entries

        delegate: Item {
            id: tile

            required property var modelData
            required property int index

            readonly property var entry: tile.modelData
            readonly property bool isNew: tile.entry.kind === "new"
            readonly property HyprlandMonitor mon: tile.entry.monitor ?? view.hmon
            readonly property var wins: !tile.isNew ? view.m.windowsOn(tile.entry.id) : []
            readonly property real monW: tile.mon ? tile.mon.width / Math.max(0.1, tile.mon.scale) : 2560
            readonly property real s: view.tileW / tile.monW

            readonly property bool selected: view.selected === tile.index
            readonly property bool hovered: tileHover.hovered && !view.drag
            readonly property bool dropTarget: view.drag !== null && view.dropIndex === tile.index
                && !(tile.entry.kind === "ws" && tile.entry.id === view.drag.from.id)

            width: view.tileW
            height: view.labelH + view.tileH

            Component.onCompleted: view.tileItems[tile.index] = tile
            Component.onDestruction: if (view.tileItems[tile.index] === tile) delete view.tileItems[tile.index]

            HoverHandler {
                id: tileHover
            }

            Row {
                x: 2
                height: view.labelH - 6
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.entry.special ? "layers" : ""
                    visible: text !== ""
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 14
                    color: Colors.primary
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.isNew ? I18n.tr("Neuer Workspace") : tile.entry.label
                    font.family: Config.font
                    font.pixelSize: tile.isNew || tile.entry.special ? 12 : 13
                    font.weight: Font.Bold
                    color: tile.entry.active ? Colors.primary : Colors.fgSurface
                }
            }

            Item {
                id: screenArea

                y: view.labelH
                width: view.tileW
                height: view.tileH

                // Auswahl-/Ziel-Ring mit Abstand aussen
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: 14
                    color: "transparent"
                    border.width: 2
                    border.color: tile.dropTarget || tile.selected ? Colors.primary : Colors.alpha(Colors.primary, 0.45)
                    opacity: tile.dropTarget || tile.selected || tile.hovered ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Colors.background

                    Image {
                        anchors.fill: parent
                        visible: !tile.isNew
                        source: view.m.wallThumb
                        sourceSize: Qt.size(480, 270)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: false
                        cache: true
                        opacity: tile.wins.length > 0 ? 0.3 : 0.85
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: tile.isNew
                        color: Colors.alpha(Colors.surfaceBright, tile.hovered || tile.selected ? 0.55 : 0.35)

                        Text {
                            anchors.centerIn: parent
                            text: "add"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 34
                            color: tile.hovered || tile.selected ? Colors.primary : Colors.fgSurfaceVariant
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.activate(tile.index)
                    }

                    Repeater {
                        model: tile.wins

                        delegate: Item {
                            id: wnd

                            required property var modelData
                            readonly property var o: wnd.modelData.lastIpcObject ?? {}
                            readonly property bool dragged: view.drag !== null && view.drag.toplevel === wnd.modelData

                            x: Math.round(((wnd.o.at?.[0] ?? 0) - (tile.mon?.x ?? 0)) * tile.s)
                            y: Math.round(((wnd.o.at?.[1] ?? 0) - (tile.mon?.y ?? 0)) * tile.s)
                            width: Math.max(6, Math.round((wnd.o.size?.[0] ?? 0) * tile.s))
                            height: Math.max(6, Math.round((wnd.o.size?.[1] ?? 0) * tile.s))
                            opacity: wnd.dragged ? 0.3 : 1

                            ClippingRectangle {
                                id: preview

                                anchors.fill: parent
                                radius: 4
                                color: Colors.surfaceContainer

                                ScreencopyView {
                                    id: cap

                                    anchors.fill: parent
                                    captureSource: wnd.modelData.wayland
                                    // Live nur, wo man hinschaut (Main.preview)
                                    // `live` nur bei "alle": es kopiert je Monitor-Frame (180 Hz),
                                    // schon ein ruhiges Fenster kostete so ~8 % CPU. Bei "auswahl"
                                    // selbst getaktet (Main: fastTick 30 fps, tick 1/s)
                                    live: view.m.preview === "alle"
                                    paintCursor: false

                                    Connections {
                                        target: view.m.preview === "auswahl" ? view.m : null

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

                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !cap.hasContent
                                    implicitSize: Math.max(12, Math.min(32, Math.min(wnd.width, wnd.height) * 0.45))
                                    source: view.m.iconFor(wnd.o.class ?? "")
                                }
                            }

                            IconImage {
                                x: 4
                                y: wnd.height - height - 4
                                visible: cap.hasContent && wnd.width > 40 && wnd.height > 30
                                implicitSize: Math.max(12, Math.min(18, wnd.height * 0.2))
                                source: view.m.iconFor(wnd.o.class ?? "")
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                color: winArea.containsMouse && !view.drag ? Colors.alpha(Colors.primary, 0.08) : "transparent"
                                border.width: winArea.containsMouse && !view.drag ? 2 : 1
                                border.color: winArea.containsMouse ? Colors.primary : Colors.alpha(Colors.outline, 0.3)
                            }

                            MouseArea {
                                id: winArea

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: view.drag ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                                property point pressAt
                                property bool wasDrag: false

                                onPressed: event => {
                                    winArea.pressAt = Qt.point(event.x, event.y);
                                    winArea.wasDrag = false;
                                }
                                onPositionChanged: event => {
                                    if (!winArea.pressed || !(event.buttons & Qt.LeftButton))
                                        return;
                                    const p = winArea.mapToItem(view, event.x, event.y);
                                    if (!view.drag && Math.hypot(event.x - winArea.pressAt.x, event.y - winArea.pressAt.y) > 6) {
                                        winArea.wasDrag = true;
                                        view.drag = { toplevel: wnd.modelData, from: tile.entry, w: wnd.width, h: wnd.height, source: preview };
                                    }
                                    if (view.drag)
                                        view.moveDrag(p);
                                }
                                onReleased: {
                                    if (view.drag)
                                        view.endDrag();
                                }
                                onClicked: event => {
                                    if (winArea.wasDrag)
                                        return;
                                    if (event.button === Qt.MiddleButton)
                                        view.m.closeWindow(wnd.modelData);
                                    else
                                        view.m.focusWindow(wnd.modelData);
                                }
                            }

                            // Titel als Tooltip unter der Kachel waere
                            // abgeschnitten – darum in der Kachel, klein
                            Rectangle {
                                anchors {
                                    horizontalCenter: parent.horizontalCenter
                                    bottom: parent.bottom
                                    bottomMargin: 4
                                }
                                visible: winArea.containsMouse && !view.drag && wnd.height > 34
                                width: Math.min(wnd.width - 8, titleText.implicitWidth + 12)
                                height: 18
                                radius: 9
                                color: Colors.alpha(Colors.surface, 0.92)

                                Text {
                                    id: titleText

                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - 12)
                                    text: wnd.o.title ?? ""
                                    elide: Text.ElideRight
                                    font.family: Config.font
                                    font.pixelSize: 10
                                    color: Colors.fgSurface
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: tile.dropTarget
                        color: Colors.alpha(Colors.primary, 0.16)
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.alpha(Colors.outline, 0.3)
                }
            }
        }
    }

    // Gezogenes Fenster am Zeiger
    ShaderEffectSource {
        readonly property real gw: view.drag ? Math.min(160, view.drag.w) : 0
        readonly property real gh: view.drag ? gw * view.drag.h / Math.max(1, view.drag.w) : 0

        visible: view.drag !== null
        sourceItem: view.drag?.source ?? null
        live: true
        width: gw
        height: gh
        x: view.dragPos.x - gw / 2
        y: view.dragPos.y - gh / 2
        opacity: 0.9
        z: 100
    }
}
