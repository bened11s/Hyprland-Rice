pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.core
import qs.modules.services.config

// Stand und Updates der Shell selbst – also dieses Git-Repos
// (Hyprland-Rice), nicht der Systempakete.
//
//  * Stand: Branch, Commit, Datum, `git describe`, Upstream und die eigenen
//    (nicht eingecheckten) Aenderungen – ein Skript, gelesen sobald jemand
//    hinsieht (`watching` per DemandRequest, Muster SystemStats).
//  * Pruefen: dasselbe Skript mit `git fetch` davor; danach stehen die
//    neuen Commits des Upstreams in `incoming`. Beim Oeffnen (Cache 15 min),
//    auf Knopfdruck und – falls eingestellt – alle paar Stunden im
//    Hintergrund (Config.system.updateCheckHours).
//  * Aktualisieren: shellupdate.sh, abgekoppelt gestartet. Der Pull aendert
//    QML-Dateien, Quickshell laedt dann neu und beendet seine Kindprozesse –
//    darum kein Process hier, sondern eine Logdatei, die wir beobachten
//    (`updateStep`, `updateDone`, `updateFailed`, `updateError`). Das Skript
//    startet die Shell am Ende neu wie die CLI (`dynamic-island shell -k`,
//    dann `shell -d`); die neue Instanz liest das Protokoll beim Start und
//    zeigt noch "Aktualisiert".
//
// Das Repo wird ueber den eigenen Pfad gefunden: ~/.config/quickshell/
// dynamic-island ist ein Symlink ins Repo, `readlink -f` plus
// `git rev-parse --show-toplevel`; Rueckfall ~/hyprland-rice.
//
// Benutzung:  import qs.modules.services.system
Singleton {
    id: root

    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active

    readonly property string home: Quickshell.env("HOME")
    readonly property string shellFile: Quickshell.shellPath("shell.qml")
    readonly property string fallbackRepo: root.home + "/hyprland-rice"
    readonly property string script: Quickshell.shellPath("modules/services/system/shellupdate.sh")
    readonly property string logPath: root.home + "/.local/state/dynamic-island/shell-update.log"
    readonly property string cli: root.home + "/.local/bin/dynamic-island"

    // ---- Stand ----
    property bool loaded: false
    property string repo: ""           // Wurzel des Repos ("" = keins gefunden)
    property string branch: ""
    property string commit: ""         // kurzer Hash
    property string commitDate: ""     // JJJJ-MM-TT
    property string commitAge: ""      // "vor 3 Tagen"
    property string describe: ""       // Tag-Abstand-Hash oder nur Hash
    property string upstream: ""       // z. B. origin/main
    property var localChanges: []      // [{ status, file }] aus git status --porcelain
    readonly property int localCount: root.localChanges.length
    property int behind: 0             // Commits, die der Upstream voraus ist
    property int ahead: 0              // eigene Commits, die oben fehlen
    property var incoming: []          // [{ hash, subject, when }] HEAD..@{u}

    // ---- Pruefung ----
    // "idle" (nie), "checking", "ok", "error"
    property string checkState: "idle"
    property string checkError: ""
    property double lastCheck: 0       // ms seit Epoche, 0 = nie geholt
    readonly property bool checking: root.checkState === "checking"
    readonly property int cacheMs: 15 * 60 * 1000

    // ---- Update-Lauf (aus der Logdatei) ----
    property string updateStep: ""     // "", "pull", "build", "hypr", "restart"
    property bool updateDone: false
    property bool updateFailed: false
    property bool buildWarned: false
    property string updateError: ""    // E-Zeilen (git/cargo)
    property int updatePulled: 0       // Commits beim letzten Lauf
    property double updateStart: 0     // ms seit Epoche
    property bool launching: false     // Skript gestartet, Log noch leer
    readonly property bool updating: root.launching || (root.updateStep !== "" && !root.updateDone && !root.updateFailed)
    // Eigene Aenderungen sperren den Knopf nicht: ob sie dem Pull im Weg
    // stehen, weiss nur git – dessen Fehlertext zeigt die Karte dann
    readonly property bool canUpdate: root.behind > 0 && !root.updating && !root.checking

    readonly property int checkHours: Config.system.updateCheckHours

    // ---- Stand lesen, mit oder ohne fetch ----
    property bool queuedFetch: false
    property bool queued: false

    function refresh(): void {
        root.run(false);
    }

    // Pruefen, wenn der Cache abgelaufen ist (oder `force`)
    function check(force: bool): void {
        if (!force && root.lastCheck > 0 && Date.now() - root.lastCheck < root.cacheMs)
            return;
        root.run(true);
    }

    function run(fetch: bool): void {
        if (gitProc.running) {
            root.queued = true;
            root.queuedFetch = root.queuedFetch || fetch;
            return;
        }
        if (fetch)
            root.checkState = "checking";
        gitProc.fetch = fetch;
        gitProc.running = true;
    }

    // ---- Aktualisieren: Skript abgekoppelt, siehe oben ----
    function update(): void {
        if (root.updating || root.repo === "")
            return;
        root.resetUpdate();
        root.launching = true;
        root.updateStart = Date.now();
        // Skript erst komplett lesen, dann ausfuehren: der Pull ueberschreibt
        // es womoeglich, waehrend sh noch darin liest
        Quickshell.execDetached(["sh", "-c",
            's=$(cat "$1") || exit 1; exec sh -c "$s" shellupdate "$2" "$3"',
            "sh", root.script, root.repo, root.logPath]);
    }

    // Nur neu starten, ohne Pull – genau wie die CLI
    function restart(): void {
        Quickshell.execDetached(["sh", "-c",
            'c="$1"; [ -x "$c" ] || c=dynamic-island; sleep 1; "$c" shell -k >/dev/null 2>&1; sleep 1.5; exec "$c" shell -d',
            "sh", root.cli]);
    }

    function resetUpdate(): void {
        root.updateStep = "";
        root.updateDone = false;
        root.updateFailed = false;
        root.buildWarned = false;
        root.updateError = "";
        root.updatePulled = 0;
    }

    onWatchingChanged: {
        if (!root.watching)
            return;
        if (root.lastCheck > 0 && Date.now() - root.lastCheck < root.cacheMs)
            root.refresh();
        else
            root.check(false);
    }

    // ---- git: Stand (und Pruefung) in einem Aufruf ----
    Process {
        id: gitProc

        property bool fetch: false

        command: ["sh", "-c",
            'export GIT_TERMINAL_PROMPT=0;'
            + ' d=$(dirname "$(readlink -f "$1")"); r=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || r="$2";'
            + ' cd "$r" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "norepo $r"; exit 0; };'
            + ' echo "repo $r";'
            + ' if [ "$3" = 1 ]; then out=$(timeout 60 git fetch --quiet 2>&1) || echo "fetcherr ${out:-git fetch fehlgeschlagen}"; echo "fetched"; fi;'
            + ' echo "branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null)";'
            + ' echo "commit $(git rev-parse --short HEAD 2>/dev/null)";'
            + ' echo "date $(git log -1 --format=%cs 2>/dev/null)";'
            + ' echo "age $(git log -1 --format=%cr 2>/dev/null)";'
            + ' echo "describe $(git describe --tags --always 2>/dev/null)";'
            + ' up=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null); echo "upstream $up";'
            + ' if [ -n "$up" ]; then echo "behind $(git rev-list --count HEAD..@{u} 2>/dev/null)"; echo "ahead $(git rev-list --count @{u}..HEAD 2>/dev/null)";'
            + '   git log --format="in %h%x09%s%x09%cr" HEAD..@{u} 2>/dev/null; fi;'
            + ' git status --porcelain 2>/dev/null | sed "s/^/st /"',
            "sh", root.shellFile, root.fallbackRepo, gitProc.fetch ? "1" : "0"]

        stdout: StdioCollector {
            onStreamFinished: {
                const changes = [];
                const incoming = [];
                let fetched = false;
                let fetchError = "";
                let repo = "";
                let behind = 0;
                let ahead = 0;
                let upstream = "";

                for (const raw of text.split("\n")) {
                    const line = raw.replace(/\r$/, "");
                    const i = line.indexOf(" ");
                    const key = i < 0 ? line : line.slice(0, i);
                    const val = i < 0 ? "" : line.slice(i + 1);
                    switch (key) {
                    case "norepo":
                        root.repo = "";
                        root.loaded = true;
                        root.checkState = "error";
                        root.checkError = I18n.tr("Kein Git-Repo gefunden: %1").arg(val.trim());
                        root.lastCheck = Date.now();
                        return;
                    case "repo": repo = val.trim(); break;
                    case "fetched": fetched = true; break;
                    case "fetcherr": fetchError = val.trim().split("\n")[0]; break;
                    case "branch": root.branch = val.trim(); break;
                    case "commit": root.commit = val.trim(); break;
                    case "date": root.commitDate = val.trim(); break;
                    case "age": root.commitAge = val.trim(); break;
                    case "describe": root.describe = val.trim(); break;
                    case "upstream": upstream = val.trim(); break;
                    case "behind": behind = Number(val.trim()) || 0; break;
                    case "ahead": ahead = Number(val.trim()) || 0; break;
                    case "in": {
                        const f = val.split("\t");
                        if (f[0] !== "")
                            incoming.push({ hash: f[0], subject: f[1] ?? "", when: f[2] ?? "" });
                        break;
                    }
                    case "st":
                        // "XY pfad" – zwei Statusspalten, dann Leerzeichen
                        if (val.length > 3)
                            changes.push({ status: val.slice(0, 2).trim(), file: val.slice(3).trim() });
                        break;
                    }
                }

                root.repo = repo;
                root.upstream = upstream;
                root.localChanges = changes;
                root.behind = behind;
                root.ahead = ahead;
                root.incoming = incoming;
                root.loaded = true;

                if (fetched) {
                    root.lastCheck = Date.now();
                    if (fetchError !== "") {
                        root.checkState = "error";
                        root.checkError = fetchError;
                    } else if (upstream === "") {
                        root.checkState = "error";
                        root.checkError = I18n.tr("Kein Upstream für Branch %1").arg(root.branch);
                    } else {
                        root.checkState = "ok";
                        root.checkError = "";
                    }
                }
            }
        }

        onExited: (code, status) => {
            // Skript selbst gescheitert: nicht ewig "Prüfe…"
            if (root.checkState === "checking") {
                root.checkState = "error";
                root.checkError = I18n.tr("Prüfung fehlgeschlagen");
                root.lastCheck = Date.now();
            }
            if (root.queued) {
                root.queued = false;
                const fetch = root.queuedFetch;
                root.queuedFetch = false;
                root.run(fetch);
            }
        }
    }

    // ---- Protokoll des Update-Skripts ----
    FileView {
        id: logFile

        path: root.logPath
        watchChanges: true
        printErrors: false
        onLoaded: root.readLog(text())
        onFileChanged: reload()
    }

    // Solange das Skript laeuft, zur Sicherheit auch ohne Dateiereignis
    // nachlesen (die Datei entsteht erst mit dem Start)
    Timer {
        interval: 500
        repeat: true
        running: root.updating
        onTriggered: logFile.reload()
    }

    // Kommt nach dem Start nichts im Protokoll an, ist das Skript nie
    // angelaufen (Datei fehlt, sh nicht da) – nicht ewig "Lade…" zeigen
    Timer {
        interval: 20 * 1000
        running: root.launching
        onTriggered: {
            if (!root.launching)
                return;
            root.launching = false;
            root.updateFailed = true;
            root.updateError = I18n.tr("Update-Skript nicht gestartet: %1").arg(root.script);
        }
    }

    function readLog(text: string): void {
        let step = "";
        let done = false;
        let failed = false;
        let warned = false;
        let pulled = 0;
        let start = 0;
        const errors = [];

        for (const raw of text.split("\n")) {
            const line = raw.replace(/\r$/, "");
            const i = line.indexOf(" ");
            const key = i < 0 ? line : line.slice(0, i);
            const val = i < 0 ? "" : line.slice(i + 1);
            switch (key) {
            case "START": start = (Number(val) || 0) * 1000; break;
            case "STEP": step = val.trim(); errors.length = 0; break;
            case "E": errors.push(val); break;
            case "WARN": warned = true; break;
            case "FAIL": failed = true; break;
            case "PULLED": pulled = Number(val.split(" ")[2]) || 0; break;
            case "DONE": done = true; break;
            }
        }

        if (start === 0)
            return;
        const age = Date.now() - start;
        // Ein alter Lauf interessiert nicht mehr; ein Lauf ohne Abschluss
        // ist nach einer Viertelstunde abgebrochen
        if (age > 60 * 60 * 1000) {
            root.resetUpdate();
            return;
        }
        if (!done && !failed && age > 15 * 60 * 1000) {
            failed = true;
            errors.push(I18n.tr("Kein Abschluss im Protokoll: %1").arg(root.logPath));
        }

        root.launching = false;
        root.updateStart = start;
        root.updateStep = step;
        root.updateDone = done;
        root.updateFailed = failed;
        root.buildWarned = warned;
        root.updateError = errors.join("\n").trim();
        root.updatePulled = pulled;
    }

    // ---- Hintergrund ----
    // Erste Pruefung kurz nach dem Start (nicht sofort: beim Hot-Reload
    // entsteht der Singleton jedes Mal neu), danach im eingestellten Takt.
    // 0 Stunden = nur bei offener Ansicht.
    Timer {
        interval: 90 * 1000
        running: root.checkHours > 0 && root.lastCheck === 0
        onTriggered: root.check(false)
    }

    Timer {
        interval: Math.max(1, root.checkHours) * 3600 * 1000
        running: root.checkHours > 0
        repeat: true
        onTriggered: root.check(false)
    }
}
