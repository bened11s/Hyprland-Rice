pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Konto des angemeldeten Users (Einstellungen > Konto, AccountEditor.qml):
// Login, Anzeigename, Profilbild (~/.face, das der Sperrbildschirm zeigt)
// und Passwort. Schreiben macht usermgr.py ueber AccountsService; das
// Passwort fragt polkit ab (Dialog der Shell).
//
// Benutzung:  import qs.modules.services.user  ->  User.name, User.setName("…")
Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("modules/services/user/usermgr.py")

    property string user: Quickshell.env("USER") ?? ""
    property string name: ""
    property string face: ""
    // Neu laden erzwingen, wenn ~/.face ersetzt wurde (gleicher Pfad)
    property int faceVersion: 0
    readonly property url faceUrl: root.face !== "" ? `file://${root.face}?v=${root.faceVersion}` : ""

    // Laufende Aktion ("face", "name", "password") und ihr Ergebnis
    property string busy: ""
    property string lastError: ""
    // Zuletzt erfolgreich: fuer kurze Rueckmeldungen in der Seite
    property string lastDone: ""

    function refresh(): void {
        root.run(["info"]);
    }

    function pickFace(): void {
        if (root.busy !== "")
            return;
        root.lastError = "";
        root.busy = "face";
        pickProc.running = true;
    }

    function setName(name: string): void {
        if (root.busy !== "" || name.trim() === "" || name.trim() === root.name)
            return;
        root.lastError = "";
        root.busy = "name";
        root.run(["name", name.trim()]);
    }

    function setPassword(password: string): void {
        if (root.busy !== "" || password === "")
            return;
        root.lastError = "";
        root.busy = "password";
        pwProc.secret = password;
        pwProc.running = true;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            return { ok: false, error: text.trim() || "usermgr.py" };
        }
    }

    function run(args: var): void {
        mgrProc.args = args;
        mgrProc.command = ["python3", "-I", root.helper].concat(args);
        mgrProc.running = true;
    }

    function finish(op: string, r: var): void {
        if (!r.ok) {
            root.lastError = r.error ?? "";
        } else if (op === "info") {
            root.user = r.user ?? root.user;
            root.name = r.name ?? "";
            root.face = r.face ?? "";
        } else if (op === "face") {
            root.face = r.face ?? root.face;
            root.faceVersion++;
        } else if (op === "name") {
            root.name = r.name ?? root.name;
        }
        if (r.ok && op !== "info")
            root.lastDone = op;
        if (op !== "info")
            root.busy = "";
    }

    Component.onCompleted: root.refresh()

    Process {
        id: mgrProc

        property var args: []

        stdout: StdioCollector { id: mgrOut }
        onExited: root.finish(mgrProc.args[0], root.parse(mgrOut.text))
    }

    Process {
        id: pickProc

        command: ["python3", "-I", root.helper, "pick"]
        stdout: StdioCollector { id: pickOut }
        onExited: {
            const r = root.parse(pickOut.text);
            if (r.ok && r.path) {
                root.run(["face", r.path]);
            } else {
                root.lastError = r.ok ? "" : (r.error ?? "");
                root.busy = "";
            }
        }
    }

    // Passwort ueber stdin, nie in der Kommandozeile
    Process {
        id: pwProc

        property string secret: ""

        command: ["python3", "-I", root.helper, "password"]
        stdinEnabled: true
        stdout: StdioCollector { id: pwOut }
        onStarted: {
            pwProc.write(pwProc.secret + "\n");
            pwProc.secret = "";
        }
        onExited: root.finish("password", root.parse(pwOut.text))
    }
}
