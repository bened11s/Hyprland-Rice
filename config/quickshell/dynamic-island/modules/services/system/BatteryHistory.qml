pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs

// Akkuverlauf je Geraet – fuer die Seite "Akku" im Einstellungs-Fenster.
//
// Die Daten schreibt upowerd ohnehin mit: /var/lib/upower/history-charge-
// <Modell>-<Seriennummer>.dat, lesbar fuer alle, rund eine Woche lang, auch
// fuer Geraete, die gerade aus sind. Je Zeile "Unixzeit<TAB>Wert<TAB>Zustand",
// der Wert mit Dezimalkomma ("32,000"). Eigenheiten:
//   * "0,000 unknown" ist kein Messwert, sondern eine Luecke: davor war das
//     Geraet weg (Maus schlief, Tastatur aus). Gleich danach folgt mit
//     derselben Zeit der echte Stand.
//   * Dieselbe Seriennummer taucht unter mehreren Modellnamen auf (aeltere
//     upowerd schrieben "G502_X_PLUS", neuere "Logitech_G502_X_PLUS") – die
//     Dateien werden ueber die Seriennummer zusammengefuehrt.
//   * upowerd speichert nur alle paar Minuten; den Stand von jetzt haengt
//     die Seite aus Power (live) an.
//   * Die G915 meldet beim Laden am Kabel "fully-charged" bei 3 %, 7 %, 12 %
//     – unter 95 % zaehlt "fully-charged" hier als Laden.
//
// Gelesen wird nur auf Anfrage (refresh(), die Seite ruft es beim Oeffnen
// und jede Minute, solange sie offen ist).
//
// Benutzung:  import qs.modules.services.system
Singleton {
    id: root

    readonly property string dir: "/var/lib/upower"
    // Handy und Headset (Power.extraBatteries) – die kennt upowerd nicht,
    // Power schreibt ihren Verlauf im selben Format selbst
    readonly property string ownDir: Power.historyDir

    // [{ key, name, aliases, serial, points: [{ t, v, state }], segments: [[Index…]] }]
    // points: zeitlich sortiert, ohne Lueckenmarken; t in Sekunden.
    // segments: zusammenhaengende Abschnitte (zwischen zwei Luecken).
    property var devices: []
    property bool loading: false
    property double loadedAt: 0

    // Welches Geraet die Akku-Seite zeigen soll (Klick auf einen Chip in der
    // Uebersicht) – als Modellname, die Seite sucht es in `aliases`
    property string focusModel: ""
    property int focusSerial: 0

    function focus(model: string): void {
        root.focusModel = model;
        root.focusSerial++;
    }

    function refresh(): void {
        if (!reader.running)
            reader.running = true;
    }

    // Laedt das Geraet in diesem Abschnitt? (Zustand aus der Datei)
    function isCharging(state: string, value: real): bool {
        return state === "charging" || state === "pending-charge"
            || (state === "fully-charged" && value < 95);
    }

    // Seriennummer am Dateinamen-Ende: "5f-43-fb-6b", "A4:CC:B3:E5:6F:F0"
    // oder eine USV-Nummer wie "5B2411TH1541__"
    function splitName(stem: string): var {
        const m = stem.match(/^(.*)-((?:[0-9A-Fa-f]{2}[-:]){3,}[0-9A-Fa-f]{2}|[0-9A-Z]{8,}_*)$/);
        return m ? { model: m[1], serial: m[2] } : { model: stem, serial: "" };
    }

    function parse(text: string): var {
        const byKey = {};
        let current = null;

        for (const raw of text.split("\n")) {
            const line = raw.trim();
            if (line === "")
                continue;
            if (line.startsWith("#")) {
                const stem = line.slice(1).replace(/^history-charge-/, "").replace(/\.dat$/, "");
                // generic_id: Sammeldatei ohne Geraet dahinter
                if (stem === "generic_id") {
                    current = null;
                    continue;
                }
                const parts = root.splitName(stem);
                const key = parts.serial !== "" ? parts.serial : parts.model;
                current = byKey[key] ?? (byKey[key] = { key, serial: parts.serial, models: [], raw: [] });
                current.models.push(parts.model);
                continue;
            }
            if (!current)
                continue;
            const cols = line.split("\t");
            if (cols.length < 3)
                continue;
            const t = Number(cols[0]);
            const v = Number(cols[1].replace(",", "."));
            if (!isFinite(t) || !isFinite(v))
                continue;
            current.raw.push({ t, v, state: cols[2] });
        }

        const out = [];
        for (const key in byKey) {
            const d = byKey[key];
            // Zusammengefuehrte Dateien: sortieren, doppelte Zeilen raus.
            // Lueckenmarken vor dem echten Wert gleicher Zeit einsortieren.
            d.raw.sort((a, b) => a.t - b.t || (a.state === "unknown" ? -1 : 0) - (b.state === "unknown" ? -1 : 0));
            const points = [];
            const segments = [];
            let seg = [];
            let last = null;
            for (const p of d.raw) {
                if (p.state === "unknown" && p.v === 0) {
                    if (seg.length > 0)
                        segments.push(seg);
                    seg = [];
                    continue;
                }
                if (last && last.t === p.t && last.v === p.v && last.state === p.state)
                    continue;
                seg.push(points.length);
                points.push(p);
                last = p;
            }
            if (seg.length > 0)
                segments.push(seg);
            if (points.length === 0)
                continue;

            // Name: der laengste Modellname ist meist der neue mit Hersteller
            const model = d.models.reduce((a, b) => b.length > a.length ? b : a, "");
            out.push({
                key: d.key,
                serial: d.serial,
                name: model.replace(/_/g, " ").trim(),
                // alle Modellnamen, um das Geraet in UPower wiederzufinden
                aliases: d.models.map(m => m.replace(/_/g, " ").trim()),
                points,
                segments
            });
        }
        // Zuletzt gesehene Geraete zuerst
        out.sort((a, b) => b.points[b.points.length - 1].t - a.points[a.points.length - 1].t);
        return out;
    }

    // Kennzahlen eines Geraets ab `since` (Sekunden). `live` ist der Stand
    // von jetzt ({ t, v, state }) oder null, wenn das Geraet nicht da ist.
    //   rate         Verbrauch in %/h beim Entladen (nur verbundene Zeit)
    //   remaining    geschaetzte Restlaufzeit in Stunden (aus rate)
    //   lastCharged  Zeitpunkt, an dem zuletzt geladen wurde (oder 0)
    //   min/max      tiefster/hoechster Stand im Zeitraum
    function stats(device: var, since: real, live: var): var {
        const pts = device?.points ?? [];
        let drop = 0;
        let span = 0;
        let lastCharged = 0;
        let min = 101;
        let max = -1;

        const consider = (a, b, connected) => {
            if (b.v > a.v || root.isCharging(b.state, b.v))
                lastCharged = Math.max(lastCharged, b.t);
            // Verbrauch nur aus verbundenen Entlade-Strecken; ueber eine
            // Luecke weiss man nicht, wie lange das Geraet lief
            if (!connected || b.t < since || a.t < since)
                return;
            if (!root.isCharging(a.state, a.v) && !root.isCharging(b.state, b.v) && b.v <= a.v) {
                drop += a.v - b.v;
                span += b.t - a.t;
            }
        };

        for (const seg of device?.segments ?? []) {
            for (let i = 1; i < seg.length; i++)
                consider(pts[seg[i - 1]], pts[seg[i]], true);
        }
        // Ueber Luecken hinweg: gestiegen = dazwischen geladen
        for (let s = 1; s < (device?.segments ?? []).length; s++) {
            const prev = device.segments[s - 1];
            consider(pts[prev[prev.length - 1]], pts[device.segments[s][0]], false);
        }
        if (live && pts.length > 0)
            consider(pts[pts.length - 1], live, true);
        for (const p of pts) {
            if (root.isCharging(p.state, p.v))
                lastCharged = Math.max(lastCharged, p.t);
            if (p.t >= since) {
                min = Math.min(min, p.v);
                max = Math.max(max, p.v);
            }
        }
        if (live) {
            min = Math.min(min, live.v);
            max = Math.max(max, live.v);
        }

        // Unter 2 % Abfall oder 30 min Messzeit ist die Rate Rauschen
        const rate = drop >= 2 && span >= 1800 ? drop / (span / 3600) : 0;
        const now = live?.v ?? (pts.length > 0 ? pts[pts.length - 1].v : 0);
        return {
            rate,
            remaining: rate > 0 ? now / rate : 0,
            lastCharged,
            min: min <= 100 ? min : -1,
            max: max >= 0 ? max : -1
        };
    }

    Process {
        id: reader

        command: ["sh", "-c",
            'for d in "$@"; do'
            + '  cd "$d" 2>/dev/null || continue;'
            + '  for f in history-charge-*.dat; do'
            + '    [ -r "$f" ] || continue;'
            + '    echo "#$f"; cat "$f"; echo;'
            + '  done;'
            + ' done', "sh", root.dir, root.ownDir]
        onRunningChanged: root.loading = running

        stdout: StdioCollector {
            onStreamFinished: {
                root.devices = root.parse(text);
                root.loadedAt = Date.now() / 1000;
            }
        }
    }
}
