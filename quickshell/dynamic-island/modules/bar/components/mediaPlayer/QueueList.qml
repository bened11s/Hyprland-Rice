pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.services.media

import qs

// Die aufgeklappte Warteschlange: alle weiteren Titel nach "Als Naechstes"
// (MediaQueue.next ab Index 1) als kompakte Zeilen mit Positionsnummer.
// Hoechstens `maxRows` Zeilen sind zu sehen, darueber hinaus scrollt die
// Liste (Mausrad gleitet, Touchpad geht direkt – wie NotificationsPanel).
// Ein Klick springt zu dem Titel (MediaQueue.skipTo).
//
// Die Hoehe rechnet die Liste selbst aus der Zeilenzahl aus; animiert wird
// sie nicht hier, sondern vom Block drumherum in MediaPanel – so laeuft
// beim Auf- und Zuklappen eine einzige Animation.
ListView {
    id: list

    property color tint: Colors.background
    property int maxRows: 6
    readonly property real rowHeight: 32
    readonly property int extra: Math.max(0, MediaQueue.next.length - 1)
    readonly property real wantedHeight: Math.min(list.maxRows, list.extra) * (list.rowHeight + list.spacing)

    // Ab Index 1: der erste steht schon als "Als Naechstes" darueber
    model: ScriptModel {
        values: MediaQueue.next.slice(1)
    }
    // Kein Highlight-Nachfuehren (siehe LauncherPanel.qml)
    highlightFollowsCurrentItem: false

    clip: true
    spacing: 1
    boundsBehavior: Flickable.StopAtBounds
    // Senkrecht gehoert das Rad der Liste, waagerecht dem Notch-Blaettern
    interactive: false

    delegate: QueueRow {
        id: entry

        required property var modelData
        required property int index

        width: list.width
        compact: true
        track: entry.modelData
        number: entry.index + 2
        tint: list.tint
        onTriggered: MediaQueue.skipTo(entry.index + 1)
    }

    // ---- Mausrad ----
    property real targetY: 0

    NumberAnimation {
        id: scrollAnim

        target: list
        property: "contentY"
        duration: 180
        easing.type: Easing.OutCubic
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: event => {
            const angle = event.angleDelta.y;
            const pixels = event.pixelDelta.y;
            if (angle === 0 && pixels === 0) {
                event.accepted = false;
                return;
            }
            event.accepted = true;
            const max = Math.max(0, list.contentHeight - list.height);

            if (pixels !== 0) {
                scrollAnim.stop();
                list.contentY = Math.max(0, Math.min(max, list.contentY - pixels));
                list.targetY = list.contentY;
                return;
            }

            if (!scrollAnim.running)
                list.targetY = list.contentY;
            list.targetY = Math.max(0, Math.min(max, list.targetY - angle / 120 * (list.rowHeight + list.spacing) * 2));
            scrollAnim.to = list.targetY;
            scrollAnim.restart();
        }
    }
}
