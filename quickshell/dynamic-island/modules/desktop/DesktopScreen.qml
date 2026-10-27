pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs
import qs.modules.services.config
import qs.modules.services.desktop
import qs.modules.services.hypr
import qs.modules.services.system
import qs.modules.window

// Die Widget-Ebene eines Monitors.
//
// Normal: Layer "bottom" (ueber dem Wallpaper, unter allen Fenstern), ohne
// Eingabe (leere Maske – Klicks gehen auf den Desktop durch), ohne Tastatur.
// Bearbeiten: auf allen Monitoren rutscht die Ebene nach "top" (ueber die
// Fenster, deckend mit dem Wallpaper) und nimmt Maus und Tastatur. Exclusive
// auf ALLEN: Hyprland laesst den Zeiger nur auf Flaechen mit exklusivem
// Fokus. Leiste (EditBar.qml), Widget-Auswahl und Optionsfeld nur auf dem
// Monitor, auf dem zuletzt gedrueckt wurde (Scenes.editScreen).
//
// Pausieren: sieht man den Desktop nicht (Fenster auf dem Workspace bzw. nur
// bei Vollbild, Einstellung desktop.pause; Game-Mode immer), bekommen alle
// Widgets `active: false` – Cava-/Songtext-Bedarf faellt weg, Timer stehen,
// externe Programme werden angehalten. So kosten Widgets beim Arbeiten und
// Spielen nichts.
PanelWindow {
    id: win

    required property ShellScreen modelData

    readonly property string screenName: win.modelData.name
    readonly property bool editing: Scenes.editing
    readonly property bool focusHere: Scenes.editing && Scenes.editScreen === win.screenName
    // Grundeinheit: 16 px bei 1440p
    readonly property real unit: 16 * win.modelData.height / 1440

    readonly property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(win.modelData)
    readonly property HyprlandWorkspace workspace: win.hyprMonitor?.activeWorkspace ?? null
    readonly property bool hasWindows: HyprIpc.windowsOn(win.workspace) > 0
                                       || HyprIpc.specialOn(win.hyprMonitor) !== ""
    readonly property bool fullscreen: win.workspace?.lastIpcObject?.hasfullscreen ?? false
    readonly property bool covered: SessionModes.gameMode || win.fullscreen
                                    || (DesktopWidgets.settings.pause === "fenster" && win.hasWindows)
    readonly property bool active: Scenes.editing || !win.covered

    screen: win.modelData
    WlrLayershell.layer: win.editing ? WlrLayer.Top : WlrLayer.Bottom
    WlrLayershell.namespace: "dynamic-island-desktop"
    WlrLayershell.keyboardFocus: win.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // Beim Bearbeiten deckend: keine Fenster dahinter, nur Wallpaper + Widgets
    color: win.editing ? Colors.background : "transparent"
    // Leere Maske = keine Eingabe; beim Bearbeiten das ganze Fenster
    mask: win.editing ? null : noInput

    Region {
        id: noInput
    }

    // Ohne Widgets und ausserhalb der Bearbeitung bleibt die Flaeche leer –
    // es wird nichts gezeichnet ausser dem ersten, durchsichtigen Frame
    Item {
        id: stage

        anchors.fill: parent
        focus: win.editing

        // Druck irgendwo auf diesem Monitor: Tastatur und Widget-Auswahl
        // wandern hierher. Passiver Griff – Ziehen/Klicks bleiben unberuehrt
        PointHandler {
            enabled: win.editing && !win.focusHere
            onActiveChanged: if (active) Scenes.editScreen = win.screenName
        }

        // Ausgewaehltes Widget (setzt WidgetHost) – fuer "Klick ins Leere"
        property Item selectedHost: null
        // Ein Widget wird gerade auf gleiche Breite/Hoehe eines anderen
        // skaliert ({ id, title, axis }, setzt WidgetHost) – das andere zeigt es an
        property var sizeMatch: null
        // Oberstes Widget an einem Punkt (Buehnenkoordinaten): das ausgewaehlte
        // zuerst (es liegt oben, samt Griff und Optionsfeld), sonst wie
        // gezeichnet von oben nach unten. Ueberlappende Widgets bekommen einen
        // Druck alle – auswaehlen darf sich nur dieses (WidgetHost)
        function hostAt(x: real, y: real): Item {
            const sel = stage.selectedHost;
            if (sel && sel.selected && sel.owns(x, y))
                return sel;
            const kids = stage.children;
            for (let i = kids.length - 1; i >= 0; i--) {
                const c = kids[i];
                if (c !== sel && typeof c.owns === "function" && c.owns(x, y))
                    return c;
            }
            return null;
        }

        // Maus ueber Leiste oder Optionsfeld: Widgets darunter nehmen nichts an
        readonly property bool overUi: (barLoader.item?.hovered ?? false)
                                       || (pickerLoader.item?.hovered ?? false)
                                       || (stage.selectedHost?.panelHovered ?? false)

        // Liegt ein Punkt (Buehnenkoordinaten) auf der Leiste oder der
        // Widget-Auswahl? Die nehmen Klicks selbst an, Qt 6 reicht sie aber
        // trotzdem an die Handler darunter weiter
        function onUi(x: real, y: real): bool {
            for (const l of [barLoader, pickerLoader]) {
                const it = l.item;
                if (!it)
                    continue;
                const p = it.mapFromItem(stage, x, y);
                if (p.x >= 0 && p.y >= 0 && p.x <= it.width && p.y <= it.height)
                    return true;
            }
            return false;
        }

        // Esc: erst Auswahl weg, dann Abbrechen (alles zurueck). Enter: Fertig.
        Keys.onPressed: event => {
            if (!win.editing)
                return;
            const sel = Scenes.selectedWidget;
            const step = event.modifiers & Qt.ShiftModifier ? 0.02 : 0.004;
            if (event.key === Qt.Key_Escape) {
                // Erst die Widget-Liste zu, dann die Auswahl weg, dann Abbrechen
                if (Scenes.adding)
                    Scenes.adding = false;
                else if (Scenes.selected !== "")
                    Scenes.selected = "";
                else
                    Scenes.cancel();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                Scenes.done();
            } else if (sel && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
                Scenes.remove(sel.id);
            } else if (sel && event.key === Qt.Key_Left) {
                Scenes.patch(sel.id, { x: Math.max(0, sel.x - step) });
            } else if (sel && event.key === Qt.Key_Right) {
                Scenes.patch(sel.id, { x: Math.min(1, sel.x + step) });
            } else if (sel && event.key === Qt.Key_Up) {
                Scenes.patch(sel.id, { y: Math.max(0, sel.y - step) });
            } else if (sel && event.key === Qt.Key_Down) {
                Scenes.patch(sel.id, { y: Math.min(1, sel.y + step) });
            } else if (sel && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) {
                Scenes.patch(sel.id, { size: Math.min(8, (sel.size ?? 1) * 1.1) });
            } else if (sel && event.key === Qt.Key_Minus) {
                Scenes.patch(sel.id, { size: Math.max(0.3, (sel.size ?? 1) / 1.1) });
            } else {
                return;
            }
            event.accepted = true;
        }

        // Bearbeiten: das Wallpaper deckt die Fenster ab (nur solange geladen)
        Loader {
            anchors.fill: parent
            active: win.editing

            sourceComponent: WallpaperStage {
                decodeSize: Qt.size(win.modelData.width, win.modelData.height)
            }
        }

        // Bearbeiten: Grund leicht abdunkeln, Drittel-Linien andeuten
        Rectangle {
            id: backdrop

            anchors.fill: parent
            visible: win.editing
            color: Colors.alpha("#000000", 0.28)

            // Nur ein Klick auf freie Flaeche hebt die Auswahl auf – nicht auf
            // ein Widget samt Rahmen, Groessen-Griff und Optionsfeld (die
            // liegen ausserhalb seiner Grenzen, childAt saehe dort nur den
            // Hintergrund) und nicht auf die Leiste. Ist die Widget-Liste
            // offen, schliesst der Klick erst sie.
            TapHandler {
                onTapped: point => {
                    const x = point.position.x, y = point.position.y;
                    // Klicks auf Leiste/Auswahl sind kein Klick ins Leere –
                    // sonst schloesse "Widget" seine Auswahl gleich wieder
                    // und jeder Knopf hoebe die Auswahl auf
                    if (stage.onUi(x, y))
                        return;
                    for (const child of stage.children)
                        if (typeof child.owns === "function" && child.owns(x, y))
                            return;
                    if (Scenes.adding) {
                        Scenes.adding = false;
                        return;
                    }
                    Scenes.selected = "";
                }
            }

            // Rechtsklick: auf ein Widget = auswaehlen, ins Leere = Widget-
            // Auswahl an dieser Stelle (das neue Widget kommt genau hierher)
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: point => {
                    const x = point.position.x, y = point.position.y;
                    if (stage.onUi(x, y))
                        return;
                    const host = stage.hostAt(x, y);
                    if (host) {
                        Scenes.adding = false;
                        Scenes.selected = host.widget.id;
                        return;
                    }
                    Scenes.selected = "";
                    Scenes.editScreen = win.screenName;
                    Scenes.openPicker({ x: x / stage.width, y: y / stage.height });
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

        // Hilfslinien beim Einrasten (setzt WidgetHost waehrend des Ziehens)
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

        // Widgets. ListModel statt JS-Array als Modell: ein Array liesse den
        // Repeater bei jeder Aenderung (Ziehen, Option) alle Widgets neu
        // bauen – Matrix finge von vorn an, Bonsai wuechse neu.
        ListModel {
            id: ids
        }

        // Einstellung "Nur im Editor" (Schnellkachel): ausserhalb der
        // Bearbeitung keine Widgets – sie werden zerstoert, nicht nur versteckt
        // Je Widget dasselbe (`hidden` im Datensatz, Schalter im Optionsfeld)
        readonly property var shown: DesktopWidgets.settings.hidden && !Scenes.editing
                                     ? [] : Scenes.widgetsFor(win.screenName).filter(w => Scenes.editing || !w.hidden)

        onShownChanged: stage.syncIds()
        Component.onCompleted: stage.syncIds()

        function syncIds(): void {
            const want = stage.shown.map(w => w.id);
            for (let i = ids.count - 1; i >= 0; i--)
                if (!want.includes(ids.get(i).wid))
                    ids.remove(i);
            const have = [];
            for (let i = 0; i < ids.count; i++)
                have.push(ids.get(i).wid);
            for (const id of want)
                if (!have.includes(id))
                    ids.append({ wid: id });
        }

        Repeater {
            model: ids

            WidgetHost {
                required property string wid

                widget: stage.shown.find(w => w.id === wid) ?? null
                screenName: win.screenName
                shellScreen: win.modelData
                unit: win.unit
                active: win.active
                editing: win.editing
                // Ein Widget auf allen Monitoren ("*") ist auf jedem
                // ausgewaehlt – sein Optionsfeld nur auf dem aktiven
                showOptions: win.focusHere
                blocked: stage.overUi
                guideX: guideX
                guideY: guideY
            }
        }

        // Stelle eines Rechtsklicks: hier landet das neue Widget
        Rectangle {
            readonly property var at: win.focusHere && Scenes.adding ? Scenes.addAt : null

            visible: at !== null
            z: 24
            x: Math.round((at?.x ?? 0) * stage.width - width / 2)
            y: Math.round((at?.y ?? 0) * stage.height - height / 2)
            width: 22
            height: 22
            radius: 11
            color: Colors.alpha(Colors.primary, 0.25)
            border.width: 2
            border.color: Colors.primary

            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: Colors.primary
            }
        }

        // Widget-Auswahl: ueber der Leiste bzw. am Rechtsklick (rechts unten
        // davon, am Bildschirmrand eingefangen; unten zu wenig Platz = darueber)
        Loader {
            id: pickerLoader

            readonly property var at: Scenes.addAt
            readonly property real w: item?.width ?? 0
            readonly property real h: item?.height ?? 0

            active: win.focusHere && Scenes.adding
            z: 25
            x: {
                if (!at)
                    return Math.round((stage.width - w) / 2);
                return Math.round(Math.max(16, Math.min(stage.width - w - 16, at.x * stage.width + 18)));
            }
            y: {
                if (!at)
                    return Math.round(barLoader.y - h - 12);
                const py = at.y * stage.height;
                const below = py + 18 + h + 16 <= stage.height;
                return Math.round(Math.max(16, below ? py + 18 : py - h - 18));
            }

            sourceComponent: WidgetPicker {}

            // Nach dem Schliessen gehoeren die Tasten wieder der Buehne
            onActiveChanged: if (!active && win.editing) stage.forceActiveFocus()
        }

        // Bearbeitungsleiste unten mittig
        Loader {
            id: barLoader

            active: win.focusHere
            // ueber den Widgets (auch ueber dem Visualiser "unten")
            z: 20
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 36

            sourceComponent: EditBar {
                screenName: win.screenName
            }
        }
    }
}
