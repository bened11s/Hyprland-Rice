pragma ComponentBehavior: Bound
import QtQuick

import qs
import "bonsai.js" as Bonsai

// ASCII-Bonsai als Desktop-Widget (Vertrag: modules/desktop/WidgetHost.qml).
//
// bonsai.js rechnet den ganzen Baum auf einmal als Liste von Zeichen-
// Operationen. Mit "Wachsen zeigen" werden sie mit der Desktop-Bildrate
// nacheinander aufgedeckt (~6 s), danach steht der Baum und kostet nichts
// mehr – kein Timer, keine Animation. Neu waechst er beim naechsten Tag bzw.
// zur naechsten Stunde (opts.regrow) oder wenn sich eine Option aendert.
// Gleicher Zeitraum = gleicher Seed = derselbe Baum, auch nach Neustarts.
//
// Gezeichnet wird zeilenweise: je Zeile ein Text mit farbigen <font>-Spans,
// beim Wachsen werden nur die Zeilen neu gesetzt, die sich geaendert haben.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property int fps: 30

    readonly property var lifes: ({ "klein": [24, 52, 20], "mittel": [32, 64, 26], "groß": [44, 80, 34] })
    readonly property var dims: root.lifes[root.opts.life] ?? root.lifes["mittel"]

    readonly property string fontFamily: {
        const have = Qt.fontFamilies();
        for (const f of ["JetBrainsMono Nerd Font", "JetBrains Mono NL", "Noto Sans Mono"])
            if (have.includes(f))
                return f;
        return "monospace";
    }

    FontMetrics {
        id: metrics

        font.family: root.fontFamily
        font.pixelSize: Math.round(root.unit * 0.85)
    }

    // pixelSize lesen = Abhaengigkeit (der Aufruf allein misst nicht neu)
    readonly property real charW: metrics.font.pixelSize > 0 ? metrics.advanceWidth("M") : 0
    readonly property real lineH: Math.ceil(metrics.height * 0.92)

    implicitWidth: Math.ceil(root.dims[1] * root.charW)
    implicitHeight: root.dims[2] * root.lineH

    // ---- Farben je Klasse ----
    readonly property var palette: ({
        wood: Colors.mix("#a8743f", root.color, 0.15),
        woodDark: Colors.mix("#6b4526", root.color, 0.1),
        leaf: root.accent,
        leafDark: Qt.darker(root.accent, 1.55),
        pot: root.color,
        potDark: Colors.alpha(root.color, 0.65)
    })

    function hex(c: color): string {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    // ---- Zustand ----
    property var plan: null      // Ergebnis von Bonsai.grow
    property var cells: []       // [zeile][spalte] = { ch, k } | null
    property int shown: 0        // so viele ops sind aufgedeckt
    property var dirty: ({})

    ListModel {
        id: lines
    }

    // Zeitraum, aus dem der Seed kommt
    function period(): string {
        const now = new Date();
        switch (root.opts.regrow) {
        case "nie": return "fest";
        case "stündlich": return now.toISOString().slice(0, 13);
        }
        return now.toISOString().slice(0, 10);
    }

    function seedFor(text: string): int {
        let h = 2166136261;
        for (let i = 0; i < text.length; i++)
            h = Math.imul(h ^ text.charCodeAt(i), 16777619);
        return h >>> 0;
    }

    property string periodKey: ""

    function regenerate(): void {
        const key = root.period() + "|" + JSON.stringify(root.opts) + "|" + root.dims;
        root.periodKey = root.period();
        root.plan = Bonsai.grow({
            cols: root.dims[1],
            rows: root.dims[2],
            life: root.dims[0],
            leaves: root.opts.leaves ?? "&",
            pot: root.opts.pot ?? "schale",
            seed: root.seedFor(key)
        });
        const grid = [];
        for (let y = 0; y < root.dims[2]; y++)
            grid.push(new Array(root.dims[1]).fill(null));
        root.cells = grid;
        lines.clear();
        for (let y = 0; y < root.dims[2]; y++)
            lines.append({ html: "" });
        root.shown = 0;
        root.dirty = {};
        // Ohne Wachstum (oder verdeckt): alles auf einmal
        if (root.opts.grow === false || !root.active) {
            root.reveal(root.plan.ops.length);
        } else {
            // Topf zuerst komplett, dann der Baum
            let base = 0;
            while (base < root.plan.ops.length && root.plan.ops[base].base)
                base++;
            root.reveal(base);
        }
        nextPeriod.restart();
    }

    function reveal(count: int): void {
        const ops = root.plan.ops;
        const end = Math.min(ops.length, root.shown + count);
        for (let i = root.shown; i < end; i++) {
            const op = ops[i];
            const row = root.cells[op.y];
            for (let j = 0; j < op.s.length; j++)
                row[op.x + j] = { ch: op.s[j], k: op.k };
            root.dirty[op.y] = true;
        }
        root.shown = end;
        for (const y in root.dirty)
            lines.setProperty(Number(y), "html", root.rowHtml(Number(y)));
        root.dirty = {};
    }

    function glyph(ch: string): string {
        return ch === " " ? "&nbsp;" : ch === "<" ? "&lt;" : ch === ">" ? "&gt;" : ch === "&" ? "&amp;" : ch;
    }

    function rowHtml(y: int): string {
        const row = root.cells[y];
        let out = "", run = "", runK = "";
        const flush = () => {
            if (run === "")
                return;
            out += runK === "" ? run : `<font color="${root.hex(root.palette[runK])}">${run}</font>`;
            run = "";
        };
        for (const cell of row) {
            const k = cell ? cell.k : "";
            if (k !== runK) {
                flush();
                runK = k;
            }
            run += cell ? root.glyph(cell.ch) : "&nbsp;";
        }
        flush();
        return out;
    }

    // Farben/Theme geaendert: Zeilen neu faerben, Baum bleibt
    onPaletteChanged: {
        for (let y = 0; y < lines.count; y++)
            lines.setProperty(y, "html", root.rowHtml(y));
    }

    // Der Host reicht bei jeder Aenderung des Widgets (auch Verschieben) ein
    // neues opts-Objekt durch – nur echte Options-Aenderungen zaehlen
    property string optsKey: ""

    onOptsChanged: {
        const key = JSON.stringify(root.opts);
        if (key === root.optsKey)
            return;
        root.optsKey = key;
        Qt.callLater(root.regenerate);
    }
    Component.onCompleted: if (root.plan === null) root.regenerate()

    // Wachsen: nur solange noch etwas fehlt und der Desktop zu sehen ist
    Timer {
        running: root.plan !== null && root.shown < root.plan.ops.length && root.active
        repeat: true
        interval: Math.round(1000 / Math.max(5, root.fps))
        onTriggered: root.reveal(Math.max(1, Math.ceil(root.plan.ops.length / (6 * Math.max(5, root.fps)))))
    }

    // Neuer Tag / neue Stunde: neu wachsen (verdeckt wartet es aufs Zeigen)
    Timer {
        id: nextPeriod

        interval: 60000
        repeat: true
        running: root.opts.regrow !== "nie"
        onTriggered: {
            if (root.active && root.period() !== root.periodKey)
                root.regenerate();
        }
    }

    onActiveChanged: {
        if (root.active && root.periodKey !== "" && root.period() !== root.periodKey)
            root.regenerate();
    }

    Column {
        anchors.fill: parent

        Repeater {
            model: lines

            Text {
                required property string html

                height: root.lineH
                text: html
                textFormat: Text.StyledText
                font: metrics.font
                renderType: Text.NativeRendering
                style: Text.Raised
                styleColor: Colors.alpha("#000000", 0.35)
            }
        }
    }
}
