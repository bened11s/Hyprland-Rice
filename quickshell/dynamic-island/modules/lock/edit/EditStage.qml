pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.desktop
import qs.modules.lock
import qs.modules.services.desktop
import qs.modules.services.media

// Die Buehne des Anordnungs-Editors: der echte Sperrbildschirm als Vorschau
// (ohne Sperre, ohne PAM – `preview`), darueber ein Griff je Element
// (EditHandle.qml: Uhr, Karte, jedes Widget), Hilfslinien beim Einrasten,
// das Optionsfeld am gewaehlten Element, die Widget-Auswahl und die Leiste
// rechts unten (LockEditBar.qml).
//
// Tasten: Pfeile verschieben das gewaehlte Element (Umschalt = grosse
// Schritte), + / - aendern die Groesse, Entf loescht ein Widget bzw. blendet
// Uhr/Karte aus und ein, Strg+Z / Strg+Umschalt+Z machen rueckgaengig / wieder
// her, Esc schliesst erst die Auswahl, hebt dann die Markierung auf und
// bricht zuletzt ab, Enter ist Fertig. Rechtsklick auf freie Flaeche: Widget
// an dieser Stelle hinzufuegen.
Item {
    id: stage

    focus: true

    // Alle Griffe (Uhr, Karte, Widgets) – Einrasten und Treffer
    readonly property var handles: {
        const out = [clockHandle, mediaHandle];
        stage.handleRevision;
        for (let i = 0; i < widgetHandles.count; i++) {
            const h = widgetHandles.itemAt(i);
            if (h)
                out.push(h);
        }
        return out;
    }
    property int handleRevision: 0
    readonly property Item selectedHandle: stage.handles.find(h => h.name === LockLayout.selected && LockLayout.selected !== "") ?? null
    // Maus ueber Leiste, Optionsfeld oder Auswahl: Griffe darunter nehmen nichts an
    readonly property bool overUi: bar.hovered || (options.item?.hovered ?? false) || (picker.item?.hovered ?? false)

    // Sanft erscheinen – die Vorschau selbst springt (keine Szenen-Animation)
    opacity: 0

    NumberAnimation on opacity {
        to: 1
        duration: Appearance.morphDuration
        easing.type: Easing.OutCubic
    }

    function inside(item: Item, x: real, y: real): bool {
        if (!item || !item.visible)
            return false;
        const p = item.mapFromItem(stage, x, y);
        return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height;
    }

    // Liegt ein Punkt (Buehnenkoordinaten) auf Leiste, Optionsfeld oder Auswahl?
    function onUi(x: real, y: real): bool {
        return stage.inside(bar, x, y) || stage.inside(options.item, x, y) || stage.inside(picker.item, x, y);
    }

    function removeSelected(): void {
        const name = LockLayout.selected;
        if (name === "")
            return;
        if (LockLayout.isWidget(name))
            LockLayout.remove(name);
        else
            LockLayout.setHidden(name, !LockLayout.hidden(name));
    }

    Keys.onPressed: event => {
        const sel = stage.selectedHandle;
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const step = shift ? 0.02 : 0.004;
        if (ctrl && event.key === Qt.Key_Z) {
            if (shift)
                LockLayout.redo();
            else
                LockLayout.undo();
        } else if (ctrl && event.key === Qt.Key_Y) {
            LockLayout.redo();
        } else if (event.key === Qt.Key_Escape) {
            if (LockLayout.adding)
                LockLayout.adding = false;
            else if (LockLayout.selected !== "")
                LockLayout.selected = "";
            else
                LockLayout.cancel();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            LockLayout.done();
        } else if (sel && event.key === Qt.Key_Delete) {
            stage.removeSelected();
        } else if (sel && event.key === Qt.Key_Left) {
            sel.nudge(-step, 0);
        } else if (sel && event.key === Qt.Key_Right) {
            sel.nudge(step, 0);
        } else if (sel && event.key === Qt.Key_Up) {
            sel.nudge(0, -step);
        } else if (sel && event.key === Qt.Key_Down) {
            sel.nudge(0, step);
        } else if (sel && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) {
            sel.grow(1.1);
        } else if (sel && event.key === Qt.Key_Minus) {
            sel.grow(1 / 1.1);
        } else {
            return;
        }
        event.accepted = true;
    }

    LockContext {
        id: previewContext
    }

    LockScreen {
        id: preview

        anchors.fill: parent
        context: previewContext
        preview: true
        focus: false

        onWidgetRevisionChanged: stage.handleRevision++
    }

    // Drittel-Linien andeuten – kein Schleier: die Vorschau soll genau so
    // aussehen wie nachher die Sperre. Die MouseArea nimmt jeden Druck an:
    // nichts davon erreicht die Vorschau (Medien-Knoepfe, Fokus-Griff des
    // Sperrbildschirms). Die Griffe liegen darueber und holen sich das
    // Ziehen (DragHandler) von ihr.
    Item {
        id: backdrop

        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            // Nur ein Druck auf freie Flaeche hebt die Auswahl auf – nicht
            // auf einen Griff samt Rahmen (der ragt ueber das Element
            // hinaus) und nicht auf Leiste, Optionsfeld oder Auswahl.
            // Rechtsklick dort: Widget an dieser Stelle hinzufuegen
            onPressed: mouse => {
                const x = mouse.x, y = mouse.y;
                if (stage.onUi(x, y) || stage.handles.some(h => h.owns(x, y)))
                    return;
                LockLayout.selected = "";
                if (mouse.button === Qt.RightButton)
                    LockLayout.openPicker({ x: x / stage.width, y: y / stage.height });
                else
                    LockLayout.adding = false;
            }
        }

        Repeater {
            model: [1 / 3, 1 / 2, 2 / 3]

            Rectangle {
                required property real modelData

                x: Math.round(parent.width * modelData)
                width: 1
                height: parent.height
                color: Colors.alpha("#ffffff", 0.07)
            }
        }

        Repeater {
            model: [1 / 3, 1 / 2, 2 / 3]

            Rectangle {
                required property real modelData

                y: Math.round(parent.height * modelData)
                height: 1
                width: parent.width
                color: Colors.alpha("#ffffff", 0.07)
            }
        }
    }

    // Hilfslinien beim Einrasten (setzt EditHandle waehrend des Ziehens)
    Rectangle {
        id: guideX

        property real at: -1

        visible: at >= 0
        x: Math.round(at)
        width: 1
        height: parent.height
        color: Colors.primary
    }

    Rectangle {
        id: guideY

        property real at: -1

        visible: at >= 0
        y: Math.round(at)
        height: 1
        width: parent.width
        color: Colors.primary
    }

    EditHandle {
        id: clockHandle

        name: "clock"
        title: I18n.tr("Uhr")
        target: preview.clockItem
        others: stage.handles
        blocked: stage.overUi
        guideX: guideX
        guideY: guideY
    }

    EditHandle {
        id: mediaHandle

        name: "media"
        title: I18n.tr("Medien")
        target: preview.mediaItem
        others: stage.handles
        // Ohne Musik steht die Karte leer da – zurueckgenommen, als Platzhalter
        placeholder: !Media.available
        blocked: stage.overUi
        guideX: guideX
        guideY: guideY
    }

    // Ein Griff je Widget – gleiche Liste wie die Vorschau (ListModel), damit
    // Griffe beim Ziehen nicht neu entstehen
    ListModel {
        id: widgetModel
    }

    function syncWidgets(): void {
        const ids = LockLayout.widgets.map(w => w.id);
        for (let i = widgetModel.count - 1; i >= 0; i--)
            if (!ids.includes(widgetModel.get(i).wid))
                widgetModel.remove(i);
        for (const id of ids) {
            let found = false;
            for (let i = 0; i < widgetModel.count; i++)
                if (widgetModel.get(i).wid === id)
                    found = true;
            if (!found)
                widgetModel.append({ wid: id });
        }
    }

    Connections {
        target: LockLayout
        function onWidgetsChanged(): void {
            stage.syncWidgets();
        }
    }
    Component.onCompleted: stage.syncWidgets()

    Repeater {
        id: widgetHandles

        model: widgetModel
        onItemAdded: stage.handleRevision++
        onItemRemoved: stage.handleRevision++

        EditHandle {
            id: wh

            required property string wid
            readonly property var info: {
                const w = LockLayout.widget(wh.wid);
                return w ? DesktopWidgets.info(w.type) : null;
            }

            name: wh.wid
            title: I18n.tr(wh.info?.title ?? "Widget")
            target: {
                stage.handleRevision;
                return preview.widgetItem(wh.wid);
            }
            others: stage.handles
            blocked: stage.overUi
            guideX: guideX
            guideY: guideY
        }
    }

    // Optionsfeld am gewaehlten Element: unter dem Rahmen, sonst darueber,
    // am Bildschirmrand eingefangen
    Loader {
        id: options

        readonly property Item handle: stage.selectedHandle
        readonly property real frame: 8

        active: options.handle !== null && !options.handle.busy && !LockLayout.adding
        z: 15
        x: options.handle ? Math.round(Math.max(16, Math.min(stage.width - width - 16, options.handle.x - options.frame))) : 0
        y: {
            const h = options.handle;
            if (!h)
                return 0;
            const below = h.y + h.height + options.frame + height + 16 <= stage.height;
            return Math.round(below ? h.y + h.height + options.frame - 2 : h.y - options.frame - height + 2);
        }

        sourceComponent: LockLayout.isWidget(LockLayout.selected) ? widgetOptions : elementOptions
    }

    Component {
        id: widgetOptions

        WidgetOptions {
            widget: LockLayout.widget(LockLayout.selected)
            store: LockLayout
            monitors: false
            radius: 14
        }
    }

    Component {
        id: elementOptions

        LockElementOptions {
            name: LockLayout.selected
            title: LockLayout.selected === "clock" ? I18n.tr("Uhr") : I18n.tr("Medien")
            icon: LockLayout.selected === "clock" ? "schedule" : "music_note"
        }
    }

    // Widget-Auswahl: ueber der Leiste bzw. am Rechtsklick
    Loader {
        id: picker

        readonly property var at: LockLayout.addAt
        readonly property real w: item?.width ?? 0
        readonly property real h: item?.height ?? 0

        active: LockLayout.adding
        z: 25
        x: {
            if (!at)
                return Math.round(stage.width - w - 36);
            return Math.round(Math.max(16, Math.min(stage.width - w - 16, at.x * stage.width + 18)));
        }
        y: {
            if (!at)
                return Math.round(bar.y - h - 12);
            const py = at.y * stage.height;
            const below = py + 18 + h + 16 <= stage.height;
            return Math.round(Math.max(16, below ? py + 18 : py - h - 18));
        }

        sourceComponent: WidgetPicker {
            store: LockLayout
            exclude: LockLayout.excluded
        }

        // Danach gehoeren die Tasten wieder der Buehne
        onActiveChanged: if (!active) stage.forceActiveFocus()
    }

    // Leiste rechts unten: unten mittig steht die Karte
    LockEditBar {
        id: bar

        z: 20
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 36
    }
}
