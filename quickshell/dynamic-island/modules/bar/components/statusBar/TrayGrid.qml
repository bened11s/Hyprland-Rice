pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import qs
import qs.modules.services.config

// Systemtray als Kachel-Reihe – fuer die Steuerung der Notch (ControlPanel).
// Die Leisten-Pille (StatusBar.qml) bleibt fuer das Insel-Layout.
//
// Jede App ist eine Kachel mit Symbol und Namen, alle in EINER Zeile, die
// die Breite fuellt. Werden die Kacheln zu schmal fuer den Namen, zeigen sie
// nur das Symbol; reicht auch das nicht, scrollt die Zeile seitlich:
//   Linksklick     App oeffnen (activate)
//   Rechtsklick    Menue (eigenes Popup, wie in der Leiste – kein Grab)
//   Mittelklick    secondaryActivate
// Passive Apps (laufen nur im Hintergrund, z.B. Spotify ohne Fenster) sind
// gedimmt, "braucht Aufmerksamkeit" bekommt einen Punkt in der Akzentfarbe.
// Anders als in der Leiste oeffnet Hover hier kein Menue – in einem Panel
// voller Kacheln waere das stoerend.
Item {
    id: root

    property real spacing: 8
    readonly property real tileHeight: 44
    // Darunter nur noch das Symbol, und schmaler als minTile wird keine
    readonly property real labelMinWidth: 96
    readonly property real minTile: 44

    // Aktive zuerst, dann "braucht Aufmerksamkeit", passive zuletzt; sonst
    // nach Namen
    readonly property var items: {
        const rank = item => item.status === Status.NeedsAttention ? 0
                           : item.status === Status.Active ? 1 : 2;
        return [...SystemTray.items.values].sort((a, b) =>
            rank(a) - rank(b) || root.nameOf(a).localeCompare(root.nameOf(b)));
    }
    readonly property int count: root.items.length
    readonly property real tileWidth: root.count === 0 ? 0
        : Math.max(root.minTile, (root.width - root.spacing * (root.count - 1)) / root.count)
    readonly property bool compact: root.tileWidth < root.labelMinWidth

    property var currentMenu: null

    implicitHeight: root.count === 0 ? 0 : root.tileHeight

    // Lesbarer Name: Titel, Tooltip, sonst die ID ohne Anhaengsel
    // ("discord_status_icon_1" -> "Discord", "spotify-client" -> "Spotify")
    function nameOf(item: var): string {
        const pick = item?.title || item?.tooltipTitle || "";
        if (pick !== "")
            return pick.charAt(0).toUpperCase() + pick.slice(1);
        const id = (item?.id ?? "").toLowerCase()
            .replace(/[_-]?(status[_-]?icon|tray|client|indicator)([_-]?\d+)?$/, "")
            .replace(/[_-]\d+$/, "");
        return id === "" ? "App" : id.charAt(0).toUpperCase() + id.slice(1);
    }

    function openMenuFor(item: var, entry: Item): void {
        if (!item?.hasMenu)
            return;
        menuPopup.anchor.item = entry;
        root.currentMenu = item.menu;
        trayMenu.open(item.menu);
        closeGrace.stop();
    }

    function closeMenu(): void {
        root.currentMenu = null;
    }

    // Wird die Steuerung geschlossen, geht das Menue mit
    onVisibleChanged: if (!visible) root.closeMenu()

    Flickable {
        id: strip

        anchors.fill: parent
        contentWidth: root.count * root.tileWidth + Math.max(0, root.count - 1) * root.spacing
        contentHeight: root.tileHeight
        interactive: strip.contentWidth > strip.width
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        // Senkrechtes Rad scrollt die Zeile seitlich, solange sie ueberlaeuft
        WheelHandler {
            enabled: strip.interactive
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const d = event.pixelDelta.y !== 0 ? event.pixelDelta.y
                        : event.angleDelta.y !== 0 ? event.angleDelta.y / 2
                        : event.angleDelta.x / 2;
                strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX - d));
            }
        }

        Repeater {
            model: root.items

            Rectangle {
                id: tile

                required property SystemTrayItem modelData
                required property int index

                readonly property bool passive: tile.modelData.status === Status.Passive
                readonly property bool attention: tile.modelData.status === Status.NeedsAttention
                readonly property bool menuOpen: root.currentMenu !== null && root.currentMenu === tile.modelData.menu

                x: tile.index * (root.tileWidth + root.spacing)
                width: root.tileWidth
                height: root.tileHeight
                radius: height / 2
                color: tile.menuOpen ? Colors.alpha(Colors.primary, 0.22)
                     : tileArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.14)
                     : Colors.alpha(Colors.fgSurface, 0.08)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: root.compact ? (tile.width - 20) / 2 : 14
                        right: parent.right
                        rightMargin: root.compact ? 0 : 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 10
                    opacity: tile.passive ? 0.55 : 1

                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 20
                        source: tile.modelData.icon
                        scale: tileArea.containsMouse ? 1.1 : 1

                        Behavior on scale {
                            NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.compact
                        width: parent.width - 30 - (tile.attention ? 14 : 0)
                        text: root.nameOf(tile.modelData)
                        elide: Text.ElideRight
                        font.family: Config.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: tile.menuOpen ? Colors.primary : Colors.fgBackground
                    }
                }

                // "Braucht Aufmerksamkeit"
                Rectangle {
                    anchors {
                        right: parent.right
                        rightMargin: root.compact ? 6 : 14
                        top: root.compact ? parent.top : undefined
                        topMargin: 7
                        verticalCenter: root.compact ? undefined : parent.verticalCenter
                    }
                    visible: tile.attention
                    width: 7
                    height: 7
                    radius: 3.5
                    color: Colors.primary
                }

                MouseArea {
                    id: tileArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onClicked: event => {
                        if (event.button === Qt.LeftButton) {
                            root.closeMenu();
                            tile.modelData.activate();
                        } else if (event.button === Qt.MiddleButton) {
                            tile.modelData.secondaryActivate();
                        } else if (tile.menuOpen) {
                            root.closeMenu();
                        } else if (tile.modelData.hasMenu) {
                            root.openMenuFor(tile.modelData, tile);
                        } else {
                            tile.modelData.secondaryActivate();
                        }
                    }

                    onContainsMouseChanged: root.syncMenuHover()
                }
            }
        }

    }

    // ---- Menue ----
    // Schliesst, wenn Kachel und Menue eine Weile ohne Zeiger sind
    function syncMenuHover(): void {
        if (menuHover.hovered)
            closeGrace.stop();
        else if (root.currentMenu !== null)
            closeGrace.restart();
    }

    Timer {
        id: closeGrace

        interval: 700
        onTriggered: root.closeMenu()
    }

    PopupWindow {
        id: menuPopup

        anchor.window: root.QsWindow.window
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 0
        grabFocus: false
        visible: root.currentMenu !== null && trayMenu.ready
        color: "transparent"

        implicitWidth: trayMenu.implicitWidth
        implicitHeight: trayMenu.implicitHeight

        onVisibleChanged: trayMenu.shown = menuPopup.visible

        HoverHandler {
            id: menuHover

            onHoveredChanged: root.syncMenuHover()
        }

        TrayMenu {
            id: trayMenu

            onCloseRequested: root.closeMenu()
        }
    }
}
