pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Bluetooth as QB
import Quickshell.Io

import qs
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.services.sounds

// Bluetooth ueber Quickshell.Bluetooth (BlueZ per DBus), dazu agent.py fuer
// PIN/Passkey-Kopplungen und pactl fuer die Audio-Profile (A2DP/HFP).
//
// Kosten im Leerlauf: keine Timer, kein Polling. agent.py laeuft nur, solange
// ein Adapter an ist. Die sortierte Geraeteliste und die Audio-Karten werden
// nur berechnet, solange ein Panel sie anfordert:
//
//     DemandRequest { demand: BluetoothService.demand; active: panelSichtbar }
//
// Faellt die letzte Anforderung weg (Panel zu, Loader weg), endet auch eine
// von hier gestartete Suche.
Singleton {
    id: root

    readonly property Demand demand: Demand {}
    readonly property bool listing: root.demand.active

    // ---- Adapter ----

    readonly property var adapters: QB.Bluetooth.adapters?.values ?? []
    // Config.bluetooth.adapter = adapterId ("hci1"), leer = automatisch: der
    // Adapter mit verbundenen bzw. gekoppelten Geraeten, sonst BlueZ' Vorgabe.
    // (Mit zwei Adaptern haengen die Geraete oft am "falschen" fuer BlueZ.)
    readonly property var adapter: {
        const list = root.adapters;
        const want = Config.bluetooth.adapter;
        if (want !== "") {
            const chosen = list.find(a => a.adapterId === want);
            if (chosen)
                return chosen;
        }
        let best = QB.Bluetooth.defaultAdapter;
        let bestScore = 0;
        for (const a of list) {
            let score = 0;
            for (const d of a.devices.values)
                score += d.connected ? 100 : d.paired ? 1 : 0;
            if (score > bestScore) {
                best = a;
                bestScore = score;
            }
        }
        return best;
    }
    readonly property bool autoAdapter: Config.bluetooth.adapter === ""
    readonly property bool anyEnabled: root.adapters.some(a => a.enabled)

    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    readonly property bool discoverable: adapter?.discoverable ?? false

    // Lesbarer Name je Adapter (USB-Produkt aus /sys), { "hci1": "TP-Link UB500 Adapter" }
    property var adapterProducts: ({})

    function adapterLabel(a: var): string {
        if (!a)
            return "";
        const product = root.adapterProducts[a.adapterId] ?? "";
        return product !== "" ? `${product} (${a.adapterId})` : `${a.name} (${a.adapterId})`;
    }

    // "" = automatisch
    function selectAdapter(adapterId: string): void {
        if (Config.bluetooth.adapter === adapterId)
            return;
        if (root.adapter?.discovering && root.scanOwned)
            root.adapter.discovering = false;
        root.scanOwned = false;
        Config.bluetooth.adapter = adapterId;
    }

    // ---- Geraete ----

    // Sortiert fuer die Liste: gekoppelte (bzw. alle waehrend der Suche),
    // Verbundene zuerst, namenlose Funde ans Ende. Nur bei Bedarf berechnet.
    readonly property var devices: {
        if (!root.listing)
            return [];
        const scanning = root.discovering;
        const rows = [];
        for (const d of root.adapter?.devices?.values ?? []) {
            if (d.paired || scanning)
                rows.push({ d, rare: root.isRareDevice(d), c: d.connected, p: d.paired, n: root.deviceName(d) });
        }
        rows.sort((a, b) => a.rare - b.rare || b.c - a.c || b.p - a.p || a.n.localeCompare(b.n));
        return rows.map(r => r.d);
    }

    // Immer aktuell (Kachel, Pille): nur die Verbundenen, Audio-Geraete zuerst
    readonly property var connectedDevices: {
        const list = (root.adapter?.devices?.values ?? []).filter(d => d.connected);
        return list.sort((a, b) => root.isAudio(b) - root.isAudio(a));
    }
    readonly property var primaryDevice: root.connectedDevices[0] ?? null
    // "AirPods · 80 %" bzw. "2 Geräte"
    readonly property string summary: {
        const list = root.connectedDevices;
        if (list.length === 0)
            return "";
        if (list.length > 1)
            return I18n.tr("%1 Geräte").arg(list.length);
        const level = root.batteryLevel(list[0]);
        return level >= 0 ? `${root.deviceName(list[0])} · ${level} %` : root.deviceName(list[0]);
    }

    function deviceName(device: var): string {
        return device?.name || device?.deviceName || device?.address || I18n.tr("Unbekanntes Gerät");
    }

    function isRareDevice(device: var): bool {
        if (!device || device.connected || device.paired || device.bonded || device.trusted || device.pairing)
            return false;

        const name = String(device.name || device.deviceName || "").trim();
        if (name === "")
            return true;

        const lower = name.toLowerCase();
        const address = String(device.address || "").toLowerCase();
        const dashedAddress = address.replace(/:/g, "-");
        const isAddress = lower === address || lower === dashedAddress
            || /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(name);
        const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(name);
        return isAddress || isUuid || lower === "unknown" || lower === "unbekannt";
    }

    function isAudio(device: var): bool {
        const icon = (device?.icon ?? "").toLowerCase();
        return icon.includes("audio") || icon.includes("head") || icon.includes("speaker");
    }

    // Material-Symbol je Geraetetyp (BlueZ' Icon ist ein freedesktop-Name)
    function deviceIcon(device: var): string {
        const icon = (device?.icon ?? "").toLowerCase();
        const name = root.deviceName(device).toLowerCase();
        if (icon.includes("headset") || /buds|pods|headset/.test(name))
            return "headset_mic";
        if (icon.includes("head"))
            return "headphones";
        if (icon.includes("speaker") || icon === "audio-card")
            return "speaker";
        if (icon.includes("audio"))
            return "headphones";
        if (icon.includes("mouse"))
            return "mouse";
        if (icon.includes("keyboard"))
            return "keyboard";
        if (icon.includes("tablet"))
            return "tablet";
        if (icon.includes("phone"))
            return "smartphone";
        if (icon.includes("computer"))
            return "computer";
        if (icon.includes("game") || /controller|gamepad|dualsense|xbox/.test(name))
            return "sports_esports";
        if (icon.includes("watch") || /watch|band/.test(name))
            return "watch";
        if (icon.includes("printer"))
            return "print";
        if (icon.includes("video") || icon.includes("tv"))
            return "tv";
        return "bluetooth";
    }

    // 0–100, -1 = unbekannt
    function batteryLevel(device: var): int {
        return device?.batteryAvailable ? Math.round(device.battery * 100) : -1;
    }

    function batteryIcon(level: int): string {
        if (level < 0)
            return "";
        if (level <= 10)
            return "battery_alert";
        const steps = ["battery_1_bar", "battery_2_bar", "battery_3_bar", "battery_4_bar", "battery_5_bar", "battery_6_bar", "battery_full"];
        return steps[Math.min(6, Math.floor(level / 15))];
    }

    // ---- Schalten ----

    // Suche, die von hier gestartet wurde (nur die wird automatisch beendet)
    property bool scanOwned: false

    function setEnabled(on: bool): void {
        if (root.adapter)
            root.adapter.enabled = on;
    }

    function setDiscovering(on: bool): void {
        if (!root.adapter)
            return;
        if (on && !root.adapter.enabled)
            root.adapter.enabled = true;
        root.scanOwned = on;
        root.adapter.discovering = on;
    }

    function setDiscoverable(on: bool): void {
        if (!root.adapter)
            return;
        if (on && !root.adapter.enabled)
            root.adapter.enabled = true;
        root.adapter.pairable = on;
        root.adapter.pairableTimeout = on ? 180 : 0;
        root.adapter.discoverableTimeout = on ? 180 : 0;
        root.adapter.discoverable = on;
    }

    // Laufende Verbindungsversuche { dbusPath: { kind: "connect"|"disconnect", since } }
    // und letzte Fehler { dbusPath: "Text" } – fuer Spinner und Fehlerzeile.
    property var ops: ({})
    property var errors: ({})
    readonly property int opTimeoutMs: 15000

    function busy(device: var): string {
        return device ? (root.ops[device.dbusPath]?.kind ?? "") : "";
    }

    function errorFor(device: var): string {
        return device ? (root.errors[device.dbusPath] ?? "") : "";
    }

    function setOp(path: string, kind: string): void {
        const next = Object.assign({}, root.ops);
        if (kind === "")
            delete next[path];
        else
            next[path] = { kind, since: Date.now() };
        root.ops = next;
    }

    function setError(path: string, message: string): void {
        const next = Object.assign({}, root.errors);
        if (message === "")
            delete next[path];
        else
            next[path] = message;
        root.errors = next;
    }

    function connectDevice(device: var): void {
        if (!device || root.busy(device) !== "")
            return;
        root.setError(device.dbusPath, "");
        root.setOp(device.dbusPath, "connect");
        // Wer verbinden will, vertraut dem Geraet – sonst fragt BlueZ bei
        // jedem Dienst nach (AuthorizeService).
        if (!device.trusted)
            device.trusted = true;
        // Waehrend einer Suche scheitern Verbindungen oft (Funk ist belegt):
        // erst stoppen, kurz warten, dann verbinden.
        if (device.adapter?.discovering) {
            device.adapter.discovering = false;
            root.scanOwned = false;
            connectDelay.queue = connectDelay.queue.concat([device]);
            connectDelay.restart();
        } else {
            device.connect();
        }
    }

    function disconnectDevice(device: var): void {
        if (!device || root.busy(device) !== "")
            return;
        root.setError(device.dbusPath, "");
        root.setOp(device.dbusPath, "disconnect");
        device.disconnect();
    }

    function toggleTrusted(device: var): void {
        if (device)
            device.trusted = !device.trusted;
    }

    function toggleBlocked(device: var): void {
        if (!device)
            return;
        if (!device.blocked && device.connected)
            device.disconnect();
        device.blocked = !device.blocked;
    }

    // Leerer Name setzt BlueZ' Alias auf den Geraetenamen zurueck
    function rename(device: var, name: string): void {
        if (device)
            device.name = name.trim();
    }

    function forget(device: var): void {
        if (!device)
            return;
        root.setOp(device.dbusPath, "");
        root.setError(device.dbusPath, "");
        device.forget();
    }

    Timer {
        id: connectDelay

        property var queue: []

        interval: 400
        onTriggered: {
            for (const d of connectDelay.queue)
                d.connect();
            connectDelay.queue = [];
        }
    }

    // Prueft haengende Verbindungsversuche – laeuft nur, solange es welche gibt
    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.ops).length > 0
        onTriggered: {
            const now = Date.now();
            for (const path in root.ops) {
                const op = root.ops[path];
                if (now - op.since < root.opTimeoutMs)
                    continue;
                root.setOp(path, "");
                root.setError(path, op.kind === "connect" ? I18n.tr("Verbindung fehlgeschlagen")
                    : I18n.tr("Trennen fehlgeschlagen"));
            }
        }
    }

    // Selbst gestartete Suche endet nach bluetooth.scanSeconds bzw. sobald
    // kein Panel mehr offen ist
    Timer {
        interval: Math.max(5, Config.bluetooth.scanSeconds) * 1000
        running: root.discovering && root.scanOwned
        onTriggered: root.setDiscovering(false)
    }

    onListingChanged: {
        if (!root.listing && root.scanOwned && root.discovering)
            root.setDiscovering(false);
        if (root.listing)
            audioRefresh.restart();
    }

    // ---- Je Geraet: Zustandswechsel melden, Akku ueberwachen ----

    // Meldungen erst nach dem Start, nicht fuer den Anfangszustand
    property bool settled: false

    Timer {
        interval: 3000
        running: true
        onTriggered: root.settled = true
    }

    function deviceConnectedChanged(device: var): void {
        const op = root.ops[device.dbusPath];
        root.setOp(device.dbusPath, "");
        if (device.connected)
            root.setError(device.dbusPath, "");
        if (root.isAudio(device))
            audioRefresh.restart();
        if (!root.settled || !device.paired)
            return;
        if (Config.sounds.bluetooth)
            Sounds.play(device.connected ? "connect" : "disconnect");
        // Selbst ausgeloeste Wechsel sieht man im Panel – Meldung nur fuer
        // das, was von allein passiert (Kopfhoerer eingeschaltet, Akku leer)
        if (Config.bluetooth.notify && !op)
            root.notify(device, device.connected ? I18n.tr("Verbunden") : I18n.tr("Getrennt"));
    }

    function deviceStateChanged(device: var): void {
        // Connecting -> Disconnected heisst: Versuch gescheitert (ohne den
        // Timeout abzuwarten)
        const op = root.ops[device.dbusPath];
        if (op?.kind === "connect" && device.state === QB.BluetoothDeviceState.Disconnected
                && Date.now() - op.since > 800) {
            root.setOp(device.dbusPath, "");
            root.setError(device.dbusPath, I18n.tr("Verbindung fehlgeschlagen"));
        }
    }

    function notify(device: var, body: string): void {
        Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", device.icon || "bluetooth",
            root.deviceName(device), body]);
    }

    Instantiator {
        model: root.anyEnabled ? QB.Bluetooth.devices : null

        delegate: QtObject {
            id: watch

            required property var modelData
            // Warnung einmal je Entladung, wieder scharf ab Schwelle + 5 %
            property bool warned: false
            readonly property int level: root.batteryLevel(watch.modelData)

            onLevelChanged: {
                const limit = Config.bluetooth.lowBattery;
                if (limit <= 0 || watch.level < 0)
                    return;
                if (watch.level > limit + 5)
                    watch.warned = false;
                else if (watch.level <= limit && !watch.warned && watch.modelData.connected) {
                    watch.warned = true;
                    root.notify(watch.modelData, I18n.tr("Akku schwach: %1 %").arg(watch.level));
                }
            }

            readonly property Connections conn: Connections {
                target: watch.modelData

                function onConnectedChanged(): void {
                    root.deviceConnectedChanged(watch.modelData);
                }

                function onStateChanged(): void {
                    root.deviceStateChanged(watch.modelData);
                }
            }
        }
    }

    // ---- Audio-Profile (pactl) ----

    // { "AA:BB:…": { card, active, profiles: [{ name, description, available }] } }
    property var audioCards: ({})

    function audioInfo(device: var): var {
        return device ? (root.audioCards[device.address] ?? null) : null;
    }

    // "Hi-Fi (A2DP)", "Headset (HFP)" – kurze Namen statt PipeWires langer Beschreibung
    function profileLabel(name: string): string {
        if (name.startsWith("a2dp"))
            return I18n.tr("Hi-Fi (A2DP)");
        if (name.startsWith("headset") || name.includes("hfp") || name.includes("hsp"))
            return I18n.tr("Headset mit Mikrofon (HFP)");
        if (name === "off")
            return I18n.tr("Aus");
        return name;
    }

    function setAudioProfile(device: var, profile: string): void {
        const info = root.audioInfo(device);
        if (!info)
            return;
        Quickshell.execDetached(["pactl", "set-card-profile", info.card, profile]);
        audioRefresh.restart();
    }

    // Kurz warten: die Karte erscheint erst einen Moment nach dem Verbinden
    Timer {
        id: audioRefresh

        interval: 700
        onTriggered: {
            if (root.listing || root.connectedDevices.some(d => root.isAudio(d)))
                cards.running = true;
            else
                root.audioCards = {};
        }
    }

    Process {
        id: cards

        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    return;
                }
                const out = {};
                for (const c of list) {
                    const address = c.properties?.["api.bluez5.address"];
                    if (!address)
                        continue;
                    const profiles = [];
                    for (const name in c.profiles ?? {}) {
                        const p = c.profiles[name];
                        if (name !== "off" && p.available !== false)
                            profiles.push({ name, description: p.description ?? name, available: p.available !== false });
                    }
                    out[address.toUpperCase()] = { card: c.name, active: c.active_profile ?? "", profiles };
                }
                root.audioCards = out;
            }
        }
    }

    // ---- Kopplung (agent.py) ----

    property var pairingDevice: null
    property string pairingRequest: ""
    property string pairingPasskey: ""
    property string pairingMessage: ""
    property bool agentReady: false
    readonly property bool pairingInputRequired: pairingRequest === "pin" || pairingRequest === "passkey"
    readonly property bool pairingActive: pairingDevice !== null
    property int pairingEntered: 0
    property bool pairingLocallyStarted: false

    function beginPairing(device: var): void {
        if (!device || root.pairingActive)
            return;
        root.pairingDevice = device;
        root.pairingLocallyStarted = true;
        root.pairingRequest = "waiting";
        root.pairingPasskey = "";
        root.pairingMessage = I18n.tr("Kopplung wird gestartet…");
        if (!root.agentReady) {
            root.pairingRequest = "error";
            root.pairingMessage = I18n.tr("Bluetooth-Agent ist noch nicht bereit");
            return;
        }
        // Wie beim Verbinden: Kopplung waehrend der Suche ist unzuverlaessig
        if (device.adapter?.discovering) {
            device.adapter.discovering = false;
            root.scanOwned = false;
        }
        sendAgent({ action: "pair", path: device.dbusPath });
    }

    function submitPin(pin: string): void {
        if (!root.pairingInputRequired || pin === "")
            return;
        sendAgent({ action: "respond", value: pin });
        root.pairingRequest = "waiting";
        root.pairingMessage = I18n.tr("PIN wird geprüft…");
    }

    function confirmPairing(accept: bool): void {
        if (root.pairingRequest !== "confirm" && root.pairingRequest !== "authorize")
            return;
        sendAgent({ action: "respond", accept: accept });
        if (accept) {
            root.pairingRequest = "waiting";
            root.pairingMessage = I18n.tr("Kopplung wird bestätigt…");
            if (root.pairingDevice?.paired && !root.pairingLocallyStarted)
                root.clearPairing();
        } else {
            root.clearPairing();
        }
    }

    function cancelPairing(): void {
        if (root.pairingDevice && root.pairingRequest !== "error")
            sendAgent({ action: "cancel", path: root.pairingDevice.dbusPath });
        root.clearPairing();
    }

    function clearPairing(): void {
        root.pairingDevice = null;
        root.pairingRequest = "";
        root.pairingPasskey = "";
        root.pairingMessage = "";
        root.pairingEntered = 0;
        root.pairingLocallyStarted = false;
    }

    function sendAgent(message: var): void {
        if (agent.running)
            agent.write(JSON.stringify(message) + "\n");
    }

    function handleAgentOutput(line: string): void {
        let event;
        try {
            event = JSON.parse(line);
        } catch (error) {
            console.warn("Bluetooth-Agent: ungültige Antwort", error);
            return;
        }
        if (event.event === "ready") {
            root.agentReady = event.ready;
            if (event.ready)
                root.agentFailures = 0;
            if (!event.ready && root.pairingActive) {
                root.pairingRequest = "error";
                root.pairingMessage = I18n.tr("Bluetooth-Agent ist nicht verfügbar");
            }
        } else if (event.event === "request") {
            const device = QB.Bluetooth.devices.values.find(device => device.dbusPath === event.path);
            if (!device) {
                sendAgent({ action: "respond", accept: false });
                return;
            }
            root.pairingDevice = device;
            root.pairingPasskey = event.passkey || "";
            root.pairingEntered = event.entered || 0;
            root.pairingMessage = event.kind === "pin" ? I18n.tr("PIN des Geräts eingeben")
                : event.kind === "passkey" ? I18n.tr("Passkey des Geräts eingeben (1–6 Ziffern)")
                : event.kind === "confirm" ? I18n.tr("Stimmt dieser Code auf beiden Geräten überein?")
                : event.kind === "display" ? I18n.tr("Diesen Code am anderen Gerät eingeben")
                : I18n.tr("Verbindung bzw. Dienste dieses Geräts erlauben?");
            root.pairingRequest = event.kind;
        } else if (event.event === "paired") {
            if (root.pairingDevice?.dbusPath === event.path) {
                const device = root.pairingDevice;
                root.clearPairing();
                root.connectDevice(device);
            }
        } else if (event.event === "canceled") {
            root.clearPairing();
        } else if (event.event === "input-error") {
            root.pairingRequest = event.kind;
            root.pairingMessage = I18n.tr(event.message);
        } else if (event.event === "error") {
            if (event.path && event.path !== root.pairingDevice?.dbusPath)
                return;
            console.warn("Bluetooth-Agent:", event.message);
            if (root.pairingActive) {
                root.pairingRequest = "error";
                root.pairingMessage = I18n.tr("Kopplung fehlgeschlagen: %1").arg(event.message);
            }
        }
    }

    Connections {
        target: root.pairingDevice

        function onPairedChanged(): void {
            // Vom Handy gestartete Kopplungen haben keinen eigenen Pair-Aufruf.
            if (root.pairingDevice?.paired && !root.pairingLocallyStarted)
                root.clearPairing();
        }

        function onConnectedChanged(): void {
            if (root.pairingDevice?.connected && root.pairingRequest === "waiting" && !root.pairingLocallyStarted)
                root.clearPairing();
        }
    }

    // Agent nur, solange ein Adapter an ist (aus = keine Kopplung moeglich).
    // Stirbt er unerwartet, neu starten: 1 s, 3 s, 10 s, 30 s, dann aufgeben.
    property int agentFailures: 0
    property bool agentBackoff: false

    Timer {
        id: agentRestart

        onTriggered: root.agentBackoff = false
    }

    Process {
        id: agent

        command: ["python3", "-I", Quickshell.shellPath("modules/services/bluetooth/agent.py")]
        stdinEnabled: true
        running: root.anyEnabled && !root.agentBackoff

        onExited: (code, status) => {
            root.agentReady = false;
            if (root.pairingDevice) {
                root.pairingRequest = "error";
                root.pairingMessage = I18n.tr("Bluetooth-Agent wurde beendet");
            }
            if (!root.anyEnabled)
                return;
            const delays = [1000, 3000, 10000, 30000];
            if (root.agentFailures >= delays.length) {
                console.warn("Bluetooth-Agent: gibt nach", root.agentFailures, "Neustarts auf (Code", code + ")");
                return;
            }
            console.warn("Bluetooth-Agent beendet (Code", code + "), Neustart in", delays[root.agentFailures], "ms");
            agentRestart.interval = delays[root.agentFailures];
            root.agentFailures++;
            root.agentBackoff = true;
            agentRestart.restart();
        }

        stdout: SplitParser {
            onRead: line => root.handleAgentOutput(line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("Bluetooth-Agent:", line)
        }
    }

    // USB-Produktnamen der Adapter einmal lesen (fuer die Adapter-Auswahl)
    Process {
        running: root.adapters.length > 1
        command: ["sh", "-c", "for d in /sys/class/bluetooth/hci*; do u=$d/device/..; printf '%s\\t%s\\t%s\\n' \"${d##*/}\" \"$(cat $u/product 2>/dev/null)\" \"$(cat $u/manufacturer 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {};
                for (const line of text.trim().split("\n")) {
                    const [id, product, vendor] = line.split("\t").map(s => (s ?? "").trim());
                    // Onboard-Chips heissen oft nur "Wireless_Device" – dann der Hersteller
                    const generic = product === "" || /^wireless[_ ]device$/i.test(product);
                    const label = generic ? vendor : product;
                    if (id && label)
                        out[id] = label;
                }
                root.adapterProducts = out;
            }
        }
    }

    IpcHandler {
        target: "bluetooth"

        function status(): string {
            return JSON.stringify({
                adapter: root.adapter?.adapterId ?? "",
                auto: root.autoAdapter,
                enabled: root.enabled,
                agent: root.agentReady,
                connected: root.connectedDevices.map(d => ({ name: root.deviceName(d), battery: root.batteryLevel(d) })),
                audio: root.audioCards
            });
        }

        function toggle(): void {
            root.setEnabled(!root.enabled);
        }
    }
}
