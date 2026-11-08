pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

import qs
import qs.modules.services.audio
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.services.media

// Musik auf dem Desktop. Stile:
//
//   insel    "Live Activity": schwarze Pille wie die Notch – Cover, Titel,
//            Interpret, rechts die gespiegelten Pegel
//   kapseln  freie, symmetrische Kapseln: Bass in der Mitte, nach aussen
//            leiser und durchsichtiger, oben/unten gespiegelt
//   welle    weiche, gefuellte Wellenform, symmetrisch
//   unten    ueber die ganze Bildschirmbreite, unten angedockt: Balken
//            wachsen vom Rand nach oben, Bass in der Mitte oder links
//
// Haengt am selben cava wie die Notch (Cava.demand). Geglaettet wird in den
// Daten, nicht per Animation: bei jedem cava-Frame (30/s) steigen die Pegel
// schnell und fallen langsam nach (wie ein Peak-Meter). Das kostet keinen
// Frame extra – eine Behavior-Animation liesse die Ebene mit 180 Hz zeichnen.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property string style: {
        const s = root.opts.style ?? "kapseln";
        return ({ "saeulen": "kapseln", "spiegel": "kapseln", "punkte": "kapseln" })[s] ?? s;
    }
    readonly property bool live: root.active && Media.playing
    readonly property bool idleShown: root.opts.idle === "ruhig"
    readonly property int bars: root.style === "insel" ? 5
                              : Math.max(8, Number(root.opts.bars ?? (root.style === "unten" ? 64 : 32)))

    // "unten": der Host dockt an der Unterkante an und reicht die Breite durch
    readonly property string dock: root.style === "unten" ? "unten" : ""
    property real areaWidth: 0
    // Bass in der Mitte (symmetrisch) oder links (klassisches Spektrum)
    readonly property bool fromLeft: root.opts.order === "links"

    implicitWidth: root.style === "insel" ? island.width : root.style === "unten" ? root.areaWidth : free.width
    implicitHeight: root.style === "insel" ? island.height : root.style === "unten" ? floor.height : free.height

    opacity: root.live || root.editing || (root.idleShown && Media.available) ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    DemandRequest {
        demand: Cava.demand
        active: root.live && root.visible
    }

    // ---- Pegel: symmetrisch, geglaettet ----
    // levels[i] fuer i = 0..bars-1, Bass in der Mitte
    property var levels: new Array(root.bars).fill(0)

    function band(f: real): real {
        // f = 0 (Bass) .. 1 (Hoehen); nur die unteren 75 % der cava-Baender,
        // darueber ist Musik fast immer leer
        const vals = Cava.values;
        const pos = f * (vals.length * 0.75 - 1);
        const i = Math.floor(pos), t = pos - i;
        const a = vals[i] ?? 0, b = vals[i + 1] ?? a;
        const v = a + (b - a) * t;
        // Hoehen anheben, leise Stellen sichtbar machen
        return Math.min(1, Math.pow(v * (1 + f * 0.35), 0.85) * 0.92);
    }

    function step(): void {
        const n = root.bars;
        const half = (n - 1) / 2;
        const prev = root.levels.length === n ? root.levels : new Array(n).fill(0);
        const next = new Array(n);
        for (let i = 0; i < n; i++) {
            const f = root.fromLeft && root.style === "unten"
                ? i / Math.max(1, n - 1)
                : Math.abs(i - half) / Math.max(1, half);
            const target = root.band(f);
            const p = prev[i];
            next[i] = target > p ? p + (target - p) * 0.65 : Math.max(target, p - 0.045);
        }
        root.levels = next;
    }

    Connections {
        target: Cava
        enabled: root.live && root.visible

        function onValuesChanged(): void {
            root.step();
        }
    }

    onLiveChanged: if (!root.live) root.levels = new Array(root.bars).fill(0)

    // ---- Frei: Kapseln / Welle ----
    Item {
        id: free

        visible: root.style !== "insel"
        width: Math.round(root.unit * 26)
        height: Math.round(root.unit * 7)

        readonly property real slot: free.width / root.bars
        readonly property real barW: Math.max(2, Math.round(free.slot * 0.55))

        Repeater {
            model: root.style === "kapseln" ? root.bars : 0

            Rectangle {
                id: cap

                required property int index

                readonly property real f: Math.abs(cap.index - (root.bars - 1) / 2) / Math.max(1, (root.bars - 1) / 2)
                readonly property real v: root.levels[cap.index] ?? 0

                x: Math.round(cap.index * free.slot + (free.slot - free.barW) / 2)
                width: free.barW
                // ganze Pixel je Seite: Subpixel-Aenderungen zeichnen nicht neu
                height: Math.max(free.barW, Math.round(cap.v * free.height / 2) * 2)
                y: Math.round((free.height - height) / 2)
                radius: width / 2
                // Mitte satt im Akzent, nach aussen zur Textfarbe und leiser
                color: Colors.mix(root.accent, root.color, cap.f * 0.55)
                opacity: 1 - cap.f * 0.55
            }
        }

        // Welle: Kurve durch die Pegel, oben und unten gespiegelt
        Shape {
            anchors.fill: parent
            visible: root.style === "welle"
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: Math.max(1.5, root.unit * 0.12)
                strokeColor: root.accent
                fillGradient: LinearGradient {
                    x1: 0; y1: 0
                    x2: 0; y2: free.height
                    GradientStop { position: 0; color: Colors.alpha(root.accent, 0.05) }
                    GradientStop { position: 0.5; color: Colors.alpha(root.accent, 0.4) }
                    GradientStop { position: 1; color: Colors.alpha(root.accent, 0.05) }
                }
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: {
                        if (root.style !== "welle")
                            return [];
                        const n = root.bars, w = free.width, h = free.height, mid = h / 2;
                        const lv = root.levels;
                        // Enden laufen auf null aus, dazwischen Cosinus-Uebergaenge
                        const amp = i => (lv[i] ?? 0) * mid * 0.92 * Math.sin(Math.PI * (i + 0.5) / n);
                        const top = [], bottom = [];
                        const steps = 4;
                        top.push(Qt.point(0, mid));
                        for (let i = 0; i < n - 1; i++) {
                            for (let s = 0; s < steps; s++) {
                                const t = s / steps, e = (1 - Math.cos(Math.PI * t)) / 2;
                                const a = amp(i) + (amp(i + 1) - amp(i)) * e;
                                const x = (i + 0.5 + t) * w / n;
                                top.push(Qt.point(x, mid - a));
                                bottom.push(Qt.point(x, mid + a));
                            }
                        }
                        top.push(Qt.point(w, mid));
                        return top.concat(bottom.reverse(), [Qt.point(0, mid)]);
                    }
                }
            }
        }
    }

    // ---- Unten angedockt, volle Breite ----
    // Balken wachsen vom Bildschirmrand nach oben, oben rund, unten buendig,
    // leicht durchsichtig, damit die Flaeche nicht aufs Bild drueckt.
    Item {
        id: floor

        visible: root.style === "unten"
        width: root.areaWidth
        height: Math.round(root.unit * 11)

        readonly property real slot: floor.width / root.bars
        readonly property real barW: Math.max(2, Math.round(floor.slot * 0.6))

        Repeater {
            model: root.style === "unten" ? root.bars : 0

            Rectangle {
                id: col

                required property int index

                readonly property real f: root.fromLeft ? col.index / Math.max(1, root.bars - 1)
                    : Math.abs(col.index - (root.bars - 1) / 2) / Math.max(1, (root.bars - 1) / 2)
                readonly property real v: root.levels[col.index] ?? 0

                x: Math.round(col.index * floor.slot + (floor.slot - floor.barW) / 2)
                width: floor.barW
                height: Math.max(Math.round(floor.barW / 2), Math.round(col.v * floor.height))
                y: floor.height - height
                topLeftRadius: width / 2
                topRightRadius: width / 2
                // Feste Farbe statt Verlauf je Balken: 64 Verlaeufe auf zwei
                // Monitoren kosteten gemessen ~2 % CPU mehr
                color: col.tint
                opacity: 0.85

                readonly property color tint: root.fromLeft ? root.accent : Colors.mix(root.accent, root.color, col.f * 0.4)
            }
        }
    }

    // ---- Insel: Live Activity ----
    RectangularShadow {
        visible: root.style === "insel"
        anchors.fill: island
        radius: island.radius
        offset.y: root.unit * 0.25
        blur: root.unit * 1.6
        color: Colors.alpha("#000000", 0.45)
    }

    Rectangle {
        id: island

        visible: root.style === "insel"
        width: Math.round(root.unit * 24)
        height: Math.round(root.unit * 4.4)
        radius: height / 2
        color: Appearance.notchColor
        border.width: 1
        border.color: Colors.alpha("#ffffff", 0.08)

        readonly property real pad: Math.round(root.unit * 0.6)
        readonly property real art: island.height - island.pad * 2

        // Cover, rund
        Item {
            id: coverBox

            x: island.pad
            y: island.pad
            width: island.art
            height: island.art

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Colors.alpha("#ffffff", 0.08)
            }

            Image {
                id: cover

                anchors.fill: parent
                source: Media.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 128
                sourceSize.height: 128
                visible: false
            }

            Item {
                id: coverMask

                anchors.fill: parent
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "black"
                }
            }

            MultiEffect {
                anchors.fill: parent
                visible: cover.status === Image.Ready
                source: cover
                maskEnabled: true
                maskSource: coverMask
            }

            Text {
                anchors.centerIn: parent
                visible: cover.status !== Image.Ready
                text: "music_note"
                color: Colors.alpha("#ffffff", 0.5)
                font.family: "Material Symbols Outlined"
                font.pixelSize: island.art * 0.45
            }
        }

        Column {
            anchors {
                left: coverBox.right
                leftMargin: root.unit * 0.8
                right: islandBars.left
                rightMargin: root.unit * 0.8
                verticalCenter: parent.verticalCenter
            }
            spacing: root.unit * 0.1

            Text {
                width: parent.width
                text: Media.title || (root.editing ? I18n.tr("Titel") : "")
                color: "#f5f5f7"
                font.family: Config.font
                font.pixelSize: root.unit * 0.95
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: Media.artist || (root.editing ? I18n.tr("Interpret") : "")
                color: Colors.alpha("#f5f5f7", 0.55)
                font.family: Config.font
                font.pixelSize: root.unit * 0.8
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        // Pegel: dieselben geglaetteten Kapseln wie frei, nur fuenf; Farbe
        // vom Cover (aufgehellt), sonst der Akzent
        Item {
            id: islandBars

            readonly property real barW: Math.max(3, Math.round(root.unit * 0.28))
            readonly property real gap: Math.max(2, Math.round(root.unit * 0.22))
            readonly property color tint: Media.artColor.a > 0 ? Colors.mix(Media.artColor, "#ffffff", 0.45) : root.accent

            anchors {
                right: parent.right
                rightMargin: island.pad + root.unit * 0.6
                verticalCenter: parent.verticalCenter
            }
            width: root.bars * barW + (root.bars - 1) * gap
            height: Math.round(island.height * 0.46)

            Repeater {
                model: root.bars

                Rectangle {
                    id: pip

                    required property int index

                    readonly property real v: root.live ? (root.levels[pip.index] ?? 0) : 0.18

                    x: pip.index * (islandBars.barW + islandBars.gap)
                    width: islandBars.barW
                    height: Math.max(islandBars.barW, Math.round(pip.v * islandBars.height / 2) * 2)
                    y: Math.round((islandBars.height - height) / 2)
                    radius: width / 2
                    color: islandBars.tint
                    opacity: root.live ? 1 : 0.45
                }
            }
        }
    }
}
