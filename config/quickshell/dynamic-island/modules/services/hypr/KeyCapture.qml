pragma ComponentBehavior: Bound
import QtQuick

import qs

// Neue Tastenkombination aufnehmen und speichern (Einstellungen >
// Tastenkürzel). Eine Instanz pro Ansicht; die Ansicht leitet ihre
// Tastenereignisse weiter, solange `active` ist:
//
//   KeyCapture { id: capture }
//   Item { focus: capture.active
//          Keys.onPressed: e => capture.press(e)
//          Keys.onReleased: e => capture.release(e) }
//
//   capture.start("set", ref, titel)            Taste eines Binds neu belegen
//   capture.start("extra", configRef, titel)    weitere Taste fuer einen Config-Bind
//   capture.start("new", "", titel, { title, exec })  eigenes Kuerzel anlegen
//
// Solange aufgenommen wird, steht Hyprland in einer Submap ohne Binds
// (Keybinds.startCapture) – sonst kaemen SUPER-Kombinationen nie an. Nach dem
// Speichern bleibt sie bis zum Loslassen aller Tasten aktiv, sonst loeste das
// Loslassen von SUPER noch das App-Menue (SUPER allein) aus.
//
// save(keys) ist auch ohne Aufnahme nutzbar (Klick auf eine Taste der
// Tastatur-Vorschau): gibt "" oder eine Fehlermeldung zurueck.
Item {
    id: root

    visible: false

    // "" | "set" | "extra" | "new"
    property string mode: ""
    property string ref: ""
    property string title: ""
    property var payload: null
    property string error: ""
    // Gerade gehaltene Modifier: Anzeige ("Super", "Alt") und als
    // Hyprland-Modmaske fuer die Tastatur-Vorschau
    property var held: []
    property int heldMask: 0
    // Gespeichert ("SUPER + T"), wartet nur noch aufs Loslassen
    property string done: ""
    readonly property bool active: root.mode !== ""
    // Ref, die das letzte Speichern angelegt/geaendert hat (bei "new" das
    // neue eigene Kuerzel, bei "extra" die Zusatztaste) – zum Auswaehlen
    property string savedRef: ""

    signal finished(string keys)
    signal cancelled

    function start(mode: string, ref: string, title: string, payload: var): void {
        // Laeuft schon eine Aufnahme: nur das Ziel tauschen. Ein
        // stopCapture()+startCapture() waeren zwei unabhaengige hyprctl-
        // Aufrufe in unbestimmter Reihenfolge – kaeme "an" vor "aus", liefe
        // die Aufnahme ohne Submap und SUPER+Q startete das Terminal.
        const running = root.active;
        releaseWait.stop();
        root.mode = mode;
        root.ref = ref;
        root.title = title;
        root.payload = payload ?? null;
        root.error = "";
        root.held = [];
        root.heldMask = 0;
        root.done = "";
        if (!running)
            Keybinds.startCapture();
    }

    function cancel(): void {
        if (!root.active)
            return;
        releaseWait.stop();
        root.reset();
        root.cancelled();
    }

    function reset(): void {
        root.mode = "";
        root.done = "";
        root.held = [];
        root.heldMask = 0;
        Keybinds.stopCapture();
    }

    // Speichern je nach Modus; "" = gespeichert, sonst Fehlermeldung
    function save(keys: string): string {
        return root.saveAs(root.mode, root.ref, keys, root.payload);
    }

    function saveAs(mode: string, ref: string, keys: string, payload: var): string {
        const conflict = HyprBinds.conflict(Keybinds.canonOf(keys), mode === "set" ? ref : "");
        if (conflict !== "")
            return I18n.tr("Schon belegt: %1").arg(conflict);
        if (mode === "set") {
            Keybinds.setKeys(ref, keys);
            root.savedRef = ref;
        } else if (mode === "extra") {
            root.savedRef = Keybinds.addExtra(ref, keys);
        } else if (mode === "new") {
            root.savedRef = Keybinds.addCustom(payload?.title ?? "", payload?.exec ?? "", keys);
        } else {
            return I18n.tr("Nichts ausgewählt");
        }
        return "";
    }

    function press(event: var): void {
        event.accepted = true;
        if (root.done !== "")
            return;
        const plainMods = Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier;
        if (event.key === Qt.Key_Escape && !(event.modifiers & plainMods)) {
            root.cancel();
            return;
        }
        const result = Keybinds.fromEvent(event);
        if (result.wait) {
            root.setHeld(event.modifiers | root.ownMod(event.key));
            return;
        }
        if (result.error) {
            root.error = I18n.tr(result.error);
            return;
        }
        const error = root.save(result.keys);
        if (error !== "") {
            root.error = error;
            return;
        }
        root.done = result.keys;
        root.error = "";
        releaseWait.restart();
    }

    function release(event: var): void {
        event.accepted = true;
        if (event.isAutoRepeat)
            return;
        // Beim Loslassen einer Modifier-Taste steht sie selbst je nach
        // Plattform noch in modifiers – hier herausrechnen
        const plain = Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier;
        const mods = event.modifiers & plain & ~root.ownMod(event.key);
        if (root.done === "")
            root.setHeld(mods);
        else if (mods === 0)
            root.finish();
    }

    function finish(): void {
        const keys = root.done;
        releaseWait.stop();
        root.reset();
        root.finished(keys);
    }

    function ownMod(key: int): int {
        if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R)
            return Qt.MetaModifier;
        if (key === Qt.Key_Control)
            return Qt.ControlModifier;
        if (key === Qt.Key_Alt)
            return Qt.AltModifier;
        if (key === Qt.Key_Shift)
            return Qt.ShiftModifier;
        return 0;
    }

    function setHeld(mods: int): void {
        const labels = [];
        let mask = 0;
        if (mods & Qt.MetaModifier) {
            labels.push("Super");
            mask |= 64;
        }
        if (mods & Qt.ControlModifier) {
            labels.push(I18n.tr("Strg"));
            mask |= 4;
        }
        if (mods & Qt.AltModifier) {
            labels.push("Alt");
            mask |= 8;
        }
        if (mods & Qt.ShiftModifier) {
            labels.push("Shift");
            mask |= 1;
        }
        root.held = labels;
        root.heldMask = mask;
    }

    // Hyprland faellt nach 20 s selbst aus der Submap – dann nicht weiter
    // auf Tasten warten
    Timer {
        running: root.active && root.done === ""
        interval: 19000
        onTriggered: root.cancel()
    }

    // Gespeichert, aber keine Loslassen-Meldung (Fokus weg o.ae.)
    Timer {
        id: releaseWait

        interval: 3000
        onTriggered: root.finish()
    }

    Component.onDestruction: Keybinds.stopCapture()
}
