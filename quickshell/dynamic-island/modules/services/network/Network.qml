pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// WLAN-Dienst auf nmcli-Basis: sichtbare Netze, gespeicherte Profile,
// Verbinden/Trennen/Vergessen.
//
// Zwei Dinge macht er bewusst anders als der Caelestia-Wechsler, an dem die
// doppelten Netze entstanden:
//
//  1. Ein Netz erscheint EINMAL. Ein Accesspoint pro Band/Repeater bringt
//     denselben SSID mehrfach in die Scan-Liste (hier z.B. "Gastwlan" mit 79%
//     und 42%) – zusammengefasst wird auf den staerksten.
//  2. Verbunden wird ueber das gespeicherte Profil (`connection up uuid`),
//     nicht ueber `device wifi connect <ssid>`. Letzteres legt ein NEUES
//     Profil an, wenn es das vorhandene nicht wiederverwenden kann – so
//     entsteht "WLAN2 1" neben "WLAN2", ohne brauchbares Passwort, und der
//     NetworkManager nimmt beim naechsten Mal das falsche.
//
// Profile, die nie zu einer Verbindung gefuehrt haben (`timestamp 0`), sind
// genau dieser Muell; die Oberflaeche zeigt sie an und raeumt sie nach einem
// gescheiterten Versuch selbst weg.
//
// Benutzung:  import qs.modules.services.network
Singleton {
    id: root

    // [{ ssid, signal, security, secured, active, inRange,
    //    profiles: [{ uuid, name, timestamp }], saved, duplicate, stale }]
    property var networks: []
    // Kabelanschluesse: [{ device, state, connection, ip,
    //                      connected, connecting, available }]
    property var wired: []
    property bool radioOn: true
    property bool loaded: false

    // Laeuft gerade ein nmcli-Kommando, und was hat es zuletzt gemeldet
    property bool busy: false
    property string status: ""

    // Die Oberflaeche schaltet das ein, solange sie offen ist – nur dann wird
    // regelmaessig nachgesehen.
    // (per DemandRequest – WifiPanel gibt es je Monitor und Einbauort)
    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active

    readonly property var activeNetwork: root.networks.find(n => n.active) ?? null

    // ---- Auftragsliste ----
    // nmcli-Aufrufe laufen nacheinander. Eigene Liste statt `sh -c "a && b"`,
    // damit Passwoerter nicht durch eine Shell-Zeile muessen (Anfuehrungs-
    // zeichen, $, ` ...).
    property var queue: []

    function run(cmd: var, note: string): void {
        root.queue = root.queue.concat([{ cmd, note }]);
        root.pump();
    }

    function pump(): void {
        if (root.busy || root.queue.length === 0)
            return;

        const job = root.queue[0];
        root.queue = root.queue.slice(1);
        root.status = job.note;
        root.busy = true;
        action.command = job.cmd;
        action.running = true;
    }

    // Laeuft gerade eine Funk-Suche nach neuen Netzen
    readonly property bool scanning: rescanProc.running || rescanFollowUp.running

    // ---- Abfragen ----
    // Zweistufig: `--rescan yes` blockiert ~6 s, bevor nmcli ueberhaupt etwas
    // liefert. Deshalb zuerst SOFORT die zwischengespeicherte Liste (~60 ms),
    // und die Suche nach neuen Netzen laeuft daneben (`nmcli device wifi
    // rescan` kehrt gleich zurueck, der NetworkManager sucht weiter). Danach
    // wird zweimal nachgelesen – neue Netze tauchen nach und nach auf.
    function refresh(rescan: bool): void {
        scan.rescan = "no";
        if (scan.running)
            scan.pending = true;
        else
            scan.running = true;

        if (rescan && !rescanProc.running) {
            rescanFollowUp.round = 0;
            rescanProc.running = true;
        }
    }

    // ---- Aktionen ----
    function setRadio(on: bool): void {
        root.run(["nmcli", "radio", "wifi", on ? "on" : "off"],
                 on ? "WLAN wird eingeschaltet…" : "WLAN wird ausgeschaltet…");
    }

    // Verbinden. Gibt es ein Profil, wird DAS genommen – auch wenn ein
    // Passwort mitkommt (dann vorher gesetzt). Nur fuer ein voellig
    // unbekanntes Netz darf nmcli selbst ein Profil anlegen.
    function connect(net: var, password: string): void {
        if (!net)
            return;

        const profile = root.bestProfile(net);

        if (profile && password) {
            root.run(["nmcli", "connection", "modify", "uuid", profile.uuid,
                      "802-11-wireless-security.psk", password], `Passwort für ${net.ssid} wird gesetzt…`);
            root.run(["nmcli", "connection", "up", "uuid", profile.uuid], `Verbinde mit ${net.ssid}…`);
        } else if (profile) {
            root.run(["nmcli", "connection", "up", "uuid", profile.uuid], `Verbinde mit ${net.ssid}…`);
        } else if (password) {
            // Neues Netz: nmcli legt das Profil an. Scheitert es, raeumen wir
            // den dabei entstandenen Rest gleich wieder weg (siehe cleanupSsid).
            scan.cleanupSsid = net.ssid;
            root.run(["nmcli", "device", "wifi", "connect", net.ssid, "password", password],
                     `Verbinde mit ${net.ssid}…`);
        } else {
            scan.cleanupSsid = net.ssid;
            root.run(["nmcli", "device", "wifi", "connect", net.ssid], `Verbinde mit ${net.ssid}…`);
        }
    }

    function disconnect(net: var): void {
        const profile = root.bestProfile(net);
        if (profile)
            root.run(["nmcli", "connection", "down", "uuid", profile.uuid], `Trenne ${net.ssid}…`);
    }

    function forget(net: var): void {
        if (!net || net.profiles.length === 0)
            return;
        // Alle Profile des Netzes, sonst bleibt ein Rest liegen und verbindet
        // beim naechsten Mal von selbst wieder
        for (const profile of net.profiles)
            root.run(["nmcli", "connection", "delete", "uuid", profile.uuid],
                     `${net.ssid} wird vergessen…`);
    }

    // LAN laeuft ueber das Geraet, nicht ueber ein Profil: `device connect`
    // nimmt das passende Profil selbst (oder legt per DHCP eins an).
    // `device disconnect` sperrt das automatische Verbinden, bis man wieder
    // verbindet – gewollt, sonst waere Trennen nach Sekunden zurueckgenommen.
    function connectWired(dev: var): void {
        root.run(["nmcli", "device", "connect", dev.device], `Verbinde ${dev.device}…`);
    }

    function disconnectWired(dev: var): void {
        root.run(["nmcli", "device", "disconnect", dev.device], `Trenne ${dev.device}…`);
    }

    function wiredStateText(dev: var): string {
        if (dev.connected)
            return "Verbunden";
        if (dev.connecting)
            return "Verbinde…";
        if (dev.state === "unavailable")
            return "Kein Kabel";
        if (dev.state === "unmanaged")
            return "Nicht verwaltet";
        return "Getrennt";
    }

    // Die Profile wegwerfen, die nie zu einer Verbindung gefuehrt haben – und
    // das benutzte behalten.
    function dropStale(net: var): void {
        for (const profile of net.stale)
            root.run(["nmcli", "connection", "delete", "uuid", profile.uuid],
                     `Doppeltes Profil "${profile.name}" wird entfernt…`);
    }

    // Das Profil, ueber das verbunden werden soll: das zuletzt benutzte.
    function bestProfile(net: var): var {
        if (!net || net.profiles.length === 0)
            return null;
        return net.profiles.reduce((a, b) => b.timestamp > a.timestamp ? b : a);
    }

    function signalIcon(net: var): string {
        if (!net.inRange)
            return "wifi_off";
        if (net.signal >= 70)
            return "wifi";
        if (net.signal >= 45)
            return "network_wifi_3_bar";
        if (net.signal >= 25)
            return "network_wifi_2_bar";
        return "network_wifi_1_bar";
    }

    // nmcli -t trennt mit ':' und maskiert echte Doppelpunkte als '\:'
    function splitTerse(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length)
                cur += line[++i];
            else if (c === ":") {
                out.push(cur);
                cur = "";
            } else
                cur += c;
        }
        out.push(cur);
        return out;
    }


    Process {
        id: action

        stderr: StdioCollector {}

        onExited: (code, status) => {
            root.busy = false;

            if (code === 0) {
                root.status = "";
                root.queue = [];        // Erfolg: nichts mehr nachzuholen
            } else {
                // nmcli schreibt "Error: ..." nach stderr
                const msg = action.stderr.text.trim().split("\n").pop();
                root.status = msg !== "" ? msg : `Fehlgeschlagen (Code ${code})`;
                root.queue = [];
            }

            root.refresh(false);
            root.pump();
        }
    }

    // Suche anstossen (ohne zu warten)
    Process {
        id: rescanProc

        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: rescanFollowUp.restart()
    }

    // Nach der Suche zweimal nachlesen (2,5 s und 5 s)
    Timer {
        id: rescanFollowUp

        property int round: 0

        interval: 2500
        onTriggered: {
            root.refresh(false);
            rescanFollowUp.round++;
            if (rescanFollowUp.round < 2)
                rescanFollowUp.restart();
        }
    }

    Process {
        id: scan

        // Kam waehrend eines Laufs eine weitere Anfrage, danach nochmal
        property bool pending: false
        property string rescan: "no"
        // Nach einem gescheiterten Versuch: die neu entstandenen, nie
        // benutzten Profile dieses Netzes wieder loswerden
        property string cleanupSsid: ""

        command: ["sh", "-c",
            'export LC_ALL=C;'
            + ' echo "RADIO $(nmcli -t radio wifi)";'
            + ' nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan ' + scan.rescan + ' | sed "s/^/AP /";'
            + ' nmcli -t -g UUID,TYPE connection show | while IFS=: read -r uuid type; do'
            + '   [ "$type" = "802-11-wireless" ] || continue;'
            + '   printf "PROFILE %s\t%s\n" "$uuid"'
            + '     "$(nmcli -t -g connection.id,802-11-wireless.ssid,connection.timestamp connection show "$uuid" | tr "\\n" "\t")";'
            + ' done;'
            + ' nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device | sed "s/^/DEV /";'
            + ' nmcli -t -f DEVICE,TYPE,STATE device | while IFS=: read -r dev type state; do'
            + '   [ "$type" = "ethernet" ] && [ "$state" = "connected" ] &&'
            + '     echo "IP $dev $(nmcli -t -g IP4.ADDRESS device show "$dev" | head -n1)";'
            + ' done']

        stdout: StdioCollector {
            onStreamFinished: {
                const byName = {};      // SSID -> Eintrag
                const profiles = [];
                const wired = [];
                const ips = {};         // Geraet -> IPv4 (mit /Praefix)

                for (const line of text.split("\n")) {
                    if (line.startsWith("RADIO ")) {
                        root.radioOn = line.slice(6).trim() === "enabled";
                    } else if (line.startsWith("AP ")) {
                        const f = root.splitTerse(line.slice(3));
                        const ssid = f[1] ?? "";
                        if (ssid === "")
                            continue;   // versteckte Netze

                        const entry = {
                            ssid,
                            signal: parseInt(f[2] ?? "0") || 0,
                            security: (f[3] ?? "").trim(),
                            active: (f[0] ?? "").trim() === "*",
                            inRange: true
                        };

                        // Derselbe SSID kommt pro Band/Repeater mehrfach –
                        // der staerkste gewinnt, verbunden schlaegt alles
                        const seen = byName[ssid];
                        if (!seen || entry.active || (!seen.active && entry.signal > seen.signal))
                            byName[ssid] = Object.assign(seen ?? {}, entry);
                    } else if (line.startsWith("PROFILE ")) {
                        const f = line.slice(8).split("\t");
                        if (f.length < 4)
                            continue;
                        profiles.push({
                            uuid: f[0],
                            name: f[1],
                            ssid: f[2],
                            timestamp: parseInt(f[3]) || 0
                        });
                    } else if (line.startsWith("DEV ")) {
                        const f = root.splitTerse(line.slice(4));
                        if (f[1] !== "ethernet")
                            continue;
                        const state = f[2] ?? "";
                        wired.push({
                            device: f[0],
                            state,
                            connection: f[3] ?? "",
                            connected: state === "connected",
                            connecting: state.startsWith("connecting"),
                            available: state !== "unavailable" && state !== "unmanaged"
                        });
                    } else if (line.startsWith("IP ")) {
                        const f = line.slice(3).split(" ");
                        ips[f[0]] = f[1] ?? "";
                    }
                }

                for (const dev of wired)
                    dev.ip = (ips[dev.device] ?? "").split("/")[0];
                root.wired = wired;

                // Gespeicherte Netze ausserhalb der Reichweite trotzdem
                // zeigen – sonst kann man sie weder aendern noch loeschen
                for (const p of profiles)
                    if (p.ssid !== "" && !byName[p.ssid])
                        byName[p.ssid] = {
                            ssid: p.ssid,
                            signal: 0,
                            security: "",
                            active: false,
                            inRange: false
                        };

                const list = [];
                for (const ssid in byName) {
                    const net = byName[ssid];
                    const own = profiles.filter(p => p.ssid === ssid);

                    net.profiles = own;
                    net.saved = own.length > 0;
                    net.duplicate = own.length > 1;
                    net.stale = own.filter(p => p.timestamp === 0);
                    net.secured = net.security !== "";
                    list.push(net);
                }

                list.sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0)
                    || (b.saved ? 1 : 0) - (a.saved ? 1 : 0)
                    || b.signal - a.signal
                    || a.ssid.localeCompare(b.ssid));

                root.networks = list;
                root.loaded = true;

                if (scan.pending) {
                    scan.pending = false;
                    Qt.callLater(() => scan.running = true);
                }

                // Aufraeumen nach einem Fehlversuch (siehe connect)
                if (scan.cleanupSsid !== "") {
                    const net = list.find(n => n.ssid === scan.cleanupSsid);
                    scan.cleanupSsid = "";
                    if (net && net.stale.length > 0 && !net.active) {
                        root.dropStale(net);
                        root.status += " · unbrauchbares Profil entfernt";
                    }
                }
            }
        }
    }

    // Nur nachsehen, solange jemand hinschaut
    Timer {
        interval: 5000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!root.busy)
            root.refresh(false)
    }
}
