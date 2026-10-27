pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config
import qs.modules.widgets.clock

// Uhr der Notch. Positioniert wird von der Notch (bleibt beim Aufklappen im
// oberen Band stehen); das Zifferblatt kommt aus modules/widgets/clock und
// folgt Config.notch.clockStyle (digital, split, analog).
Item {
    id: clock

    // Fuer Datumsanzeigen daneben (Notch-Layout), ohne zweite SystemClock
    readonly property date date: clockSource.date
    // Die Notch setzt und animiert die Farbe (Akzent beim Aufklappen)
    property color color: Colors.fgBackground

    implicitWidth: face.implicitWidth
    implicitHeight: face.implicitHeight
    width: implicitWidth
    height: implicitHeight

    ClockFace {
        id: face

        style: Config.notch.clockStyle
        date: clock.date
        // 13 pt des alten Text-Labels, in Pixel (96 dpi)
        size: 13 * 96 / 72
        color: clock.color
        accent: Colors.primary
    }

    // Eingebaute Uhr statt externem `date`-Prozess pro Sekunde
    SystemClock {
        id: clockSource
        precision: SystemClock.Minutes
    }
}
