pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.config
import qs.modules.services.core

// Songtext zum laufenden Titel, Zeile fuer Zeile mit der Wiedergabe.
//
// Quellen: bei Spotify zuerst Spotifys eigener Text ueber die Extension
// (MediaQueue.requestLyrics, Antwort in MediaQueue.lyrics), sonst bzw. ohne
// Treffer lrclib.net (lyrics.py, mit Cache in ~/.cache/dynamic-island/lyrics).
//
// Mitlaufen ohne Polling: die MPRIS-Position laesst sich jederzeit lesen
// (Quickshell rechnet sie aus der letzten bekannten Position und der seither
// vergangenen Zeit). Daraus folgt die aktuelle Zeile, und EIN Timer schlaeft
// genau bis zur naechsten. Pro Zeile ein Aufwachen, dazwischen nichts. Neu
// ausgerichtet wird bei Seek (positionChanged), Pause/Play und Titelwechsel.
//
// Laeuft nur auf Bedarf, wie Cava:
//     DemandRequest { demand: Lyrics.demand; active: shown }
//
// Benutzung:  Lyrics.lines[i].text, Lyrics.index, Lyrics.synced, Lyrics.status
Singleton {
    id: root

    readonly property Demand demand: Demand {}
    readonly property bool enabled: root.demand.active && Config.media.lyrics

    // [{ t: Millisekunden (-1 = ohne Zeit), text }]
    property var lines: []
    property bool synced: false
    // idle | loading | ok | none
    property string status: "idle"
    // spotify | lrclib
    property string source: ""
    // Aktuelle Zeile, -1 = vor der ersten
    property int index: -1
    readonly property string currentLine: root.index >= 0 ? (root.lines[root.index]?.text ?? "") : ""

    // Titel-Kennung: aendert sie sich, wird neu geladen
    readonly property string key: Media.available && Media.title !== ""
        ? `${Media.artist}\u001f${Media.title}` : ""
    property string loadedKey: ""

    // Text leicht vorziehen: man liest die Zeile, bevor sie gesungen wird
    readonly property int lead: 250

    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/dynamic-island/lyrics"
    readonly property string script: Qt.resolvedUrl("lyrics.py").toString().replace("file://", "")

    onEnabledChanged: root.refresh()
    onKeyChanged: root.refresh()

    function refresh(): void {
        if (!root.enabled || root.key === "") {
            lineTimer.stop();
            return;
        }
        if (root.key === root.loadedKey) {
            root.sync();
            return;
        }
        root.loadedKey = root.key;
        root.lines = [];
        root.index = -1;
        root.synced = false;
        root.source = "";
        root.status = "loading";
        lineTimer.stop();
        fetch.running = false;

        // Spotify kennt seine Texte selbst – kurz auf die Extension warten
        if (MediaQueue.valid && Media.source === "Spotify") {
            MediaQueue.lyrics = null;
            MediaQueue.requestLyrics();
            spotifyWait.restart();
        } else {
            root.fetchLrclib();
        }
    }

    function fetchLrclib(): void {
        spotifyWait.stop();
        fetch.forKey = root.key;
        fetch.command = ["python3", "-I", root.script, root.cacheDir,
            Media.artist, Media.title, Media.album,
            String(Media.hasLength ? Math.round(Media.length) : 0)];
        fetch.running = true;
    }

    function accept(result: var, from: string): void {
        if (!result || result.none || !Array.isArray(result.lines) || result.lines.length === 0) {
            root.status = "none";
            root.lines = [];
            return;
        }
        root.source = from;
        root.synced = !!result.synced;
        root.lines = result.lines;
        root.status = "ok";
        root.sync();
    }

    // Spotifys Antwort: passt sie zum laufenden Titel, nehmen, sonst lrclib
    Connections {
        target: MediaQueue

        function onLyricsChanged(): void {
            const l = MediaQueue.lyrics;
            if (!spotifyWait.running || !l || l.title !== Media.title)
                return;
            spotifyWait.stop();
            if (Array.isArray(l.lines) && l.lines.length > 0)
                root.accept(l, "spotify");
            else
                root.fetchLrclib();
        }
    }

    Timer {
        id: spotifyWait

        interval: 1500
        onTriggered: root.fetchLrclib()
    }

    Process {
        id: fetch

        property string forKey: ""

        stdout: StdioCollector {
            id: fetched

            onStreamFinished: {
                // Inzwischen anderer Titel: Ergebnis verwerfen
                if (fetch.forKey !== root.key)
                    return;
                let result = null;
                try {
                    result = JSON.parse(fetched.text);
                } catch (e) {}
                root.accept(result, "lrclib");
            }
        }
    }

    // ---- Mitlaufen ----

    function positionMs(): real {
        const p = Media.active?.position ?? 0;
        return p * 1000 + root.lead;
    }

    // Aktuelle Zeile bestimmen und den Timer auf die naechste stellen
    function sync(): void {
        lineTimer.stop();
        if (!root.enabled || !root.synced || root.lines.length === 0)
            return;

        const now = root.positionMs();
        // Binaere Suche: letzte Zeile mit t <= now
        let lo = 0, hi = root.lines.length - 1, found = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (root.lines[mid].t <= now) {
                found = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        if (root.index !== found)
            root.index = found;

        const next = root.lines[found + 1];
        if (next && Media.playing) {
            lineTimer.interval = Math.max(30, next.t - now);
            lineTimer.start();
        }
    }

    Timer {
        id: lineTimer

        onTriggered: root.sync()
    }

    Connections {
        target: Media

        function onPlayingChanged(): void {
            root.sync();
        }
    }

    // Seek und andere Spruenge meldet der Player per positionChanged
    Connections {
        target: Media.active

        function onPositionChanged(): void {
            root.sync();
        }
    }
}
