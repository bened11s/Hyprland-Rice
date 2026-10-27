pragma ComponentBehavior: Bound
import QtQuick

import qs.modules.services.config

// Zustand des Kachel-Editors (Vorbild: Android 16, "Kacheln bearbeiten").
// Je SettingsTiles eine Instanz; bearbeitet wird nur in der Instanz im
// Einstellungs-Menue (`editable`, editor "quick" -> QuickTilesEditor) – dort
// ist der Modus immer an. Steuerung und Settings-Pille bleiben unberuehrt.
//
// Zwei Ansichten, umgeschaltet ueber die Pille unten (EditFooter):
//   "tiles"   Kacheln an Ort und Stelle: antippen waehlt, Griff rechts zieht
//             die Breite, Ziehen sortiert um (auch in andere oder neue
//             Reihen), Ablage "Verfuegbar" blendet aus bzw. wieder ein
//   "layout"  Reihen als Bloecke, senkrecht verschiebbar (RowBlocks)
// Jede Aenderung geht sofort an QuickLayout, das sie speichert.
//
// Zeigerposition und Ziel-Markierung rechnen in den Koordinaten von `frame`,
// dem Rahmen um das Raster – dort liegen auch Geist und Markierung
// (DragOverlay). SettingsTiles setzt frame/grid/rows/tray beim Aufbau.
QtObject {
    id: edit

    property bool editable: false
    readonly property bool editing: edit.editable
    property string mode: "tiles"       // "tiles" | "layout"
    readonly property bool tilesMode: edit.editing && edit.mode === "tiles"
    readonly property bool layoutMode: edit.editing && edit.mode === "layout"

    property string selectedId: ""

    // ---- Verschieben einer Kachel ----
    property string dragId: ""
    readonly property bool dragging: edit.dragId !== ""
    property point dragPos: Qt.point(0, 0)
    // { rowIndex, index, newRow } | { rowIndex, column, span } (auf freie
    // Zellen, siehe freeTarget) | { hide: true } | null
    property var target: null
    readonly property bool hideTarget: edit.target !== null && edit.target.hide === true
    // Einfuege-Markierung in frame-Koordinaten; Breite 0 = keine
    property rect marker: Qt.rect(0, 0, 0, 0)

    // ---- Breite ziehen ----
    property string resizeId: ""
    property int resizeSpan: 0

    // Von SettingsTiles gesetzt
    property Item frame: null
    property Item grid: null        // ColumnLayout mit den Reihen
    property Repeater rows: null    // je Reihe ein RowLayout mit `slots`
    property Item tray: null        // Ablage "Verfuegbar" – Ziel: ausblenden
    property real rowGap: 10
    property real slotGap: 10

    // Antippen waehlt, erneutes Antippen hebt die Wahl auf
    function select(id: string): void {
        edit.selectedId = edit.selectedId === id ? "" : id;
    }

    function removeSelected(): void {
        if (edit.selectedId === "")
            return;
        QuickLayout.hide(edit.selectedId);
        edit.selectedId = "";
    }

    // Breite, die der Platz gerade zeigt: beim Ziehen am Griff die Vorschau
    function previewSpan(id: string, span: int): int {
        return edit.resizeId === id ? edit.resizeSpan : span;
    }

    // ---- Ziehen (Kachel aus dem Raster oder Chip aus der Ablage) ----
    function beginDrag(id: string): void {
        edit.dragId = id;
        edit.selectedId = id;
        edit.target = null;
        edit.marker = Qt.rect(0, 0, 0, 0);
    }

    function updateDrag(scenePos: point): void {
        if (!edit.frame)
            return;
        edit.dragPos = edit.frame.mapFromItem(null, scenePos.x, scenePos.y);
        edit.target = edit.hitTest(edit.dragPos);
        edit.marker = edit.markerFor(edit.target);
    }

    function endDrag(): void {
        const t = edit.target;
        const id = edit.dragId;
        edit.dragId = "";
        edit.target = null;
        edit.marker = Qt.rect(0, 0, 0, 0);
        if (!t || id === "")
            return;
        if (t.hide) {
            QuickLayout.hide(id);
            if (edit.selectedId === id)
                edit.selectedId = "";
        } else if (t.column !== undefined) {
            QuickLayout.placeAt(id, t.rowIndex, t.column);
        } else {
            QuickLayout.place(id, t.rowIndex, t.index ?? 0, t.newRow ?? false);
        }
    }

    function inside(item: Item, p: point): bool {
        if (!item || !item.visible)
            return false;
        const q = edit.frame.mapToItem(item, p.x, p.y);
        return q.x >= 0 && q.x <= item.width && q.y >= 0 && q.y <= item.height;
    }

    // Wohin faellt der Zeiger? Reihenrand oben (8 px) und die Luecke
    // darueber zaehlen als "neue Reihe davor", unter der letzten Reihe als
    // "neue Reihe hinten", die Ablage als "ausblenden".
    function hitTest(p: point): var {
        if (edit.inside(edit.tray, p))
            return ({ hide: true });
        if (!edit.grid || !edit.rows)
            return null;
        const g = edit.frame.mapToItem(edit.grid, p.x, p.y);
        if (g.x < -edit.slotGap * 2 || g.x > edit.grid.width + edit.slotGap * 2)
            return null;

        const n = edit.rows.count;
        for (let i = 0; i < n; i++) {
            const row = edit.rows.itemAt(i);
            if (!row)
                continue;
            const edge = Math.min(8, row.height / 4);
            if (g.y < row.y + edge) {
                // Oberhalb der ersten Reihe grosszuegig (Rahmen-Polster)
                const reach = i === 0 ? edit.rowGap * 3 : edit.rowGap;
                return g.y >= row.y - reach ? ({ rowIndex: i, index: 0, newRow: true }) : null;
            }
            if (g.y <= row.y + row.height) {
                const free = edit.freeTarget(row, i, g.x - row.x);
                if (free)
                    return free;
                const slots = row.slots;
                let index = slots.count;
                for (let j = 0; j < slots.count; j++) {
                    const s = slots.itemAt(j);
                    if (!s)
                        continue;
                    if (g.x < s.x + s.width / 2) {
                        index = j;
                        break;
                    }
                }
                return ({ rowIndex: i, index, newRow: false });
            }
        }
        if (g.y <= edit.grid.height + edit.rowGap * 3)
            return ({ rowIndex: n, index: 0, newRow: true });
        return null;
    }

    // Zeiger ueber einer freien Zelle (Luecke, Rest der Reihe oder der eigene
    // Platz der gezogenen Kachel)? Dann landet die Kachel genau dort – sie
    // darf dafuer nach links rutschen, solange sie die Zelle unter dem Zeiger
    // noch abdeckt. null = Zelle belegt oder nichts passt (dann zaehlt die
    // Einfuege-Position zwischen den Kacheln).
    function freeTarget(row: Item, rowIndex: int, x: real): var {
        const columns = QuickLayout.columns;
        // Spalte c beginnt bei c * step (Kachelbreiten sind Spalten + Luecken)
        const step = (row.width + edit.slotGap) / columns;
        const col = Math.floor(x / step);
        if (col < 0 || col >= columns)
            return null;
        const entries = row.entries;
        const starts = row.starts;
        const taken = c => entries.some((t, k) => t.id !== QuickLayout.gap && t.id !== edit.dragId
                                                  && starts[k] <= c && c < starts[k] + t.span);
        if (taken(col))
            return null;
        for (let c = col; c >= 0 && !taken(c); c--) {
            const span = QuickLayout.fitAt(edit.dragId, rowIndex, c);
            if (span > 0 && c + span > col)
                return ({ rowIndex, column: c, span });
        }
        return null;
    }

    // Geometrie der Markierung zu einem Ziel (frame-Koordinaten): waagerechte
    // Linie fuer eine neue Reihe, senkrechte zwischen den Kacheln
    function markerFor(t: var): rect {
        const none = Qt.rect(0, 0, 0, 0);
        // Ziele auf freie Zellen zeigen die Blasen selbst (edit/CellBubble)
        if (!t || t.hide || t.column !== undefined || !edit.grid || !edit.rows)
            return none;
        const n = edit.rows.count;
        if (t.newRow) {
            let y;
            if (t.rowIndex >= n) {
                y = edit.grid.height + edit.rowGap / 2;
            } else {
                const row = edit.rows.itemAt(t.rowIndex);
                if (!row)
                    return none;
                y = row.y - edit.rowGap / 2;
            }
            const o = edit.grid.mapToItem(edit.frame, 0, y);
            return Qt.rect(o.x + 6, o.y - 1, edit.grid.width - 12, 2);
        }
        const row = edit.rows.itemAt(t.rowIndex);
        if (!row)
            return none;
        const slots = row.slots;
        let x;
        if (slots.count === 0) {
            x = 0;
        } else if (t.index < slots.count) {
            const s = slots.itemAt(t.index);
            x = s ? s.x - edit.slotGap / 2 : 0;
        } else {
            const last = slots.itemAt(slots.count - 1);
            x = last ? Math.min(last.x + last.width + edit.slotGap / 2, row.width - 1) : 0;
        }
        const o = edit.grid.mapToItem(edit.frame, row.x + x, row.y);
        return Qt.rect(o.x - 1, o.y + 4, 2, row.height - 8);
    }
}
