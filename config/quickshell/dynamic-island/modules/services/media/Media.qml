pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris

import qs.modules.services.core

// Medien-Service: eine einzige Quelle fuer alles, was die Leiste ueber die
// laufende Wiedergabe wissen muss.
//
// Darunter liegt MPRIS – der D-Bus-Standard, den Spotify, Zen/Firefox, mpv,
// VLC & Co. sprechen. Quickshell bringt das fertig mit: `Mpris.players` ist
// die Liste aller Programme, die gerade etwas abspielen koennen.
//
// Der Service legt drei Dinge obendrauf:
//   1. Er waehlt einen "aktiven" Player (siehe `active`), damit die UI nicht
//      selbst entscheiden muss, wen ein Klick steuert.
//   2. Er reicht Titel/Interpret/Cover als flache Properties durch, mit
//      Leerstring statt null – das spart in jedem Label eine ?.-Kette.
//   3. Er kapselt die Steuerung so, dass ein Knopfdruck nichts kaputt macht,
//      wenn der Player die Aktion gar nicht kann (canGoNext & Co.).
//
// Benutzung:  import qs.modules.services.media   ->   Media.title, Media.next(), ...
Singleton {
    id: root

    // ---- Quellen ----------------------------------------------------------

    // Alle verfuegbaren Player. Direkt als Model fuer den Selektor benutzbar:
    //   Repeater { model: Media.players; delegate: ... }
    readonly property list<MprisPlayer> players: Mpris.players.values
    readonly property int count: root.players.length

    // Vom Selektor gesetzt (`Media.select(player)`). Bewusst NICHT `active`
    // direkt: verschwindet der gewaehlte Player, greift wieder die Automatik,
    // statt dass die Leiste auf eine Leiche zeigt.
    property MprisPlayer preferred: null

    // Wer gesteuert wird: die manuelle Wahl, sonst wer gerade spielt, sonst
    // der erste ueberhaupt.
    readonly property MprisPlayer active: {
        const list = root.players;
        if (root.preferred && list.includes(root.preferred))
            return root.preferred;
        return list.find(p => p.isPlaying) ?? list[0] ?? null;
    }

    // Laeuft die Auswahl gerade von Hand oder automatisch?
    readonly property bool manual: !!root.preferred && root.players.includes(root.preferred)
    // Gibt es ueberhaupt etwas zu zeigen? -> `visible: Media.available`
    readonly property bool available: !!root.active

    // ---- Anzeige ----------------------------------------------------------

    readonly property string title: root.active?.trackTitle ?? ""
    readonly property string artist: root.active?.trackArtist ?? ""
    readonly property string album: root.active?.trackAlbum ?? ""
    // Name des Programms, z.B. "Spotify" – fuer den Selektor und als Untertitel
    readonly property string source: root.identityOf(root.active)
    readonly property bool playing: root.active?.isPlaying ?? false

    // "Interpret – Titel", bzw. nur das, was da ist. Fuer ein einzeiliges Label.
    readonly property string label: root.artist && root.title ? `${root.artist} – ${root.title}`
                                  : root.title || root.artist

    // Rohe Cover-Adresse aus MPRIS – je nach Player `file://` oder `https://`.
    readonly property string artUrl: root.artOf(root.active)

    // Das hier gehoert an ein `Image { source: Media.art }`.
    //
    // Warum nicht direkt `artUrl`: Qts Netzwerk-Stack scheitert an Spotifys CDN
    // mit "HTTP/2 protocol error", das Bild bleibt leer obwohl die Adresse
    // stimmt (curl holt dieselbe URL anstandslos). Darum wird alles, was nicht
    // schon lokal liegt, einmal per curl in den Cache geholt und von dort
    // angezeigt. Nebenbei laedt so jedes Cover nur ein einziges Mal.
    readonly property string art: root.artUrl.startsWith("file://") ? root.artUrl : root.artCached

    readonly property string artDir: Quickshell.env("HOME") + "/.cache/dynamic-island/art/"
    property string artCached: ""

    // Dominante Farbe des Covers, damit sich die Karte danach faerben kann.
    // `transparent` heisst "keine bekannt" – dann bleibt es beim Theme-Grund.
    property color artColor: "transparent"

    onArtUrlChanged: root.fetchArt()

    function fetchArt(): void {
        root.artCached = "";

        const url = root.artUrl;
        if (!url || url.startsWith("file://"))
            return;

        // Dateiname aus der Adresse: derselbe Track holt sich das Bild nicht
        // zweimal, und der Name bleibt ueber Neustarts stabil.
        const file = root.artDir + url.replace(/^https?:\/\//, "").replace(/[^A-Za-z0-9]/g, "_");

        artFetch.running = false;
        artFetch.file = file;
        artFetch.environment = ({
            ART_URL: url,
            ART_FILE: file
        });
        artFetch.running = true;
    }

    // Die Farbe kommt von ImageMagick: Bild auf einen einzigen Pixel
    // eindampfen, das ist der Mittelwert. Ein Aufruf pro Cover, kein Polling.
    onArtChanged: root.probeArtColor()

    function probeArtColor(): void {
        const url = root.art;
        if (!url.startsWith("file://")) {
            root.artColor = "transparent";
            return;
        }

        artColour.running = false;
        artColour.environment = ({
            ART_FILE: decodeURIComponent(url.substring(7))
        });
        artColour.running = true;
    }

    Process {
        id: artColour

        command: ["sh", "-c", 'magick "$ART_FILE" -resize 1x1! -depth 8 -format "%[hex:p{0,0}]" info:']

        stdout: StdioCollector {
            id: colourOut

            onStreamFinished: {
                const hex = colourOut.text.trim().slice(0, 6);
                if (/^[0-9A-Fa-f]{6}$/.test(hex))
                    root.artColor = "#" + hex;
            }
        }
    }

    Process {
        id: artFetch

        property string file: ""

        // `test -s` zuerst: was schon im Cache liegt, wird nicht neu geladen.
        command: ["sh", "-c", 'test -s "$ART_FILE" || curl -sfL --max-time 10 --create-dirs -o "$ART_FILE" "$ART_URL"']

        onExited: code => {
            if (code === 0)
                root.artCached = "file://" + artFetch.file;
            else
                console.warn("Media: Cover nicht ladbar (curl", code + "):", root.artUrl);
        }
    }

    // ---- Was kann der aktive Player? --------------------------------------
    // Fuer `enabled:`/`opacity:` an den Knoepfen, damit nichts Totes klickbar ist.

    readonly property bool canPlay: root.active?.canPlay ?? false
    readonly property bool canPause: root.active?.canPause ?? false
    readonly property bool canToggle: root.active?.canTogglePlaying ?? false
    readonly property bool canNext: root.active?.canGoNext ?? false
    readonly property bool canPrevious: root.active?.canGoPrevious ?? false
    readonly property bool canSeek: root.active?.canSeek ?? false

    // ---- Fortschritt (optional, kostet Polling) ---------------------------
    //
    // MPRIS schickt die Position nicht von sich aus – sie muss abgefragt
    // werden. Das laeuft deshalb nur, wenn es jemand einschaltet:
    //   DemandRequest { demand: Media.positionDemand; active: shown }
    // und auch dann nur, solange wirklich abgespielt wird.
    readonly property Demand positionDemand: Demand {}
    readonly property bool trackPosition: root.positionDemand.active

    readonly property real position: root.active?.position ?? 0
    readonly property real length: root.active?.length ?? 0

    // Achtung: nicht jeder Player meldet eine Laenge (Firefox/Zen tut es bei
    // YouTube nicht). Quickshell gibt dann die *Position* als Laenge zurueck –
    // ohne diese Pruefung stuenden beide Zeiten identisch da und jeder
    // Fortschrittsbalken waere permanent voll.
    readonly property bool hasLength: (root.active?.lengthSupported ?? false) && root.length > 0

    // 0..1 – ohne bekannte Laenge gibt es keinen sinnvollen Fortschritt
    readonly property real progress: root.hasLength ? Math.min(1, root.position / root.length) : 0

    Timer {
        running: root.trackPosition && root.playing && (root.active?.positionSupported ?? false)
        repeat: true
        interval: 1000
        // Kein Setter: das Signal ist der Anstoss zum Neulesen.
        onTriggered: root.active?.positionChanged()
    }

    // "04:20" bzw. "1:02:03". Minuten immer zweistellig, damit die Anzeige in
    // der Leiste nicht bei jedem Minutenwechsel die Breite aendert.
    function formatTime(seconds: real): string {
        if (!(seconds > 0))
            return "00:00";

        const total = Math.floor(seconds);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60).toString().padStart(2, "0");
        const s = (total % 60).toString().padStart(2, "0");
        return h > 0 ? `${h}:${m}:${s}` : `${m}:${s}`;
    }

    // "01:23/04:56", oder nur "01:23", wenn der Player keine Laenge meldet.
    // Braucht `trackPosition`, sonst bleibt die linke Zahl stehen.
    readonly property string timeLabel: root.hasLength
        ? `${root.formatTime(root.position)}/${root.formatTime(root.length)}`
        : root.formatTime(root.position)

    // ---- Steuerung --------------------------------------------------------
    // Alle Aktionen pruefen vorher, ob der Player sie kann. Ein Klick auf
    // einen Knopf, den der Player nicht unterstuetzt, tut dann einfach nichts,
    // statt eine D-Bus-Fehlermeldung zu werfen.

    function playPause(): void {
        const p = root.active;
        if (p?.canTogglePlaying)
            p.togglePlaying();
    }

    function play(): void {
        const p = root.active;
        if (p?.canPlay)
            p.play();
    }

    function pause(): void {
        const p = root.active;
        if (p?.canPause)
            p.pause();
    }

    function stop(): void {
        root.active?.stop();
    }

    function next(): void {
        const p = root.active;
        if (p?.canGoNext)
            p.next();
    }

    function previous(): void {
        const p = root.active;
        if (p?.canGoPrevious)
            p.previous();
    }

    // Sprung an eine Stelle, 0..1 (also `Media.seek(0.5)` = Mitte)
    function seek(fraction: real): void {
        const p = root.active;
        if (p?.canSeek && p.length > 0)
            p.position = Math.max(0, Math.min(1, fraction)) * p.length;
    }

    // ---- Medientasten -----------------------------------------------------
    //
    // Die Tasten steuern denselben Player, den auch die Leiste zeigt – also
    // die im Selektor gewaehlte Quelle. `playerctl` koennte das nicht: das
    // sucht sich selbst einen Player und weiss nichts von der Auswahl hier.
    //
    // Hyprland loest die Shortcuts per `global`-Dispatcher aus, siehe
    // ~/.config/hypr/profiles/simple.lua:
    //   hl.bind("XF86AudioPlay", hl.dsp.global("dynamic-island:mediaToggle"))

    GlobalShortcut {
        appid: "dynamic-island"
        name: "mediaToggle"
        description: "Play/Pause der gewaehlten Quelle"

        onPressed: root.playPause()
    }

    GlobalShortcut {
        appid: "dynamic-island"
        name: "mediaNext"
        description: "Naechster Titel der gewaehlten Quelle"

        onPressed: root.next()
    }

    GlobalShortcut {
        appid: "dynamic-island"
        name: "mediaPrev"
        description: "Vorheriger Titel der gewaehlten Quelle"

        onPressed: root.previous()
    }

    GlobalShortcut {
        appid: "dynamic-island"
        name: "mediaStop"
        description: "Wiedergabe der gewaehlten Quelle stoppen"

        onPressed: root.stop()
    }

    // ---- Selektor ---------------------------------------------------------

    // Einen Player fest ansteuern. `null` gibt die Auswahl wieder frei.
    function select(player: MprisPlayer): void {
        root.preferred = player ?? null;
    }

    // Zurueck auf Automatik (wer spielt, wird gesteuert)
    function clearSelection(): void {
        root.preferred = null;
    }

    // Reihum durchschalten – fuer ein Mausrad auf der Medien-Pille
    function cycle(step: int): void {
        const list = root.players;
        if (list.length < 2)
            return;

        const current = list.indexOf(root.active);
        const base = current < 0 ? 0 : current;
        root.preferred = list[(base + (step || 1) + list.length * 2) % list.length];
    }

    // Anzeigename eines Players. `identity` ist der huebsche Name aus MPRIS
    // ("Spotify", "Zen Browser"); faellt er aus, bleibt der D-Bus-Name.
    function identityOf(player: MprisPlayer): string {
        if (!player)
            return "";
        return player.identity || player.dbusName || "";
    }

    // Cover eines beliebigen Players (nicht nur des aktiven) – der Selektor
    // kann damit Mini-Cover neben die Namen setzen.
    function artOf(player: MprisPlayer): string {
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;

        // YouTube liefert kein Cover ueber MPRIS, aber das Thumbnail laesst
        // sich aus der Video-ID bauen.
        const url = player.metadata["xesam:url"] ?? "";
        const id = url.startsWith("https://www.youtube.com/watch") ? url.match(/[?&]v=([\w-]{11})/)?.[1] : "";
        return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
    }
}
