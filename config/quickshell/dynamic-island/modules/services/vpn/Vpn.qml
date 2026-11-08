pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.config
import qs.modules.services.core

import qs

Singleton {
    id: root

    readonly property string provider: Config.vpn.provider === "cloudflare" ? "cloudflare" : "nordvpn"
    readonly property string providerName: provider === "cloudflare" ? "Cloudflare WARP" : "NordVPN"
    readonly property bool connected: statusProc.status === "Connected"
    readonly property string statusText: !root.available ? (root.toolsChecked ? I18n.tr("Nicht installiert") : I18n.tr("Nicht bereit"))
                                                : connected ? I18n.tr("Verbunden")
                                                : statusProc.status === "Disconnected" ? I18n.tr("Getrennt")
                                                : I18n.tr("Nicht bereit")
    // Welche CLIs installiert sind – fehlende werden gar nicht erst aufgerufen
    property bool nordAvailable: false
    property bool warpAvailable: false
    property bool toolsChecked: false
    readonly property bool available: provider === "cloudflare" ? warpAvailable : nordAvailable
    property bool nordConnected: false
    property bool warpConnected: false
    property bool nordStatusReady: false
    property bool warpStatusReady: false

    // Offene VPN-Anzeige (Kachel) laesst haeufiger nachsehen, sonst reicht
    // eine Minute – Aenderungen ueber die Shell liest refreshTimer sofort nach
    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active

    function commandFor(vpnProvider: string, action: string): list<string> {
        return vpnProvider === "cloudflare" ? ["warp-cli", action] : ["nordvpn", action];
    }

    function selectProvider(vpnProvider: string): void {
        if (vpnProvider === root.provider)
            return;

        // Den alten Tunnel nicht unbemerkt weiterlaufen lassen.
        if (root.connected)
            Quickshell.execDetached(root.commandFor(root.provider, "disconnect"));

        Config.set("vpn", "provider", vpnProvider);
    }

    function applyDetectedProvider(): void {
        if (!root.nordStatusReady || !root.warpStatusReady)
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
        if (root.available)
            statusProc.running = true;
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
            onStreamFinished: {
                const match = collector.text.match(/Status(?: update)?:\s*(Connected|Disconnected)/i);
                if (!match)
                    statusProc.status = "Unknown";
                else
                    statusProc.status = match[1].toLowerCase() === "connected" ? "Connected" : "Disconnected";

                // Zaehlt zugleich als Ergebnis der Anbieter-Erkennung
                if (root.provider === "cloudflare") {
                    root.warpConnected = root.connected;
                    root.warpStatusReady = true;
                } else {
                    root.nordConnected = root.connected;
                    root.nordStatusReady = true;
                }
                root.applyDetectedProvider();
            }
        }
    }

    Process {
        id: toolCheck
        command: ["sh", "-c", "for t in nordvpn warp-cli; do command -v \"$t\" >/dev/null && echo \"$t\"; done"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const found = this.text.split("\n");
                root.nordAvailable = found.includes("nordvpn");
                root.warpAvailable = found.includes("warp-cli");
                root.toolsChecked = true;
                root.refreshStatus();
                root.detectProviders();
            }
        }
    }

    Process {
        id: nordStatusProc
        command: ["nordvpn", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.nordConnected = /Status:\s*Connected/i.test(this.text);
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
                root.warpConnected = /Status update:\s*Connected/i.test(this.text);
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
        running: root.toolsChecked && (root.nordAvailable || root.warpAvailable)
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
        onTriggered: toolCheck.running = true
    }
}
