pragma ComponentBehavior: Bound
import QtQuick

import qs
import "lookmodel.js" as LookModel

// Terminal-Block fuer die fastfetch-Vorschau: dunkle Flaeche, links die
// Logo-Karte, rechts die Ausgabe von `looks.py preview` in einem Zellraster
// (Monospace 12 px). Natuerliche Masse stehen in implicitWidth/-Height, wer
// weniger Platz hat, skaliert (scale, transformOrigin TopLeft).
//
// Genutzt vom Looks-Editor (LooksPage.qml, mit Budget-Rahmen und rotem
// Ueberlauf) und von der Sektion in der Wallpaper-Auswahl (Section.qml).
// Plugin-Dateien sehen sich nicht als Typen, deshalb per Loader laden:
// `source: plugin.url("TerminalPreview.qml")`, Werte danach binden – darum
// hier keine required-Eigenschaften.
Item {
    id: block

    // Ergebnis von looks.py preview: { lines: [[{t, fg, bg, b, i, d, u}]],
    // width, height, budget: {cols, rows}, overflow: [], tooTall }
    property var preview: null
    // Budget, solange die Vorschau keins mitbringt
    property int cols: 50
    property int rows: 19
    // Pfad der Logo-Karte, "" = keine (dann faellt die Spalte weg)
    property string card: ""
    // Karte als 3:4-Ausschnitt fuellen (Wallpaper als Karte) statt einpassen
    property bool cardCrop: false
    // Budget-Rahmen zeichnen und Zeilen ausserhalb rot hinterlegen (Editor)
    property bool budgetFrame: true
    property real pad: 14
    property string monoFont: "monospace"

    readonly property real charW: metrics.advanceWidth("0")
    readonly property real lineH: Math.ceil(metrics.height)
    readonly property int budgetCols: block.preview?.budget?.cols ?? block.cols
    readonly property int budgetRows: block.preview?.budget?.rows ?? block.rows
    readonly property int lineCount: block.preview?.lines?.length ?? 0
    readonly property int shownRows: Math.max(block.budgetRows, block.lineCount)
    readonly property bool withCard: block.card !== ""
    readonly property real cardH: block.budgetRows * block.lineH
    readonly property real cardW: block.withCard ? Math.round(block.cardH * 3 / 4) + 14 : 0
    readonly property real textW: Math.max(block.budgetCols, block.preview?.width ?? 0) * block.charW
    readonly property real naturalW: block.pad * 2 + block.cardW + block.textW + 8
    readonly property real naturalH: block.pad * 2 + block.shownRows * block.lineH
    readonly property bool overflowing: block.preview?.tooTall || (block.preview?.overflow?.length ?? 0) > 0

    implicitWidth: block.naturalW
    implicitHeight: block.naturalH

    // Vorschau-Zeile in Laeufe zerlegen, die wie im Terminal in Zellen
    // stehen: Zeichen mit fremder Breite (Ersatzschrift) bekommen einzeln
    // genau ihre Zellen, statt die Zeile nach rechts zu schieben
    property var advanceCache: ({})

    function advance(ch: string): real {
        let a = block.advanceCache[ch];
        if (a === undefined) {
            a = metrics.advanceWidth(ch);
            block.advanceCache[ch] = a;
        }
        return a;
    }

    function cellRuns(segs: var): var {
        const cw = block.charW;
        const out = [];
        let col = 0;
        for (const s of segs) {
            let buf = "";
            let start = col;
            const flush = () => {
                if (buf !== "")
                    out.push({ x: start, n: col - start, t: buf, s: s, odd: false });
                buf = "";
                start = col;
            };
            for (const ch of String(s.t)) {
                const w = LookModel.cellWidth(ch);
                if (w === 0) {
                    buf += ch;
                    continue;
                }
                if (Math.abs(block.advance(ch) - w * cw) > 0.5) {
                    flush();
                    out.push({ x: col, n: w, t: ch, s: s, odd: true });
                    col += w;
                    start = col;
                } else {
                    if (buf === "")
                        start = col;
                    buf += ch;
                    col += w;
                }
            }
            flush();
        }
        return out;
    }

    FontMetrics {
        id: metrics

        font.family: block.monoFont
        font.pixelSize: 12
    }

    onMonoFontChanged: block.advanceCache = {}

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "#0f0f12"
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.3)
    }

    // Logo-Karte links, wie im Terminal
    Rectangle {
        id: cardFrame

        x: block.pad
        y: block.pad
        width: block.withCard ? block.cardW - 14 : 0
        height: block.cardH
        visible: block.withCard
        radius: 6
        color: Colors.alpha("#ffffff", 0.05)
        clip: true

        Image {
            anchors.fill: parent
            source: block.card !== "" ? (block.card.startsWith("file://") ? block.card : "file://" + block.card) : ""
            sourceSize: Qt.size(300, 400)
            fillMode: block.cardCrop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            asynchronous: true
        }
    }

    // Budget-Rahmen
    Rectangle {
        x: block.pad + block.cardW
        y: block.pad
        width: block.budgetCols * block.charW + 2
        height: block.budgetRows * block.lineH
        visible: block.budgetFrame
        color: "transparent"
        border.width: 1
        border.color: Colors.alpha(block.overflowing ? Colors.error : "#ffffff", 0.18)
        radius: 2
    }

    Column {
        x: block.pad + block.cardW + 1
        y: block.pad

        Repeater {
            model: block.preview?.lines?.length ?? 0

            Item {
                id: line

                required property int index

                readonly property var modelData: block.preview?.lines?.[line.index] ?? []
                readonly property bool over: block.budgetFrame
                    && ((block.preview?.overflow ?? []).includes(line.index) || line.index >= block.budgetRows)

                width: block.textW
                height: block.lineH

                Rectangle {
                    anchors.fill: parent
                    visible: line.over
                    color: Colors.alpha(Colors.error, 0.16)
                }

                Repeater {
                    model: block.cellRuns(line.modelData)

                    Item {
                        id: run

                        required property var modelData

                        x: run.modelData.x * block.charW
                        width: run.modelData.n * block.charW
                        height: block.lineH

                        Rectangle {
                            anchors.fill: parent
                            visible: !!run.modelData.s.bg
                            color: run.modelData.s.bg || "transparent"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: run.modelData.odd ? (parent.width - width) / 2 : 0
                            // Breitere Ersatz-Glyphe in ihre Zelle stauchen
                            scale: run.modelData.odd && implicitWidth > parent.width ? parent.width / implicitWidth : 1
                            font.family: block.monoFont
                            font.pixelSize: 12
                            font.bold: !!run.modelData.s.b
                            font.italic: !!run.modelData.s.i
                            font.underline: !!run.modelData.s.u
                            opacity: run.modelData.s.d ? 0.6 : 1
                            color: run.modelData.s.fg || "#d8d8dc"
                            textFormat: Text.PlainText
                            text: run.modelData.t
                        }
                    }
                }
            }
        }
    }
}
