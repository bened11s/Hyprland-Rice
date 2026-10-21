// Audio-Peak-Visualizer direkt ueber PipeWire (kein cava noetig)
// Nutzt PwNodePeakMonitor auf dem Default-Sink und zeichnet Balken.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Item {
    id: root

    // ============================================================
    // PUFFER: Balkenanzahl folgt der BREITE
    // Vorher stand hier fest 28 (= 138 px Inhalt) bei 120 px Breite -
    // die Balken liefen nach rechts ueber und klebten am Media-Widget.
    // ============================================================

    readonly property int barWidth: 3
    readonly property int barGap: 2

    readonly property int barCount: {
        if (width <= 0)
            return 28

        return Math.max(8, Math.floor((width + barGap) / (barWidth + barGap)))
    }

    property var levels: new Array(barCount).fill(0)

    // Defensiv: barCount kann sich aendern, dann ist der Puffer kuerzer
    function levelFor(i) {
        return i < levels.length ? levels[i] : 0
    }

    // ============================================================
    // SINK + PEAKS
    // ============================================================

    readonly property var sinkNode: Pipewire.defaultAudioSink

    PwNodePeakMonitor {
        id: monitor

        node: root.sinkNode

        // Muss explizit aktiviert werden
        enabled: root.sinkNode !== null
    }

    // ============================================================
    // LEVELS AUS PEAKS -> BALKEN
    // ============================================================

    Timer {
        interval: 60
        running: root.sinkNode !== null
        repeat: true

        onTriggered: {
            let out = new Array(root.barCount).fill(0)

            // peaks: [-1.0 .. 1.0] je Kanal, typisch 2 (links/rechts)
            let peaks = monitor.peaks

            if (peaks && peaks.length > 0) {
                for (let i = 0; i < root.barCount; i++) {
                    // Peaks auf BAEKEN abbilden, Indizes zyklisch
                    let p = peaks[i % peaks.length]
                    let v = Math.abs(p)

                    // Leichte Kompression, damit es nicht komplett klebt
                    v = Math.pow(v, 0.65)

                    // Sanftes Abklingen statt hartem Ausschneiden
                    out[i] = Math.max(v, root.levelFor(i) * 0.72)
                }
            } else {
                // Stille: alles ausblenden
                for (let i = 0; i < root.barCount; i++)
                    out[i] = root.levelFor(i) * 0.85
            }

            root.levels = out
        }
    }

    // ============================================================
    // ZEICHNEN
    // ============================================================

    Row {
        anchors.fill: parent
        spacing: root.barGap

        Repeater {
            model: root.barCount

            delegate: Rectangle {
                required property int index

                width: root.barWidth
                height: Math.max(2, parent.height * root.levelFor(index))
                radius: 1.5

                color: {
                    // Tokyo-Night-Verlauf: cyan -> blue -> purple
                    let h = root.levelFor(index)

                    if (h > 0.66)
                        return "#bb9af7"
                    if (h > 0.33)
                        return "#7aa2f7"
                    return "#7dcfff"
                }

                // Von unten nach oben wachsen
                anchors.bottom: parent.bottom
            }
        }
    }

    // ============================================================
    // KEIN SINK / STILLE -> ausblenden
    // ============================================================

    opacity: root.sinkNode !== null ? 1 : 0
}