pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// Bildschirm-Dienst: liest die Monitore aus `hyprctl monitors all -j` und
// setzt Aenderungen uber `hyprctl eval` (hl.monitor) wieder zurueck.
//
// WICHTIG: Die laufende Config ist hyprland.lua (Hyprland ab 0.55 mit
// Lua-Parser). `hyprctl keyword monitor` wird abgelehnt ("can't work with
// non-legacy parsers"), deshalb laeuft alles über eval:
//
//   hyprctl eval 'hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@180",
//                              position = "1920x0", scale = 1 })'
//
// Zwei Stufen:
//   1. ANWENDEN  – sofort im laufenden Hyprland, haelt bis reload/reboot
//   2. SPEICHERN – schreibt ~/.config/hypr/monitors.lua (mit Backup) und
//                  haengt per dofile in hyprland.lua dran (siehe dort)
//
// Entwurf (draft): Aenderungen werden erst gesammelt und erst mit apply()
// gesetzt. Verworfen wird mit revert(), angewandt mit apply(), dauerhaft
// mit persist(). Nach apply()/reload wird neu gelesen.
//
// Regeln fuer die eval-Zeilen:
//   - mode-Strings werden EXAKT aus availableModes übernommen (der eigene
//     Rundungsstring "1920x1080@60" matcht "1920x1080@60.00" nicht)
//   - vrr ist ein Int -1..3 (Boolean wirft den Parser-Fehler)
//   - mirror ist der Ausgangsname oder '' (nie 'none' – das waere ein Name)
//
// Benutzung:  import qs.modules.services.monitors
Singleton {
    id: root

    // Rohdaten aus hyprctl, in Lesereihenfolge
    property var monitors: []
    property bool loaded: false
    property bool busy: false

    // Anforderungen der Oberflaeche (Kachel/Fenster), siehe core/Demand.qml
    readonly property Demand demand: Demand {}

    // Entwurf je Moniturname: { mode, x, y, scale, transform, mirror, vrr, enabled }
    // Fehlende Schluessel bedeuten "wie gerade aktiv".
    property var draft: ({})

    // Letzte Meldung von hyprctl oder dem Speichern (leer = alles gut)
    property string status: ""

    readonly property string luaPath: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"

    // ------------------------------------------------------- Lesen ----

    function refresh(): void {
        if (!readProc.running)
            readProc.running = true;
    }

    Process {
        id: readProc

        command: ["hyprctl", "monitors", "all", "-j"]

        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onExited: (code) => {
            if (code !== 0)
                root.status = "hyprctl monitors fehlgeschlagen (Code " + code + ")";
        }
    }

    function parse(text: string): void {
        try {
            const list = JSON.parse(text);
            root.monitors = list.map(m => {
                // availableModes EXAKT übernehmen, deduplizieren (es gibt
                // Duplikate) und nach Aufloesung/Hertz sortieren
                const seen = new Set();
                const modes = [];
                for (const s of (m.availableModes ?? [])) {
                    const raw = String(s).replace(/Hz$/, "");
                    if (seen.has(raw))
                        continue;
                    seen.add(raw);
                    const parts = raw.split("@");
                    const wh = parts[0].split("x");
                    modes.push({
                        mode: raw,
                        w: parseInt(wh[0]),
                        h: parseInt(wh[1]),
                        refresh: parts[1] ? parseFloat(parts[1]) : 0
                    });
                }
                modes.sort((a, b) => (b.w - a.w) || (b.h - a.h) || (b.refresh - a.refresh));

                return {
                    name: m.name,
                    description: m.description ?? "",
                    make: m.make ?? "",
                    model: m.model ?? "",
                    serial: m.serial ?? "",
                    width: m.width,
                    height: m.height,
                    refreshRate: m.refreshRate,
                    x: m.x,
                    y: m.y,
                    scale: m.scale,
                    transform: m.transform ?? 0,
                    disabled: !!m.disabled,
                    // hyprctl meldet "none" – intern leer lassen
                    mirrorOf: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
                    // hyprctl vrr: bool -> Int fuer hl.monitor (-1 unset, 0..3)
                    vrr: m.vrr ? 1 : -1,
                    focused: !!m.focused,
                    modes: modes
                };
            });
            root.loaded = true;
        } catch (e) {
            console.warn("Monitors: hyprctl-JSON nicht lesbar:", e);
        }
    }

    // Exakter Modusstring fuer den ZUSTAENDIGEN Modus (aus availableModes),
    // damit die Auswahl-Chip-Markierung greift. Fallback: eigene Rundung.
    function currentModeString(m: var): string {
        if (m === null || m === undefined)
            return "";
        for (const c of m.modes) {
            if (c.w === m.width && c.h === m.height
                && Math.abs(c.refresh - m.refreshRate) < 0.1)
                return c.mode;
        }
        return m.width + "x" + m.height + "@" + (Math.round(m.refreshRate * 100) / 100);
    }

    // ------------------------------------------------- Entwurf ----

    // Wirksamer Wert: Entwurf schlaegt den laufenden Zustand
    function eff(name: string, key: string, fallback: var): var {
        const d = root.draft[name];
        return d && d[key] !== undefined ? d[key] : fallback;
    }

    function live(name: string): var {
        return root.monitors.find(m => m.name === name) ?? null;
    }

    function set(name: string, key: string, value: var): void {
        const next = Object.assign({}, root.draft);
        const d = Object.assign({}, next[name] ?? {});
        d[key] = value;
        next[name] = d;
        root.draft = next;
    }

    function clear(name: string): void {
        const next = Object.assign({}, root.draft);
        delete next[name];
        root.draft = next;
    }

    readonly property bool dirty: Object.keys(root.draft).length > 0

    function revert(): void {
        root.draft = ({});
        root.refresh();
    }

    // ------------------------------------------ Geometrie/Hilfen ----

    // Effektive logische Breite/Hoehe (transform dreht mit, scale teilt)
    function logicalSize(m: var): var {
        if (m === null || m === undefined)
            return { w: 1, h: 1 };
        const mode = root.eff(m.name, "mode", root.currentModeString(m));
        const parts = String(mode).split("@")[0].split("x");
        const w = parseInt(parts[0]) || m.width;
        const h = parseInt(parts[1]) || m.height;
        const scale = root.eff(m.name, "scale", m.scale);
        const t = root.eff(m.name, "transform", m.transform);
        return t % 2 === 1
            ? { w: h / scale, h: w / scale }
            : { w: w / scale, h: h / scale };
    }

    // Ausschnitt der gesamten Anordnung: Ursprung + Masse in logischen Pixeln
    function layoutInfo(): var {
        let minX = 0, minY = 0, maxX = 0, maxY = 0, first = true;
        for (const m of root.monitors) {
            if (!root.eff(m.name, "enabled", !m.disabled))
                continue;
            const x = root.eff(m.name, "x", m.x);
            const y = root.eff(m.name, "y", m.y);
            const s = root.logicalSize(m);
            if (first) {
                minX = x; minY = y; maxX = x + s.w; maxY = y + s.h;
                first = false;
            } else {
                minX = Math.min(minX, x);
                minY = Math.min(minY, y);
                maxX = Math.max(maxX, x + s.w);
                maxY = Math.max(maxY, y + s.h);
            }
        }
        if (first)
            return { x: 0, y: 0, w: 1, h: 1 };
        return { x: minX, y: minY, w: Math.max(1, maxX - minX), h: Math.max(1, maxY - minY) };
    }

    // Kanten-Snapping wie Plasma: naechstgelegene Kante eines anderen
    // Monitors anlegen, wenn nahe genug (logische Pixel). `tol` laesst sich
    // hochsetzen fuer das harte Andocken beim Loslassen.
    function snap(name: string, nx: real, ny: real, tol = 16): var {
        const me = root.live(name);
        if (me === null)
            return { x: nx, y: ny };
        const sz = root.logicalSize(me);
        let bx = nx, by = ny;

        const best = (start, candidates) => {
            let v = start, d = tol;
            for (const c of candidates) {
                const cd = Math.abs(c - start);
                if (cd < d) {
                    d = cd;
                    v = c;
                }
            }
            return v;
        };

        for (const o of root.monitors) {
            if (o.name === name)
                continue;
            if (!root.eff(o.name, "enabled", !o.disabled))
                continue;
            const ox = root.eff(o.name, "x", o.x);
            const oy = root.eff(o.name, "y", o.y);
            const os = root.logicalSize(o);

            bx = best(bx, [ox, ox + os.w - sz.w, ox + os.w, ox - sz.w]);
            by = best(by, [oy, oy + os.h - sz.h, oy + os.h, oy - sz.h]);
        }
        return { x: bx, y: by };
    }

    // Skalierungsstufen, die fuer diese Aufloesung sauber teilen
    // (Hyprland: "Invalid scale", sonst kaputte logische Pixel)
    function validScales(m: var): var {
        if (m === null || m === undefined)
            return [1];
        const t = root.eff(m.name, "transform", m.transform);
        const rotated = t % 2 === 1;
        const w = rotated ? m.height : m.width;
        const h = rotated ? m.width : m.height;
        const out = [];
        for (const s of [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3]) {
            const lw = w / s;
            const lh = h / s;
            if (Math.abs(lw - Math.round(lw)) < 0.001 && Math.abs(lh - Math.round(lh)) < 0.001)
                out.push(s);
        }
        return out;
    }

    // ------------------------------------------------- Anwenden ----

    // Eine hl.monitor-Zeile fuer einen Monitorentwurf
    function ruleFor(m: var, persistent = false): string {
        const output = JSON.stringify(persistent && m.description ? "desc:" + m.description : m.name);
        const mode = root.eff(m.name, "mode", root.currentModeString(m));
        const x = root.eff(m.name, "x", m.x);
        const y = root.eff(m.name, "y", m.y);
        const scale = root.eff(m.name, "scale", m.scale);
        const transform = root.eff(m.name, "transform", m.transform);
        const mirror = root.eff(m.name, "mirror", m.mirrorOf);
        // vrr IMMER Int: -1 unset/global, 0 aus, 1 ein, 2/3 Vollbild
        const vrr = root.eff(m.name, "vrr", m.vrr);
        const enabled = root.eff(m.name, "enabled", !m.disabled);

        if (!enabled)
            return `hl.monitor({ output = ${output}, disabled = true })`;

        // mirror IMMER explizit (leer = kein Spiegel) – ohne das bleibt ein
        // alter Spiegel aus frueheren Regeln haengen
        return `hl.monitor({ output = ${output}, mode = '${mode}', `
             + `position = '${x}x${y}', scale = ${scale}, transform = ${transform}, `
             + `mirror = '${mirror}', vrr = ${vrr} })`;
    }

    function apply(): void {
        if (!root.loaded)
            return;
        if (root.busy) {
            // gerade laeuft: gleich nach (wird z.B. nach Drag-Ende while
            // apply noch laeuft erneut versucht)
            retryApply.restart();
            return;
        }

        // NUR die geaenderten Monitore setzen – unveraenderte bleiben unberuehrt
        // (wichtig bei evdi/DisplayLink: jede Neuanwendung kann die Connectoren
        // neu enumerieren und Port-Namen tauschen)
        const names = Object.keys(root.draft);
        if (names.length === 0) {
            root.status = "Keine Aenderungen";
            return;
        }
        const changed = names.map(n => root.live(n)).filter(m => m !== null);
        // Erst eingeschaltete Monitore, dann abgeschaltete – nie ein
        // Fenster, in dem gar nichts mehr leuchtet
        const on = changed.filter(m => root.eff(m.name, "enabled", !m.disabled));
        const off = changed.filter(m => !root.eff(m.name, "enabled", !m.disabled));
        const script = on.concat(off).map(m => root.ruleFor(m)).join("\n");

        root.busy = true;
        root.status = "Wende an …";
        evalProc.command = ["hyprctl", "eval", script];
        evalProc.running = false;
        evalProc.running = true;
    }

    Timer {
        id: retryApply

        interval: 250
        onTriggered: root.apply()
    }

    Process {
        id: evalProc

        property string reply: ""
        onStarted: reply = ""
        stdout: StdioCollector {
            onStreamFinished: evalProc.reply = text.trim()
        }

        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                root.status = text.trim()
        }

        onExited: (code) => {
            root.busy = false;
            if (code === 0 && (evalProc.reply === "" || evalProc.reply === "ok")) {
                root.status = "Angewandt";
                // Noch vor dem Leeren speichern: die Live-Liste ist hier alt.
                root.persist();
                root.draft = ({});
                // DisplayLink braucht beim Umschalten – kurz warten, dann
                // zweiter Lesedurchlauf (refreshDelay), damit die UI sicher
                // den echten Zustand zeigt
                refreshDelay.restart();
            } else {
                root.status = "Anwenden fehlgeschlagen: " + (evalProc.reply || ("Code " + code));
                // Entwurf behalten, damit nichts verloren geht
            }
        }
    }

    Timer {
        id: refreshDelay

        interval: 500
        onTriggered: {
            root.refresh();
            secondRefresh.restart();
        }
    }

    Timer {
        id: secondRefresh

        interval: 1200
        onTriggered: root.refresh()
    }

    // ------------------------------------------------- Speichern ----

    // Atomares Schreiben von monitors.lua mit Zeitstempel-Backup daneben
    readonly property string persistScript: `
import sys, os, time, shutil, tempfile
path = sys.argv[1]
if os.path.exists(path):
    shutil.copy2(path, path + ".bak-" + str(time.time_ns()))
fd, tmp = tempfile.mkstemp(prefix=".monitors-", dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    f.write(sys.argv[2])
    f.flush()
    os.fsync(f.fileno())
os.replace(tmp, path)
fd = os.open(os.path.dirname(path), os.O_DIRECTORY)
os.fsync(fd)
os.close(fd)
with open(path) as f:
    if f.read() != sys.argv[2]:
        raise RuntimeError("Gespeicherte Monitorregeln stimmen nicht ueberein")
`

    // Aktuellen (entwurfsfreien) Stand aller Monitore als Lua-Datei.
    // Die Regeln stehen NACH den festen in hyprland.lua (dofile am Ende),
    // damit sie gewinnen.
    function persist(): void {
        if (root.busy || !root.loaded)
            return;

        const stamp = Qt.formatDateTime(new Date(), "dd.MM.yyyy, HH:mm");
        const lines = [
            `-- Von dynamic-island (Bildschirmmanager) erzeugt, ${stamp}.`,
            `-- Wird von hyprland.lua per dofile geladen und gewinnt gegen die`,
            `-- festen Regeln dort. Von Hand durfen geaendert werden; der`,
            `-- Manager schreibt diese Datei beim Speichern neu.`,
            ""
        ];
        // Entwurf zuerst anwenden, damit die Datei dem entspricht, was gerade
        // sichtbar ist – apply() leert danach den Entwurf, deshalb die Zeilen
        // JETZT aus dem aktuellen Zustand bauen (inkl. Draft-Werte).
        for (const m of root.monitors)
            lines.push(root.ruleFor(m, true));

        root.busy = true;
        root.status = "Schreibe monitors.lua …";
        persistProc.command = ["python3", "-c", root.persistScript, root.luaPath, lines.join("\n") + "\n"];
        persistProc.running = false;
        persistProc.running = true;
    }

    Process {
        id: persistProc

        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                root.status = text.trim()
        }

        onExited: (code) => {
            root.busy = false;
            if (code === 0) {
                root.status = "Gespeichert in monitors.lua";
                // Neuladen, damit der Datei-Inhalt auch wirklich greift
                reloadProc.running = false;
                reloadProc.running = true;
            } else {
                root.status = "Speichern fehlgeschlagen (Code " + code + ")";
            }
        }
    }

    Process {
        id: reloadProc

        command: ["hyprctl", "reload"]
        onExited: refreshDelay.restart()
    }
}
