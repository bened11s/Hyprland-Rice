pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config

// Ausklapp-Inhalt der Notch: Monat + Tagesstreifen als Karussell.
// Bringt alles Datums-Bezogene selbst mit – Datumsrechnung, Gesten (Rad und
// Ziehen), Einschub-Animation und die eigene Einrückung in der Karte. Die Notch
// sagt nur, wo es anfängt (`topOffset`) und worauf die Gesten gelten sollen.
Item {
    id: panel

    // ---- Schnittstelle zur Notch ----
    // Oberkante innerhalb der Karte (= Unterkante des Uhr-Bands)
    property real topOffset: 0
    // Rundung der Karte; die Vignette folgt ihr, sonst füllt sie die Ecken
    // wieder rechteckig auf
    property real cardRadius: 18
    // Abstand zur Kartenkante, damit Rand und Ecken frei bleiben
    property real inset: 2
    // Fläche fürs Mausrad. Ohne Zuweisung gilt nur das Panel selbst – die Notch
    // reicht ihre ganze Karte rein, sonst passiert nichts, solange der Zeiger
    // noch über der Uhr steht. Gezogen wird dagegen nur im Datumsstreifen
    // (siehe DragHandler unten).
    property Item gestureArea: panel
    // Von außen abschaltbar – die Notch legt das Ziehen still, solange ihre
    // eigene Geste (Launcher aufziehen) läuft.
    property bool dragEnabled: true
    // Grundton der Karte, in den die Randverlaeufe auslaufen (die angedockte
    // Notch ist schwarz, die Insel hat den Theme-Hintergrund)
    property color fadeColor: Colors.background

    // Platz, den die Karte für das Panel bereithalten muss
    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    // Damit die Notch beim Ziehen nicht zuklappt
    readonly property bool dragging: dragHandler.active

    // ---- Datum ----
    // Verschiebung gegenüber heute, in Tagen. Die Notch setzt das beim
    // Zuklappen zurück.
    property int dayOffset: 0

    readonly property date today: dateSource.date
    readonly property date focusDay: panel.addDays(today, dayOffset)

    // Von aussen einstellbar: die angedockte Notch ist breiter und zeigt mehr Tage
    property real columnWidth: 26
    readonly property real columnSpacing: 2
    readonly property real step: columnWidth + columnSpacing
    property int visibleColumns: 7
    // gerendert wird -n..+n (eine mehr als sichtbar), außen frisst die Vignette
    property int sideColumns: Math.ceil(visibleColumns / 2)
    readonly property real topPadding: 8

    // Pixel-Versatz für die Einschub-Animation (siehe onDayOffsetChanged)
    property real slide: 0
    property int lastOffset: 0

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset
    implicitWidth: visibleColumns * columnWidth + (visibleColumns - 1) * columnSpacing + 12
    implicitHeight: strip.y + strip.height + 10
    clip: true

    function shiftDays(days: int): void {
        panel.dayOffset += days;
    }

    function addDays(from: date, days: int): date {
        return new Date(from.getFullYear(), from.getMonth(), from.getDate() + days);
    }

    // Der Inhalt springt sofort um einen Tag, der Streifen startet dafür um
    // eine Spalte versetzt und fährt zurück auf 0 -> sieht aus wie geschoben.
    onDayOffsetChanged: {
        const delta = panel.dayOffset - panel.lastOffset;
        panel.lastOffset = panel.dayOffset;
        panel.slide = Math.max(-2 * panel.step, Math.min(2 * panel.step, panel.slide + delta * panel.step));
        slideAnim.restart();
    }

    NumberAnimation {
        id: slideAnim

        target: panel
        property: "slide"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic
    }

    SystemClock {
        id: dateSource
        precision: SystemClock.Minutes   // reicht, um den Tageswechsel mitzubekommen
    }

    // ---- Gesten ----
    WheelHandler {
        id: wheel

        parent: panel.gestureArea       // Trefferfläche, nicht Eltern-Objekt im QML-Baum
        enabled: panel.visible
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        // Hi-Res-Räder (z.B. G502 im Free-Spin) liefern Bruchteile einer
        // Rastung pro Event. Einzeln gerundet wäre das immer 0 -> es würde gar
        // nichts passieren. Deshalb aufsummieren und erst bei einer vollen
        // Rastung einen Tag weiterschalten.
        property real accum: 0

        onWheel: event => {
            const angle = event.angleDelta.y + event.angleDelta.x;
            const pixels = event.pixelDelta.y + event.pixelDelta.x;
            wheel.accum += angle !== 0 ? angle / 120 : pixels / 40;

            const steps = wheel.accum > 0 ? Math.floor(wheel.accum) : Math.ceil(wheel.accum);
            if (steps !== 0) {
                wheel.accum -= steps;
                panel.shiftDays(-steps);
            }
            event.accepted = true;
        }
    }

    DragHandler {
        id: dragHandler

        parent: panel                 // das ganze Datumsfeld, aber nicht das Uhr-Band darüber
        enabled: panel.visible && panel.dragEnabled
        target: null                    // nur Geste, nichts wird verschoben
        yAxis.enabled: false

        property int startOffset: 0

        onActiveChanged: if (active) startOffset = panel.dayOffset
        onTranslationChanged: {
            if (!dragHandler.active)
                return;
            panel.dayOffset = dragHandler.startOffset - Math.round(dragHandler.activeTranslation.x / panel.step);
        }
    }

    // ---- Inhalt ----
    Text {
        id: header
        font.family: Config.font

        anchors.horizontalCenter: parent.horizontalCenter
        y: panel.topPadding
        text: panel.focusDay.toLocaleDateString(I18n.locale, "MMMM yyyy")
        color: Colors.fgSurfaceVariant
        font.pixelSize: 10
        font.weight: Font.Medium
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.8
    }

    Row {
        id: strip

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: panel.slide
        y: header.y + header.implicitHeight + 7
        height: 40
        spacing: panel.columnSpacing

        Repeater {
            model: panel.sideColumns * 2 + 1

            DayColumn {
                required property int index

                width: panel.columnWidth
                height: strip.height

                offset: index - panel.sideColumns
                day: panel.addDays(panel.focusDay, offset)
                today: panel.today
            }
        }
    }

    EdgeFade {
        anchors {
            left: parent.left
            top: strip.top
            bottom: parent.bottom
        }
        cornerRadius: panel.cardRadius - panel.inset
        baseColor: panel.fadeColor
    }

    EdgeFade {
        anchors {
            right: parent.right
            top: strip.top
            bottom: parent.bottom
        }
        mirrored: true
        cornerRadius: panel.cardRadius - panel.inset
        baseColor: panel.fadeColor
    }
}
