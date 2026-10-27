pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs
import qs.modules.services.audio
import qs.modules.services.config

// Kleiner Audio-Visualiser aus Cava-Pegeln – fuer die Medien-Pille, die
// Live-Activity der Notch und gross als Desktop-Widget.
//
//     Visualizer { count: 5; barWidth: 3; height: 16; active: Media.playing }
//
// Vier Stile (`style`, ohne Angabe gilt Config.notch.visualizerStyle):
//   "spiegel"  gespiegelt wie eine Wellenform: der Bass sitzt in der Mitte,
//              nach aussen folgen die hoeheren Baender, die Balken wachsen
//              aus der Mitte nach oben und unten
//   "saeulen"  klassisches Spektrum, Balken wachsen von unten, Bass links
//   "punkte"   je Spalte ein Punkt, der mit dem Pegel steigt
//   "welle"    durchgehende Linie, um die Mitte gespiegelt
//
// Fruehere Fassung mittelte linear ueber alle 36 Baender – die oberen
// Gruppen sind bei Musik fast immer leer, es bewegte sich nur ein Balken.
// Hier werden nur die unteren `range` der Baender genutzt und die hoeheren
// Positionen verstaerkt. Mehr Spalten als nutzbare Baender (grosses Widget)
// werden zwischen den Baendern interpoliert statt leer zu bleiben.
//
// Ohne Wiedergabe (`active: false`) stehen die Pegel als ruhiger Bogen und
// gedimmt da, statt zu einer Punktreihe zusammenzufallen.
//
// Pegel werden waehrend der Wiedergabe NICHT animiert und auf ganze Pixel
// gerundet: eine 90-ms-Animation je Frame lief bei 30 cava-Frames/s ohne
// Pause und liess das ganze Leistenfenster mit der Monitorrate (180 Hz) neu
// zeichnen statt mit 30 Hz. Frames, die sich nur im Subpixel unterscheiden,
// aendern so nichts und loesen kein Neuzeichnen aus.
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
    // Verstaerkung je Schritt vom Bass weg (Hoehen sind leiser)
    property real tilt: 0.45
    // "" = Einstellung der Notch (Config.notch.visualizerStyle)
    property string style: ""
    // Feste Pegel statt Cava (0..1 je Band) – fuer Vorschauen, die keinen
    // Cava-Bedarf erzeugen sollen
    property var sample: null

    readonly property string effectiveStyle: root.style !== "" ? root.style : Config.notch.visualizerStyle
    readonly property bool mirrored: root.effectiveStyle === "spiegel"
    // Zahl der unterschiedlichen Pegel-Positionen: gespiegelt bei 5 Balken
    // 0 (Mitte), 1, 2 – sonst eine je Spalte
    readonly property int positions: root.mirrored ? Math.ceil(root.count / 2) : root.count
    // Nur sichtbare Visualiser folgen cava: `visible` ist die effektive
    // Sichtbarkeit (auch versteckte Eltern zaehlen). Versteckte (Pille im
    // Notch-Layout, zugeklappte Uebersicht) rechnen sonst 30x pro Sekunde
    // fuer niemanden.
    readonly property bool live: root.active && root.visible

    implicitWidth: root.count * root.barWidth + (root.count - 1) * root.spacing
    implicitHeight: 16

    // Pegel einer Position, 0..1
    function level(pos: int): real {
        const vals = root.sample !== null ? root.sample : Cava.values;
        if (!vals || !vals.length)
            return 0;
        const positions = root.positions;
        const usable = Math.max(1, Math.floor(vals.length * root.range));
        let avg;
        if (positions <= usable) {
            // Mehrere Baender je Spalte: Mittelwert
            const size = usable / positions;
            const from = Math.floor(pos * size);
            const to = Math.max(from + 1, Math.floor((pos + 1) * size));
            let sum = 0;
            for (let k = from; k < to && k < vals.length; k++)
                sum += vals[k];
            avg = sum / (to - from);
        } else {
            // Mehr Spalten als Baender: zwischen zwei Baendern interpolieren
            const f = positions > 1 ? pos / (positions - 1) * (usable - 1) : 0;
            const i = Math.floor(f);
            const t = f - i;
            avg = vals[i] * (1 - t) + vals[Math.min(i + 1, usable - 1)] * t;
        }
        // Verstaerkung: bei bis zu 4 Positionen je Schritt `tilt` (so wie
        // die Notch gemessen wurde), bei mehr ueber die Breite verteilt
        const steps = positions <= 4 ? pos : pos * 3 / (positions - 1);
        // Leise Pegel anheben, damit auch ruhige Stellen sichtbar arbeiten
        return Math.min(1, Math.pow(avg * (1 + steps * root.tilt), 0.6));
    }

    // Ruhebogen: Mitte am hoechsten, aussen flacher
    function idleArc(pos: int): real {
        return root.positions > 1 ? 0.5 - 0.28 * pos / (root.positions - 1) : 0.4;
    }
    // Ruhebogen fuer Spalten von links nach rechts: Huegel in der Mitte
    function idleHill(index: int): real {
        const t = root.count > 1 ? index / (root.count - 1) : 0.5;
        return 0.22 + 0.28 * Math.sin(t * Math.PI);
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.effectiveStyle === "saeulen" ? columns
                       : root.effectiveStyle === "punkte" ? dots
                       : root.effectiveStyle === "welle" ? wave
                       : mirror
    }

    // ---- "spiegel": Balken aus der Mitte nach oben und unten ----
    Component {
        id: mirror

        Item {
            Repeater {
                model: root.count

                Rectangle {
                    id: bar

                    required property int index

                    readonly property int pos: Math.round(Math.abs(bar.index - (root.count - 1) / 2))
                    readonly property real value: root.live ? root.level(bar.pos) : root.idleArc(bar.pos)

                    x: bar.index * (root.barWidth + root.spacing)
                    y: (root.height - height) / 2
                    width: root.barWidth
                    // Auf ganze Pixel je Seite gerundet (waechst nach oben und unten)
                    height: Math.max(root.barWidth, Math.round(bar.value * root.height / 2) * 2)
                    radius: root.barWidth / 2
                    color: root.color
                    opacity: root.active ? 1 : 0.4

                    // Nur der Wechsel in den Ruhebogen wird animiert, beim
                    // Spielen folgen die Balken cava direkt (siehe oben)
                    Behavior on height {
                        enabled: root.visible && !root.active
                        NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.fadeDuration }
                    }
                }
            }
        }
    }

    // ---- "saeulen": Spektrum von unten, Bass links ----
    Component {
        id: columns

        Item {
            Repeater {
                model: root.count

                Rectangle {
                    id: col

                    required property int index

                    readonly property real value: root.live ? root.level(col.index) : root.idleHill(col.index)

                    x: col.index * (root.barWidth + root.spacing)
                    y: root.height - height
                    width: root.barWidth
                    height: Math.max(root.barWidth, Math.round(col.value * root.height))
                    radius: root.barWidth / 2
                    color: root.color
                    opacity: root.active ? 1 : 0.4

                    Behavior on height {
                        enabled: root.visible && !root.active
                        NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.fadeDuration }
                    }
                }
            }
        }
    }

    // ---- "punkte": ein Punkt je Spalte, steigt mit dem Pegel ----
    Component {
        id: dots

        Item {
            id: dotsRow

            readonly property real diameter: Math.round(root.barWidth * 1.4)

            Repeater {
                model: root.count

                Rectangle {
                    id: dot

                    required property int index

                    readonly property real value: root.live ? root.level(dot.index) : root.idleHill(dot.index)

                    x: Math.round(dot.index * (root.barWidth + root.spacing) + (root.barWidth - width) / 2)
                    // unten = leise
                    y: Math.round((root.height - height) * (1 - dot.value))
                    width: dotsRow.diameter
                    height: dotsRow.diameter
                    radius: width / 2
                    color: root.color
                    opacity: root.active ? 1 : 0.4

                    Behavior on y {
                        enabled: root.visible && !root.active
                        NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.fadeDuration }
                    }
                }
            }
        }
    }

    // ---- "welle": Linie, um die Mitte gespiegelt ----
    Component {
        id: wave

        Shape {
            id: shape

            preferredRendererType: Shape.CurveRenderer
            opacity: root.active ? 1 : 0.4

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration }
            }

            // Stuetzpunkte: oben von links nach rechts, unten zurueck – als
            // geschlossene Flaeche mit Kontur. Zwischen den Spalten liegen
            // weich interpolierte Zwischenpunkte (Cosinus), damit die Linie
            // nicht zackt; y auf ganze Pixel gerundet.
            readonly property real mid: root.height / 2
            readonly property real amp: root.height / 2 - shape.stroke
            readonly property real stroke: Math.max(1, Math.round(root.barWidth * 0.7))
            readonly property int subdiv: root.count <= 12 ? 4 : 2
            readonly property var points: {
                const n = Math.max(2, root.count);
                const levels = [];
                for (let i = 0; i < n; i++)
                    levels.push(root.live ? root.level(i) : root.idleHill(i));
                const segs = (n - 1) * shape.subdiv;
                const stepX = root.width / segs;
                const top = [], bottom = [];
                for (let i = 0; i <= segs; i++) {
                    const f = i / shape.subdiv;
                    const k = Math.min(n - 2, Math.floor(f));
                    const t = f - k;
                    const w = (1 - Math.cos(t * Math.PI)) / 2;
                    const v = levels[k] * (1 - w) + levels[k + 1] * w;
                    const x = Math.round(i * stepX);
                    const y = Math.max(1, Math.round(v * shape.amp));
                    top.push(Qt.point(x, shape.mid - y));
                    bottom.push(Qt.point(x, shape.mid + y));
                }
                return top.concat(bottom.reverse(), [top[0]]);
            }

            ShapePath {
                strokeColor: root.color
                strokeWidth: shape.stroke
                fillColor: Colors.alpha(root.color, 0.16)
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap

                PathPolyline {
                    path: shape.points
                }
            }
        }
    }
}
