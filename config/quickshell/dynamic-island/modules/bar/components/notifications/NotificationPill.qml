pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services.notifications

import qs
import qs.modules.services.config
import qs.modules.widgets

// Benachrichtigungs-Pille links neben der Medien-Karte.
//
// Drei Zustaende:
//   eingeklappt  Kreis mit Glocke und Anzahl-Badge
//   breit        waechst nach links auf und zeigt die neueste Nachricht
//                (beim Hovern – oder von selbst, wenn eine neue eintrifft)
//   offen        Zug nach unten: darunter die Liste aller Nachrichten
//
// Das horizontale Wachsen ist nach der StatusBar gebaut (Inhalt haengt rechts
// fest, die Karte wird nach links breiter), das Aufklappen nach unten nach der
// Medien-Karte (DragHandler mit Latch, y fest statt verticalCenter).
//
// Die Anker setzt Bar.qml – die Pille haengt rechts an der Medien-Karte und
// waechst deshalb in die freie Luecke daneben hinein.
Item {
    id: root

    required property real verticalMargin
    required property real borderWidth
    required property color borderColor
    required property real cardRadius

    readonly property real collapsedSize: parent.height - verticalMargin
    readonly property real peekWidth: 340
    readonly property real openWidth: 380
    readonly property real maxListHeight: 300
    // Hoehe der Liste im eingeklappten Zustand der Gruppen: je Gruppe eine
    // Zeile, bei mehreren Nachrichten zusaetzlich der Kopf. Bewusst aus dem
    // Modell gerechnet statt aus `list.contentHeight` – daran haengt die
    // Karte, und die Karte gibt der Liste ihre Hoehe, das waere eine
    // Bindungsschleife. Aufgeklappte Gruppen scrollen stattdessen.
    readonly property real listBody: {
        let h = 0;
        for (const g of Notifications.groups) {
            h += g.entries.length > 1 ? 26 : 0;          // Gruppenkopf
            // Zeile, bei Aktionsknoepfen eine Reihe hoeher
            h += Notifications.actionButtons(g.entries[0]).length > 0 ? 86 : 54;
        }
        return h;
    }
    // Nach unten gedeckelt, damit die Karte bei leerer Liste nicht in sich
    // zusammenfaellt: wer die Maus dorthin bewegt, wo gleich Inhalt
    // erscheint, waere sonst schon draussen (Falle aus dem WLAN-Panel).
    readonly property real listHeight: Math.max(90, Math.min(root.maxListHeight, root.listBody))
    readonly property real openHeight: root.collapsedSize + root.listHeight + 8

    // Liste offen bzw. Pille zeigt gerade die neueste Nachricht
    property bool open: false
    property bool peek: false

    readonly property bool wide: root.open || root.peek || hover.hovered
    // Platz, den sich das Bar-Fenster nach unten nehmen muss
    // Reserve im Bar-Fenster: immer der groesste Fall, nicht die aktuelle
    // Hoehe – sonst muesste das Fenster mit jeder Nachricht mitwachsen
    readonly property real maxDrop: Math.max(0, root.verticalMargin / 2
        + root.collapsedSize + root.maxListHeight + 8 - parent.height)

    y: root.verticalMargin / 2
    width: root.open ? root.openWidth : root.wide ? root.peekWidth : root.collapsedSize
    height: root.open ? root.openHeight : root.collapsedSize

        Morph on width {}
    Morph on height {}

    // Neue Nachricht: kurz aufklappen, dann wieder zu. Wie lange, sagt die
    // Nachricht selbst (expireTimeout), sonst die Einstellung; begrenzt auf
    // 2-15 Sekunden.
    Connections {
        target: Notifications

        function onArrived(entry: var): void {
            const timeout = entry?.notif?.expireTimeout ?? 0;
            const fallback = Config.notifications.peekSeconds * 1000;
            peekTimer.interval = Math.min(15000, Math.max(2000, timeout > 0 ? timeout : fallback));
            root.peek = true;
            peekTimer.restart();
        }
    }

    Timer {
        id: peekTimer

        interval: 5000
        onTriggered: root.peek = false
    }

    // Nachlauf beim Wegfahren – offen darf es etwas laenger dauern, damit die
    // Maus ueber die Liste wandern kann
    Timer {
        id: closeTimer

        interval: root.open ? 800 : 400
        onTriggered: {
            root.peek = false;
            root.open = false;
        }
    }

    Surface {
        id: pill

        anchors.fill: parent

        maxRadius: root.cardRadius
        borderWidth: root.borderWidth
        borderColor: root.borderColor

        HoverHandler {
            id: hover

            onHoveredChanged: {
                if (hovered) {
                    closeTimer.stop();
                    peekTimer.stop();
                } else {
                    closeTimer.restart();
                }
            }
        }

        // Zug nach unten oeffnet die Liste (Muster aus der Medien-Karte)
        DragHandler {
            id: openDrag

            target: null
            xAxis.enabled: false
            enabled: !root.open

            readonly property real threshold: 18
            property bool triggered: false

            onActiveChanged: if (!openDrag.active)
                openDrag.triggered = false
            onTranslationChanged: {
                if (!openDrag.active || openDrag.triggered)
                    return;
                if (openDrag.activeTranslation.y > openDrag.threshold) {
                    openDrag.triggered = true;
                    root.open = true;
                }
            }
        }

        // ---- Glocke mit Badge (bleibt rechts stehen) ----
        Item {
            id: bell

            anchors {
                right: parent.right
                top: parent.top
            }
            width: root.collapsedSize
            height: root.collapsedSize

            Text {
                anchors.centerIn: parent

                text: Notifications.dnd ? "notifications_off"
                    : Notifications.count > 0 ? "notifications_active" : "notifications"
                color: Notifications.count > 0 ? Colors.primary : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16

                Behavior on color {
                    ColorAnimation { duration: 140 }
                }
            }

            // Badge oben rechts – bewusst INNERHALB des Kreises, die Karte
            // schneidet ab (clip), ein ueberstehendes Badge waere weg.
            Rectangle {
                anchors {
                    right: parent.right
                    top: parent.top
                    rightMargin: 2.5
                    topMargin: 2.5
                }
                width: 14
                height: 14
                radius: height / 2
                color: Colors.primary
                opacity: Notifications.count > 0 ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }

                Text {
                    font.family: Config.font
                    anchors.centerIn: parent
                    text: Notifications.count > 9 ? "9+" : Notifications.count
                    color: Colors.fgPrimary
                    font.pixelSize: 8
                    font.weight: Font.DemiBold
                }
            }

            // Klick auf die Glocke klappt die Liste auf und zu
            TapHandler {
                onTapped: root.open = !root.open
            }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
        }

        // ---- Breiter Zustand: die neueste Nachricht ----
        NotificationRow {
            id: peekRow

            anchors {
                left: parent.left
                leftMargin: 12
                right: bell.left
                rightMargin: 2
                top: parent.top
            }
            height: root.collapsedSize

            compact: true
            swipeable: true      // seitlich wegziehen geht auch hier
            entry: Notifications.latest
            opacity: root.wide && !root.open && Notifications.count > 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }

        Text {
            font.family: Config.font
            anchors {
                left: parent.left
                leftMargin: 14
                right: bell.left
                top: parent.top
            }
            height: root.collapsedSize
            verticalAlignment: Text.AlignVCenter

            text: Notifications.dnd ? I18n.tr("Nicht stören") : I18n.tr("Keine Benachrichtigungen")
            color: Colors.fgSurfaceVariant
            font.pixelSize: 11
            elide: Text.ElideRight
            opacity: root.wide && !root.open && Notifications.count === 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }

        // ---- Offener Zustand: Kopfzeile ----
        Item {
            id: header

            anchors {
                left: parent.left
                right: bell.left
                top: parent.top
            }
            height: root.collapsedSize
            opacity: root.open ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Text {
                font.family: Config.font
                anchors {
                    left: parent.left
                    leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                text: Notifications.count > 0 ? I18n.tr("Benachrichtigungen · %1").arg(Notifications.count)
                                              : I18n.tr("Benachrichtigungen")
                color: Colors.fgBackground
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Rectangle {
                anchors {
                    right: parent.right
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                width: 26
                height: 26
                radius: height / 2
                color: clearArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.14) : "transparent"
                opacity: Notifications.count > 0 ? 1 : 0.35

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }

                Text {
                    anchors.centerIn: parent
                    text: "delete_sweep"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: clearArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: Notifications.count > 0
                    onClicked: Notifications.clear()
                }
            }
        }

        // ---- Offener Zustand: die Liste ----
        ListView {
            id: list

            anchors {
                top: bell.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 10
                rightMargin: 10
                bottomMargin: 8
            }
            clip: true
            spacing: 2
            model: ScriptModel {
                values: Notifications.groups
            }
            // Kein Highlight-Nachfuehren (siehe LauncherPanel.qml)
            highlightFollowsCurrentItem: false
            boundsBehavior: Flickable.StopAtBounds
            opacity: root.open ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;

                    const max = Math.max(0, list.contentHeight - list.height);
                    list.contentY = Math.max(0, Math.min(max, list.contentY - delta * 54));
                    event.accepted = true;
                }
            }

            delegate: NotificationGroup {
                width: ListView.view.width
            }

            Text {
                font.family: Config.font
                anchors.centerIn: parent
                visible: Notifications.count === 0

                text: I18n.tr("Nichts Neues")
                color: Colors.fgSurfaceVariant
                font.pixelSize: 12
            }
        }
    }
}
