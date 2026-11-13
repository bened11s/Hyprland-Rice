pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.config
import qs.modules.services.core

import qs

// VPN-Dienst mit Anbieter-Register: die eingebauten (NordVPN, Cloudflare
// WARP) plus eigene aus Config.vpn.custom. Jeder Eintrag in `providers`:
//
//     { id, name, icon, builtin, available }
//
// Eingebaute rufen ihre CLI direkt (`nordvpn connect`), eigene laufen als
// Shell-Befehl (`sh -c …`). Verbunden ist ein eigener Anbieter, wenn die
// Ausgabe (stdout + stderr) seines Status-Befehls auf `connectedRegex`
// passt (Gross/Klein egal) – ohne Regex zaehlt Exit-Code 0 als verbunden.
// Installiert ist er, wenn das erste Wort seines Verbinden-Befehls per
// `command -v` zu finden ist (sudo/pkexec/doas davor werden uebersprungen).
Singleton {
    id: root

    // ---- Register ----

    readonly property var builtins: [
        { id: "nordvpn", name: "NordVPN", icon: "vpn_key", builtin: true, bin: "nordvpn" },
        { id: "cloudflare", name: "Cloudflare WARP", icon: "cloud", builtin: true, bin: "warp-cli" }
    ]

    // Eigene Anbieter aus der Datei, als reine JS-Objekte (der Adapter
    // liefert QVariant-Listen)
    readonly property var customList: {
        const raw = Config.vpn.custom;
        if (!raw || raw.length === undefined)
            return [];
        let list;
        try {
            list = JSON.parse(JSON.stringify(raw));
        } catch (e) {
            return [];
        }
        return list.filter(c => c && typeof c === "object" && String(c.id ?? "") !== "");
    }

    readonly property var definitions: root.builtins.concat(root.customList.map(c => ({
        id: String(c.id),
        name: String(c.name ?? "") || String(c.id),
        icon: String(c.icon ?? "") || "vpn_key",
        builtin: false,
        connect: String(c.connect ?? ""),
        disconnect: String(c.disconnect ?? ""),
        status: String(c.status ?? ""),
        connectedRegex: String(c.connectedRegex ?? ""),
        bin: root.binOf(String(c.connect ?? ""))
    })))

    // Welche CLIs installiert sind ({ nordvpn: true, "wg-quick": false }) –
    // fehlende werden gar nicht erst aufgerufen
    property var tools: ({})
    property bool toolsChecked: false

    readonly property var providers: root.definitions.map(d => ({
        id: d.id, name: d.name, icon: d.icon, builtin: d.builtin,
        available: root.tools[d.bin] === true
    }))

    function definition(id: string): var {
        return root.definitions.find(d => d.id === id) ?? null;
    }

    // Unbekannte id (geloeschter Anbieter, Tippfehler in der Datei): NordVPN
    readonly property string provider: root.definition(Config.vpn.provider) ? Config.vpn.provider : "nordvpn"
    readonly property var current: root.definition(root.provider) ?? root.builtins[0]
    readonly property string providerName: root.current.name
    readonly property string providerIcon: root.current.icon
    readonly property bool builtin: root.current.builtin
    readonly property bool available: root.tools[root.current.bin] === true
    readonly property bool nordAvailable: root.tools["nordvpn"] === true
    readonly property bool warpAvailable: root.tools["warp-cli"] === true

    readonly property bool connected: statusProc.status === "Connected"
    readonly property string statusText: !root.available ? (root.toolsChecked ? I18n.tr("Nicht installiert") : I18n.tr("Nicht bereit"))
                                                : connected ? I18n.tr("Verbunden")
                                                : statusProc.status === "Disconnected" ? I18n.tr("Getrennt")
                                                : I18n.tr("Nicht bereit")

    property bool nordConnected: false
    property bool warpConnected: false
    property bool nordStatusReady: false
    property bool warpStatusReady: false

    // Offene VPN-Anzeige (Kachel) laesst haeufiger nachsehen, sonst reicht
    // eine Minute – Aenderungen ueber die Shell liest refreshTimer sofort nach
    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active

    // Programm hinter einem Shell-Befehl: erstes Wort, das kein Rechte-
    // Wrapper und keine VAR=wert-Zuweisung ist
    function binOf(cmd: string): string {
        const skip = ["sudo", "doas", "pkexec", "env", "nohup", "run0"];
        for (const word of cmd.trim().split(/\s+/)) {
            if (word === "" || skip.includes(word) || word.includes("=") || word.startsWith("-"))
                continue;
            // ~/bin/x: ~ selbst aufloesen, sonst bliebe "/bin/x" uebrig
            const w = word.startsWith("~/") ? Quickshell.env("HOME") + word.slice(1) : word;
            return w.replace(/[^A-Za-z0-9._+\/-]/g, "");
        }
        return "";
    }

    function commandFor(vpnProvider: string, action: string): list<string> {
        const def = root.definition(vpnProvider) ?? root.builtins[0];
        if (def.builtin)
            return [def.bin, action];
        // Status mit Zeitlimit: ein haengender Befehl blockierte sonst
        // statusProc fuer immer (running = true bewirkt dann nichts mehr)
        if (action === "status")
            return ["timeout", "15", "sh", "-c", String(def[action] ?? "")];
        return ["sh", "-c", String(def[action] ?? "")];
    }

    // Ausgabe des Status-Befehls -> "Connected" | "Disconnected" | "Unknown"
    function parseStatus(def: var, text: string, code: int): string {
        if (def.builtin) {
            const match = text.match(/Status(?: update)?:\s*(Connected|Disconnected)/i);
            if (!match)
                return "Unknown";
            return match[1].toLowerCase() === "connected" ? "Connected" : "Disconnected";
        }
        return root.matches(text, code, def.connectedRegex) ? "Connected" : "Disconnected";
    }

    function matches(text: string, code: int, pattern: string): bool {
        if (pattern.trim() === "")
            return code === 0;
        try {
            return new RegExp(pattern, "i").test(text);
        } catch (e) {
            console.warn("VPN: ungueltiger Regex", JSON.stringify(pattern), e);
            return false;
        }
    }

    function selectProvider(vpnProvider: string): void {
        if (vpnProvider === root.provider || !root.definition(vpnProvider))
            return;

        // Den alten Tunnel nicht unbemerkt weiterlaufen lassen.
        if (root.connected)
            Quickshell.execDetached(root.commandFor(root.provider, "disconnect"));

        Config.set("vpn", "provider", vpnProvider);
    }

    // Nur zwischen den eingebauten: meldet genau eine CLI "verbunden",
    // wechselt die Anzeige dorthin. Ein eigener Anbieter bleibt gewaehlt.
    function applyDetectedProvider(): void {
        if (!root.nordStatusReady || !root.warpStatusReady || !root.builtin)
            return;

        if (warpConnected && !nordConnected && root.provider !== "cloudflare")
            Config.set("vpn", "provider", "cloudflare");
        else if (nordConnected && !warpConnected && root.provider !== "nordvpn")
            Config.set("vpn", "provider", "nordvpn");
    }

    // Nicht installierte CLIs gelten sofort als "getrennt und fertig gelesen".
    // Der gewaehlte Anbieter wird nicht extra gefragt – das erledigt
    // statusProc ohnehin (frueher lief `nordvpn status` so zweimal je Takt).
    function detectProviders(): void {
        root.nordConnected = root.nordConnected && root.nordAvailable;
        root.warpConnected = root.warpConnected && root.warpAvailable;
        root.nordStatusReady = !root.nordAvailable;
        root.warpStatusReady = !root.warpAvailable;
        if (root.nordAvailable && root.provider !== "nordvpn")
            nordStatusProc.running = true;
        if (root.warpAvailable && root.provider !== "cloudflare")
            warpStatusProc.running = true;
        root.applyDetectedProvider();
    }

    function refreshStatus(): void {
        if (root.available && (root.builtin || root.current.status.trim() !== ""))
            statusProc.running = true;
        else if (root.available && !root.builtin)
            // Eigener Anbieter ohne Status-Befehl: der zuletzt geschaltete
            // Zustand gilt (sonst fiele er nach 5 s auf "unbekannt" und
            // toggle() koennte nie trennen), anfangs "getrennt"
            statusProc.status = statusProc.status === "Connected" ? "Connected" : "Disconnected";
        else
            statusProc.status = "Unknown";
    }

    function toggle(): void {
        if (!root.available) {
            console.warn("VPN (" + providerName + "): CLI nicht installiert");
            return;
        }
        if (connected) {
            console.log("VPN (" + providerName + "): disconnecting...");
            statusProc.status = "Disconnected";
            disconnectProc.command = root.commandFor(root.provider, "disconnect");
            disconnectProc.running = true;
        } else {
            console.log("VPN (" + providerName + "): connecting...");
            statusProc.status = "Connected";
            connectProc.command = root.commandFor(root.provider, "connect");
            connectProc.running = true;
        }

        refreshTimer.restart();
    }

    // ---- Eigene Anbieter (Config.vpn.custom) ----

    function normaliseCustom(id: string, obj: var): var {
        return {
            id,
            name: String(obj.name ?? "").trim(),
            icon: String(obj.icon ?? "").trim() || "vpn_key",
            connect: String(obj.connect ?? "").trim(),
            disconnect: String(obj.disconnect ?? "").trim(),
            status: String(obj.status ?? "").trim(),
            connectedRegex: String(obj.connectedRegex ?? "").trim()
        };
    }

    function addCustom(obj: var): string {
        const id = "custom-" + Date.now().toString(36);
        const list = root.customList.map(c => Object.assign({}, c));
        list.push(root.normaliseCustom(id, obj));
        Config.set("vpn", "custom", list);
        return id;
    }

    function updateCustom(id: string, obj: var): void {
        const list = root.customList.map(c => c.id === id ? root.normaliseCustom(id, obj) : Object.assign({}, c));
        Config.set("vpn", "custom", list);
    }

    // Den gewaehlten entfernen: vorher trennen, dann zurueck zu einem
    // eingebauten (dem installierten, sonst NordVPN)
    function removeCustom(id: string): void {
        if (root.provider === id) {
            if (root.connected)
                Quickshell.execDetached(root.commandFor(id, "disconnect"));
            Config.set("vpn", "provider", root.warpAvailable && !root.nordAvailable ? "cloudflare" : "nordvpn");
        }
        Config.set("vpn", "custom", root.customList.filter(c => c.id !== id).map(c => Object.assign({}, c)));
    }

    // Probelauf fuer den Editor: Status-Befehl ausfuehren und melden, ob die
    // Ausgabe als "verbunden" gelten wuerde.
    //   { running, output, code, connected }  (null = noch nie getestet)
    property var testResult: null

    function testStatus(cmd: string, pattern: string): void {
        if (testProc.running)
            return;
        testProc.pattern = pattern;
        // Mit Zeitlimit: ein haengender Befehl liesse "Testen" sonst fuer
        // immer gesperrt (Exit-Code 124 = abgebrochen)
        testProc.command = ["timeout", "10", "sh", "-c", cmd];
        root.testResult = { running: true, output: "", code: -1, connected: false };
        testProc.running = true;
    }

    function clearTest(): void {
        root.testResult = null;
    }

    Process {
        id: testProc

        property string pattern: ""

        stdout: StdioCollector {
            id: testOut
        }
        stderr: StdioCollector {
            id: testErr
        }
        onExited: (code, exitStatus) => {
            const text = testOut.text + testErr.text;
            root.testResult = {
                running: false,
                output: text.trim(),
                code,
                connected: root.matches(text, code, testProc.pattern)
            };
        }
    }

    // ---- Prozesse ----

    Process {
        id: connectProc
    }

    Process {
        id: disconnectProc
    }

    Process {
        id: statusProc
        command: root.commandFor(root.provider, "status")

        property string status: ""
        property string _prevStatus: ""   // "" = noch nie gelesen -> keine Boot-Notification

        // Notification nur bei echten Übergängen zwischen bekannten Zuständen
        onStatusChanged: {
            const known = s => s === "Connected" || s === "Disconnected";
            const was = _prevStatus === "Connected";
            const now = status === "Connected";

            if (_prevStatus !== "" && known(_prevStatus) && known(status) && was !== now) {
                console.log("VPN status changed:", now ? "connected" : "disconnected");
                Quickshell.execDetached(["notify-send", "-a", "dynamic-island", root.providerName,
                                         now ? I18n.tr("Verbunden") : I18n.tr("Getrennt")]);
            }
            _prevStatus = status;
        }

        stdout: StdioCollector {
            id: collector
        }
        stderr: StdioCollector {
            id: errCollector
        }

        // Die Sammler sind beim Exit komplett (so auch Clipboard/Idle)
        onExited: (code, exitStatus) => {
            const def = root.current;
            statusProc.status = root.parseStatus(def, def.builtin ? collector.text : collector.text + "\n" + errCollector.text, code);

            // Zaehlt zugleich als Ergebnis der Anbieter-Erkennung
            if (!def.builtin)
                return;
            if (def.id === "cloudflare") {
                root.warpConnected = root.connected;
                root.warpStatusReady = true;
            } else {
                root.nordConnected = root.connected;
                root.nordStatusReady = true;
            }
            root.applyDetectedProvider();
        }
    }

    // Alle Programme der Anbieter auf einmal nachsehen
    readonly property string binList: {
        const bins = [];
        for (const d of root.definitions) {
            if (d.bin !== "" && !bins.includes(d.bin))
                bins.push(d.bin);
        }
        return bins.map(b => "'" + b.replace(/'/g, "") + "'").join(" ");
    }

    Process {
        id: toolCheck
        command: ["sh", "-c", "for t in " + root.binList + "; do command -v \"$t\" >/dev/null && echo \"$t\"; done"]
        running: true

        property bool again: false

        stdout: StdioCollector {
            onStreamFinished: {
                const found = this.text.split("\n");
                const next = {};
                for (const d of root.definitions)
                    next[d.bin] = found.includes(d.bin);
                root.tools = next;
                root.toolsChecked = true;
                root.refreshStatus();
                root.detectProviders();
            }
        }
        onExited: {
            if (toolCheck.again) {
                toolCheck.again = false;
                toolCheck.running = true;
            }
        }
    }

    function recheckTools(): void {
        if (toolCheck.running)
            toolCheck.again = true;
        else
            toolCheck.running = true;
    }

    // Neuer oder geaenderter Anbieter: Programm pruefen, Status neu lesen
    onBinListChanged: if (root.toolsChecked) root.recheckTools()
    onCurrentChanged: if (root.toolsChecked) providerRefresh.restart()

    Process {
        id: nordStatusProc
        command: ["nordvpn", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.nordConnected = root.parseStatus(root.builtins[0], this.text, 0) === "Connected";
                root.nordStatusReady = true;
                root.applyDetectedProvider();
            }
        }
    }

    Process {
        id: warpStatusProc
        command: ["warp-cli", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.warpConnected = root.parseStatus(root.builtins[1], this.text, 0) === "Connected";
                root.warpStatusReady = true;
                root.applyDetectedProvider();
            }
        }
    }

    onProviderChanged: {
        statusProc.status = "Unknown";
        statusProc._prevStatus = "";
        providerRefresh.restart();
    }

    Timer {
        id: providerRefresh
        interval: 100
        onTriggered: root.refreshStatus()
    }

    // Einmal-Timer: nach connect/disconnect den Status neu lesen
    Timer {
        id: refreshTimer
        interval: 5000
        onTriggered: root.refreshStatus()
    }

    // Kachel geht auf: sofort frisch lesen, statt auf den naechsten Takt zu warten
    onWatchingChanged: if (root.watching) root.refreshStatus()

    // Regelmäßiges Polling, falls sich außerhalb der Shell was ändert. Ohne
    // offene Kachel nur selten – sichtbar ist der Status dann hoechstens als
    // Symbol der Insel-Pille.
    Timer {
        interval: root.watching ? 15000 : 300000
        running: root.toolsChecked && (root.available || root.nordAvailable || root.warpAvailable)
        repeat: true
        onTriggered: {
            root.refreshStatus();
            root.detectProviders();
        }
    }

    // Selten: nachinstallierte CLIs entdecken
    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: root.recheckTools()
    }
}
