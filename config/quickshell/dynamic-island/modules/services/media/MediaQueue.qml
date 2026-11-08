pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtWebSockets
import Quickshell
import Quickshell.Io

// Spotify-Queue: vorherige und naechste Titel rund um den laufenden.
//
// MPRIS kennt keine Queue. Die liefert die Spicetify-Extension
// ~/.config/spicetify/Extensions/islandQueue.js: sie verbindet sich als
// WebSocket-Client mit diesem Server und schickt bei jeder Aenderung
//   {"type":"queue","current":{…},"prev":[…],"next":[…]}
// (je Titel uri/uid/title/artist/album/art/queued, prev[0] = direkter
// Vorgaenger, next bis zu 30 Titel). Der Server lauscht nur auf 127.0.0.1.
//
// Zurueck an die Extension gehen Befehle (`command`):
//   {"cmd":"refresh"}                    alles neu schicken
//   {"cmd":"skip","uri","uid","index"}   zu next[index] springen
//   {"cmd":"lyrics"}                     Songtext des laufenden Titels
// Die Antwort auf "lyrics" ist {"type":"lyrics","uri","title","synced",
// "lines":[{"t":ms,"text"}]} und landet in `lyrics` (Lyrics.qml liest sie).
//
// Andere lokale Clients duerfen die Extension mitsteuern: Nachrichten mit
// "cmd" reicht der Server an alle anderen Clients weiter, Antworten der
// Extension mit eigenem "type" (alles ausser queue/lyrics) ebenso, z. B.
//   {"cmd":"play","query":"…","kind":"track|artist|album|playlist"}
//   -> {"type":"play_result","ok",…}
//
// Benutzung:  MediaQueue.previous?.title, MediaQueue.upcoming?.art, MediaQueue.next
Singleton {
    id: root

    readonly property int port: 28199

    // Letzte Nachricht der Extension, ungefiltert
    property var current: null
    property var rawPrev: []
    property var rawNext: []
    property bool connected: false

    // Nur zeigen, wenn die Queue zum laufenden Titel passt: ein anderer
    // Player kann aktiv sein, oder die Nachricht hinkt einen Wechsel hinterher.
    readonly property bool valid: root.connected && !!root.current
                                  && Media.source === "Spotify"
                                  && root.current.title === Media.title

    // Ausgabe fuer die UI, Cover schon als file:// (siehe fetchArt)
    readonly property var prev: root.valid ? root.rawPrev.map(root.withArt) : []
    readonly property var next: root.valid ? root.rawNext.map(root.withArt) : []
    readonly property var previous: root.prev[0] ?? null
    readonly property var upcoming: root.next[0] ?? null

    // Letzte Songtext-Antwort der Extension (siehe oben), null = keine
    property var lyrics: null

    // Cover werden nur fuer den sichtbaren Anfang der Liste geholt – die
    // aufgeklappte Warteschlange zeigt die ersten paar, der Rest bekommt
    // sein Bild, sobald er nachrueckt
    readonly property int artAhead: 12

    function command(msg: var): void {
        const text = JSON.stringify(msg);
        for (const socket of root.sockets)
            if (socket.status === WebSocket.Open)
                socket.sendTextMessage(text);
    }

    // Zu einem Titel der naechsten-Liste springen. Die Extension nimmt
    // Spotifys eigenes skipTo, sonst entsprechend oft "weiter".
    function skipTo(index: int): void {
        const t = root.rawNext[index];
        if (!t)
            return;
        if (index === 0 || root.clients === 0) {
            Media.next();
            return;
        }
        root.command({ cmd: "skip", uri: t.uri, uid: t.uid ?? "", index: index });
    }

    function requestLyrics(): void {
        root.command({ cmd: "lyrics" });
    }

    // ---- Cover-Cache ----------------------------------------------------
    // Gleicher Cache und gleiches Dateinamen-Schema wie Media.art (Qt laedt
    // Spotifys CDN nicht, curl schon). `cached` wird neu zugewiesen, damit
    // die Bindungen von prev/next neu rechnen.
    property var cached: ({})

    function fileFor(url: string): string {
        return Media.artDir + url.replace(/^https?:\/\//, "").replace(/[^A-Za-z0-9]/g, "_");
    }

    function withArt(t: var): var {
        const art = t.art && root.cached[t.art] ? "file://" + root.fileFor(t.art) : "";
        return Object.assign({}, t, { art: art });
    }

    function fetchArt(): void {
        const missing = [...root.rawPrev.slice(0, 3), ...root.rawNext.slice(0, root.artAhead)]
            .map(t => t.art)
            .filter((url, i, all) => url && !root.cached[url] && all.indexOf(url) === i);
        if (!missing.length)
            return;
        if (artFetch.running) {
            artFetch.pending = true;
            return;
        }
        artFetch.urls = missing;
        artFetch.environment = ({
            ART_LIST: missing.map(u => u + "\t" + root.fileFor(u)).join("\n")
        });
        artFetch.running = true;
    }

    Process {
        id: artFetch

        property var urls: []
        property bool pending: false

        // Laedt nur, was fehlt; meldet jede vorhandene Datei per URL zurueck
        command: ["sh", "-c", `printf '%s\\n' "$ART_LIST" | while IFS="$(printf '\\t')" read -r url file; do
            test -s "$file" || curl -sfL --max-time 10 --create-dirs -o "$file" "$url"
            test -s "$file" && printf '%s\\n' "$url"
        done`]

        stdout: StdioCollector {
            id: fetched

            onStreamFinished: {
                const next = Object.assign({}, root.cached);
                for (const url of fetched.text.split("\n"))
                    if (url)
                        next[url] = true;
                root.cached = next;
            }
        }

        onExited: {
            if (artFetch.pending) {
                artFetch.pending = false;
                Qt.callLater(root.fetchArt);
            }
        }
    }

    // ---- Server ---------------------------------------------------------

    // Fremde Befehle/Antworten zwischen den Clients durchreichen (siehe oben)
    function relay(from: var, text: string): void {
        let msg;
        try {
            msg = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!msg?.cmd && (!msg?.type || msg.type === "queue" || msg.type === "lyrics"))
            return;
        for (const socket of root.sockets)
            if (socket !== from && socket.status === WebSocket.Open)
                socket.sendTextMessage(text);
    }

    function receive(text: string): void {
        let msg;
        try {
            msg = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (msg?.type === "lyrics") {
            root.lyrics = msg;
            return;
        }
        if (msg?.type !== "queue")
            return;
        root.current = msg.current ?? null;
        root.rawPrev = Array.isArray(msg.prev) ? msg.prev : [];
        root.rawNext = Array.isArray(msg.next) ? msg.next : [];
        root.fetchArt();
    }

    // Spotify-Neustart = neue Verbindung; die alte schliesst sich von selbst
    property int clients: 0
    onClientsChanged: {
        root.connected = root.clients > 0;
        if (root.clients > 0)
            root.bindFailed = false;
    }

    // Beim Hot-Reload entsteht der neue Server, bevor die alte Generation den
    // Port freigibt -> "Adresse bereits in Gebrauch". errorString wird bei
    // Erfolg nie geleert, darum gilt erst ein verbundener Client als Beweis.
    // Bis dahin alle 2 s neu binden; ohne Client trennt das niemanden.
    property bool bindFailed: false

    // Angenommene Sockets ueberleben sonst den Abbau einer Reload-Generation:
    // die Extension bliebe mit dem toten Singleton verbunden und die neue
    // Generation bekaeme nie Daten. Also beim Abbau alles schliessen.
    property var sockets: []

    Component.onDestruction: {
        server.listen = false;
        for (const socket of root.sockets)
            socket.active = false;
    }

    Timer {
        running: root.bindFailed && root.clients === 0
        interval: 2000
        repeat: true
        onTriggered: {
            server.listen = false;
            server.listen = true;
        }
    }

    WebSocketServer {
        id: server

        listen: true
        host: "127.0.0.1"
        port: root.port
        accept: true

        onErrorStringChanged: {
            if (!server.errorString)
                return;
            console.warn("MediaQueue:", server.errorString);
            root.bindFailed = true;
        }

        onClientConnected: socket => {
            root.sockets.push(socket);
            root.clients++;
            let gone = false; // Error und Closed koennen beide kommen
            socket.textMessageReceived.connect(root.receive);
            socket.textMessageReceived.connect(text => root.relay(socket, text));
            socket.statusChanged.connect(() => {
                if (gone || (socket.status !== WebSocket.Closed && socket.status !== WebSocket.Error))
                    return;
                gone = true;
                root.clients--;
                root.sockets = root.sockets.filter(s => s !== socket);
            });
        }
    }
}
