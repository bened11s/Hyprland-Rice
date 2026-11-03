pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.config
import qs.modules.services.record

// Screenshot-Overlay: friert alle Monitore ein (grim), zeigt das Standbild
// als Ebene darueber, und der gezogene Ausschnitt wird aus dem Standbild
// geschnitten – was man sieht, ist was man bekommt, auch wenn sich darunter
// etwas bewegt. Die Arbeit mit Dateien macht shot.py.
//
// Oberflaeche: modules/screenshot/ScreenshotOverlay.qml (eine je Monitor).
//
// Aufruf: IPC `screenshot region|edit|ocr|qr|close`, die CLI
// (`dynamic-island screenshot -r`) leitet dorthin weiter.
//
// Benutzung:  import qs.modules.services.screenshot
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("modules/services/screenshot/shot.py")
    readonly property string freezeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dynamic-island-shot"

    // Overlay sichtbar
    property bool active: false
    // Standbilder werden gerade gemacht (Overlay noch nicht da)
    property bool freezing: false
    // Was Enter tut: "copy" | "save" | "edit" | "ocr" | "qr"
    property string preset: "copy"
    // { "<monitor>": "<pfad>" }
    property var shots: ({})
    // [{ name, x, y, w, h, scale }] logisch
    property var monitors: []
    // [{ x, y, w, h, title, cls, monitor }] global logisch, obenliegende zuerst
    property var windows: []
    // Zeitstempel des Standbilds, damit Image nicht aus dem Cache laedt
    property double frozenAt: 0
    property string lastError: ""

    // Nach einer Aktion: action, Ergebnis von shot.py
    signal done(string action, var result)

    function open(preset: string): void {
        if (root.active || root.freezing)
            return;
        root.preset = preset || "copy";
        root.freezing = true;
        freezeProc.command = ["python3", "-I", root.script, "freeze", root.freezeDir];
        freezeProc.running = true;
    }

    function close(): void {
        root.active = false;
        root.cleanup();
    }

    // Fenster eines Monitors in Monitor-Koordinaten (fuer das Einrasten)
    function windowsOn(name: string): var {
        const m = root.monitors.find(m => m.name === name);
        if (!m)
            return [];
        return root.windows.filter(w => w.monitor === name)
            .map(w => ({ x: w.x - m.x, y: w.y - m.y, w: w.w, h: w.h, title: w.title, cls: w.cls }));
    }

    function shotFor(name: string): string {
        const p = root.shots[name];
        return p ? "file://" + p + "?" + root.frozenAt : "";
    }

    // Ausschnitt (logisch, relativ zum Monitor) verarbeiten. Das Overlay
    // verschwindet sofort, das Schneiden laeuft danach.
    function act(action: string, screenName: string, x: real, y: real, w: real, h: real): void {
        const m = root.monitors.find(m => m.name === screenName);
        const shot = root.shots[screenName];
        if (!m || !shot || w < 1 || h < 1)
            return;
        root.active = false;
        actProc.action = action;
        actProc.command = ["python3", "-I", root.script, "act", action, shot,
            String(Math.round(x)), String(Math.round(y)), String(Math.round(w)), String(Math.round(h)),
            String(m.w), String(m.h)];
        actProc.running = true;
    }

    // Ausschnitt aufnehmen (gpu-screen-recorder ueber die CLI)
    function record(screenName: string, x: real, y: real, w: real, h: real): void {
        const m = root.monitors.find(m => m.name === screenName);
        if (!m)
            return;
        // gpu-screen-recorder will gerade Masse
        const ew = Math.max(2, Math.round(w) & ~1), eh = Math.max(2, Math.round(h) & ~1);
        Recorder.startRegion(`${ew}x${eh}+${Math.round(m.x + x)}+${Math.round(m.y + y)}`);
        root.close();
    }

    function cleanup(): void {
        if (actProc.running || root.freezing)
            return;
        Quickshell.execDetached(["rm", "-rf", root.freezeDir]);
        root.shots = {};
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            return { ok: false, error: text.trim() || "shot.py" };
        }
    }

    Process {
        id: freezeProc
        stdout: StdioCollector { id: freezeOut }
        onExited: {
            root.freezing = false;
            const r = root.parse(freezeOut.text);
            if (!r.ok) {
                root.lastError = r.error;
                console.warn("screenshot:", r.error);
                return;
            }
            root.lastError = "";
            root.shots = r.shots;
            root.monitors = r.monitors;
            root.windows = r.windows;
            root.frozenAt = Date.now();
            root.active = true;
        }
    }

    Process {
        id: actProc
        property string action: ""
        environment: ({
                DYNAMIC_ISLAND_LANG: Config.appearance.language
            })
        stdout: StdioCollector { id: actOut }
        onExited: {
            const r = root.parse(actOut.text);
            if (!r.ok) {
                root.lastError = r.error;
                Quickshell.execDetached(["notify-send", "-a", "dynamic-island", "-i", "dialog-error",
                    I18n.tr("Screenshot fehlgeschlagen"), r.error]);
            }
            root.done(actProc.action, r);
            if (!root.active)
                root.cleanup();
        }
    }

    IpcHandler {
        target: "screenshot"

        function region(): void {
            root.open("copy");
        }
        function save(): void {
            root.open("save");
        }
        function edit(): void {
            root.open("edit");
        }
        function ocr(): void {
            root.open("ocr");
        }
        function qr(): void {
            root.open("qr");
        }
        function close(): void {
            root.close();
        }
    }
}
