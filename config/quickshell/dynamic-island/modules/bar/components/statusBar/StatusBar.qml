pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

import qs
import qs.modules.widgets

// Systemtray im Settings-Stil: Pille mit Border, kollabiert auf einen Kreis,
// Hover klappt nach links auf. Ab `maxVisible` Icons wird die Reihe scrollbar
// statt breiter.
// Menüs: eigenes PopupWindow + TrayMenu (kein Wayland-Grab) -> Hover-Öffnen
// mit Delay UND Schließen-beim-Verlassen funktionieren beide.
// Optik (Verlauf, Rand, Schatten) kommt von Surface.
Surface {
    id: root

    // Schnittstelle (Bar.qml setzt verticalMargin / borderWidth – wie bei Settings)
    required property real verticalMargin

    readonly property real iconSize: 16
    readonly property real padding: 7      // 7 + 16 + 7 = 30 = Höhe -> kollabiert exakt Kreis
    readonly property real iconSpacing: 12 // Luft zwischen den Tray-Icons
    readonly property int maxVisible: 6    // mehr Icons -> scrollen statt wachsen

    // Rangfolge für den eingeklappten Kreis: das erste vorhandene Item dieser
    // Liste bekommt den Platz. Gematcht wird gegen id/title/tooltip (klein).
    readonly property var priority: ["discord", "nordvpn", "spotify", "steam"]

    // Sortiert: wichtigstes Item ganz rechts – dort bleibt beim Einklappen der
    // Kreis stehen. Nach links folgen NordVPN, Spotify, Steam, dann der Rest.
    readonly property var trayItems: {
        const rank = item => {
            const hay = ((item.id ?? "") + " " + (item.title ?? "") + " " + (item.tooltipTitle ?? "")).toLowerCase();
            const i = root.priority.findIndex(p => hay.includes(p));
            return i < 0 ? root.priority.length : i;
        };
        return [...SystemTray.items.values].sort((a, b) => rank(b) - rank(a));
    }
    readonly property var current: trayItems.length ? trayItems[trayItems.length - 1] : null

    // Breite der sichtbaren Icon-Reihe (gedeckelt auf maxVisible Icons)
    readonly property real rowViewWidth: Math.min(trayRow.implicitWidth,
                                                  maxVisible * iconSize + (maxVisible - 1) * iconSpacing)
    // Verschiebung der Reihe nach rechts -> zeigt die weiter links liegenden Icons
    property real trayScroll: 0
    readonly property real maxScroll: Math.max(0, trayRow.implicitWidth - rowViewWidth)

    // Pille bleibt während der Schonfrist offen, damit sie beim Verlassen des
    // Menüs nicht vorzeitig zuschnappt.
    readonly property bool expanded: hover.hovered || menuHover.hovered || closeGrace.running
    property var currentMenu: null         // QsMenuHandle des offenen Menüs

    anchors {
        verticalCenter: parent.verticalCenter
    }
    implicitWidth: expanded ? rowViewWidth + padding * 2 : height
    height: parent.height - verticalMargin   // flach -> Surface rundet zum Kreis

    onExpandedChanged: if (!expanded) trayScroll = 0

    Morph on implicitWidth {}
    Behavior on trayScroll {
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: root.syncMenuHover()
    }

    // Mausrad scrollt die Icon-Reihe, wenn mehr als maxVisible Icons da sind
    WheelHandler {
        enabled: root.maxScroll > 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const step = root.iconSize + root.iconSpacing;
            const delta = (event.angleDelta.y + event.angleDelta.x) / 120;
            root.trayScroll = Math.max(0, Math.min(root.maxScroll, root.trayScroll - delta * step));
        }
    }

    // Öffnen (Icon als Anker) / Schließen; closeGrace = Schonfrist, damit das
    // Menü nicht sofort zuklappt, wenn man es kurz verlässt.
    function openMenuFor(handle: var, entry: var): void {
        if (!handle)
            return;
        menuPopup.anchor.item = entry;
        currentMenu = handle;
        trayMenu.open(handle);
        closeGrace.stop();
    }

    function closeMenu(): void {
        currentMenu = null;   // visible-Binding schliesst das Popup damit selbst
    }

    function syncMenuHover(): void {
        if (hover.hovered || menuHover.hovered)
            closeGrace.stop();
        else if (root.currentMenu !== null)
            closeGrace.restart();
    }

    Timer {
        id: closeGrace
        interval: 400
        onTriggered: root.closeMenu()
    }

    Row {
        id: trayRow
        anchors {
            right: parent.right                        // fix rechts -> Wachstum nach links
            rightMargin: root.padding - root.trayScroll
            verticalCenter: parent.verticalCenter
        }
        spacing: root.iconSpacing

        Repeater {
            model: root.trayItems

            MouseArea {
                id: trayEntry

                required property SystemTrayItem modelData
                // Icon, dessen Menü gerade offen ist -> wird leicht hervorgehoben
                readonly property bool active: root.currentMenu !== null && root.currentMenu === trayEntry.modelData.menu

                implicitWidth: root.iconSize
                implicitHeight: root.iconSize
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true

                // kollabiert: nur das wichtigste Item bleibt sichtbar
                opacity: root.expanded || trayEntry.modelData === root.current ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }

                // Hover mit Verzögerung -> Menü öffnen; hier lebt der Sensor,
                // weil das eigene Popup keinen Grab hat. Ist schon ein Menü
                // offen, wechselt der Hover zügiger (Menüleisten-Verhalten).
                onEntered: if (trayEntry.modelData.hasMenu && !trayEntry.active) hoverTimer.restart()
                onExited: hoverTimer.stop()

                Timer {
                    id: hoverTimer
                    interval: root.currentMenu !== null ? 140 : 300
                    onTriggered: {
                        if (trayEntry.containsMouse && !trayEntry.active)
                            root.openMenuFor(trayEntry.modelData.menu, trayEntry);
                    }
                }

                onClicked: event => {
                    if (event.button === Qt.LeftButton) {
                        trayEntry.modelData.activate();
                        root.closeMenu();
                    } else if (!trayEntry.modelData.hasMenu) {
                        trayEntry.modelData.secondaryActivate();
                    } else if (trayEntry.active) {
                        root.closeMenu();
                    } else {
                        root.openMenuFor(trayEntry.modelData.menu, trayEntry);
                    }
                }

                IconImage {
                    anchors.fill: parent
                    source: trayEntry.modelData.icon
                    scale: trayEntry.active || trayEntry.containsMouse ? 1.15 : 1

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                    }
                }
            }
        }
    }

    // Weiche Kante links, solange noch Icons ausserhalb liegen
    Rectangle {
        anchors {
            left: parent.left
            leftMargin: root.borderWidth
            top: parent.top
            bottom: parent.bottom
        }
        width: 16
        visible: root.expanded && root.trayScroll < root.maxScroll - 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Colors.background }
            GradientStop { position: 1; color: Colors.alpha(Colors.background, 0) }
        }
    }

    // ---- Eigenes Menü-Popup (kein Grab -> Hover bleibt lebendig) ----
    // margins.top bleibt 0: den optischen Abstand liefert die transparente
    // "bridge" im TrayMenu – so ist der Weg vom Icon zur Karte lückenlos
    // vom Popup abgedeckt und der Hover reißt unterwegs nicht ab.
    PopupWindow {
        id: menuPopup

        anchor.window: root.QsWindow.window
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 0
        grabFocus: false
        // erst zeigen, wenn die D-Bus-Einträge der ersten Seite da sind
        visible: root.currentMenu !== null && trayMenu.ready
        color: "transparent"

        implicitWidth: trayMenu.implicitWidth
        implicitHeight: trayMenu.implicitHeight

        // Einblend-Animation erst starten, wenn das Fenster wirklich da ist
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
