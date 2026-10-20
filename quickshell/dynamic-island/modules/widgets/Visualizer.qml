pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.audio

// Kleiner Audio-Visualiser aus Cava-Pegeln – fuer die Medien-Pille und die
// Live-Activity der Notch.
//
//     Visualizer { count: 5; barWidth: 3; height: 16; active: Media.playing }
//
// Gespiegelt wie eine Wellenform: der Bass sitzt in der Mitte, nach aussen
// folgen die hoeheren Baender, die Balken wachsen aus der Mitte nach oben und
// unten. Fruehere Fassung mittelte linear ueber alle 36 Baender – die oberen
// Gruppen sind bei Musik fast immer leer, es bewegte sich nur ein Balken.
// Hier werden nur die unteren `range` der Baender genutzt und die hoeheren
// Positionen verstaerkt.
//
// Ohne Wiedergabe (`active: false`) stehen die Balken als ruhiger Bogen und
// gedimmt da, statt zu einer Punktreihe zusammenzufallen.
Item {
    id: root

    property int count: 5
    property real barWidth: 3
    property real spacing: 2
    property color color: Colors.primary
    // Laeuft Musik? Steuert Pegel vs. Ruhebogen
    property bool active: true
    // Anteil der Cava-Baender, der ueberhaupt angezeigt wird (von unten)
    property real range: 0.7
    // Verstaerkung je Schritt von der Mitte nach aussen (Hoehen sind leiser)
    property real tilt: 0.45

    // Nur der Monitor im Fokus aktualisiert den Pegel-Snapshot. Auf allen
    // anderen Monitoren bleiben die Balken auf dem letzten Stand stehen.
    //
    // Grund: die Shell laeuft auf der iGPU, der Compositor auf der dGPU –
    // jeder Frame der Shell muss also ueber PCIe kopiert werden, und
    // Hyprland rendert pro Layer-Frame den GESAMTEN Output neu (5040x1920
    // bei vier Monitoren). Vier Monitore x 30 Hz Cava waren deshalb 120
    // Frames/s und genau die GPU-Auslastung, die man beim Oeffnen der Insel
    // als Spike zu spueren bekommt.
    property bool live: true
    property var snapshot: []

    // Kurz nach einem Wechsel zwischen Ruhebogen und Pegeln darf die Hoehe
    // animiert werden – danach nicht mehr (siehe Behavior unten).
    property bool transitioning: false
    onActiveChanged: {
        root.transitioning = true;
        transitionTimer.restart();
    }
    Timer {
        id: transitionTimer
        interval: Appearance.morphDuration
        onTriggered: root.transitioning = false
    }

    Connections {
        target: Cava
        function onValuesChanged(): void {
            if (root.live)
                root.snapshot = Cava.values;
        }
    }

    onLiveChanged: if (root.live) root.snapshot = Cava.values

    Component.onCompleted: root.snapshot = Cava.values

    // Positionen von der Mitte aus: bei 5 Balken 0 (Mitte), 1, 2
    readonly property int positions: Math.ceil(root.count / 2)

    implicitWidth: root.count * root.barWidth + (root.count - 1) * root.spacing
    implicitHeight: 16

    // Pegel einer Position, 0..1
    function level(pos: int): real {
        const vals = root.snapshot.length > 0 ? root.snapshot : Cava.values;
        const usable = Math.max(root.positions, Math.floor(vals.length * root.range));
        const size = usable / root.positions;
        const from = Math.floor(pos * size);
        const to = Math.max(from + 1, Math.floor((pos + 1) * size));

        let sum = 0;
        for (let k = from; k < to && k < vals.length; k++)
            sum += vals[k];
        const avg = sum / (to - from);
        // Leise Pegel anheben, damit auch ruhige Stellen sichtbar arbeiten
        return Math.min(1, Math.pow(avg * (1 + pos * root.tilt), 0.6));
    }

    Repeater {
        model: root.count

        Rectangle {
            id: bar

            required property int index

            readonly property int pos: Math.round(Math.abs(bar.index - (root.count - 1) / 2))
            // Ruhebogen: Mitte am hoechsten, aussen flacher
            readonly property real idle: root.positions > 1
                ? 0.5 - 0.28 * bar.pos / (root.positions - 1)
                : 0.4
            // Nur sichtbare Balken folgen cava: `visible` ist die effektive
            // Sichtbarkeit (auch versteckte Eltern zaehlen). Versteckte
            // Visualiser (Pille im Notch-Layout, zugeklappte Uebersicht)
            // rechnen und animieren sonst 30x pro Sekunde fuer niemanden.
            readonly property real value: root.active && root.visible ? root.level(bar.pos) : bar.idle

            x: bar.index * (root.barWidth + root.spacing)
            y: (root.height - height) / 2
            width: root.barWidth
            height: Math.max(root.barWidth, bar.value * root.height)
            radius: root.barWidth / 2
            color: root.color
            opacity: root.active ? 1 : 0.4

            // Nur der Wechsel zwischen Ruhebogen und Pegeln wird animiert.
            //
            // Wichtig: die Animation darf NICHT bei jeder Pegel-Aktualisierung
            // laufen. Eine laufende Animation liess die ganze Shell mit der
            // Monitorrate neu zeichnen (jeder Frame = Layer-Update =
            // PCIe-Kopie zur dGPU + Hyprland rendert den Output neu). Statt
            // einer Behavior auf `height` laeuft die Animation deshalb nur
            // kurz nach einem Wechsel von `active` – der Ruhebogen-Wechsel
            // bleibt weich, die Pegel selbst springen direkt.
            Behavior on height {
                enabled: root.visible && root.transitioning
                NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration }
            }
        }
    }
}
