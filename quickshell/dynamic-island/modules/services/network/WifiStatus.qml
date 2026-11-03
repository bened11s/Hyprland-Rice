pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.services.core

// Kurzstatus des WLANs fuer Symbole und Kacheln: Funk an/aus, verbunden mit
// welchem Netz, Empfang. Die volle Netzliste (Scan, Verbinden, ...) ist
// Network.qml – das hier ist der billige Teil, den die Leiste dauernd zeigt.
//
// Frueher pollte jede Anzeige selbst (WLAN-Symbol alle 3 s, Kachel alle 5 s).
// Beide gibt es je Monitor und Einbauort (Pille + Steuerungs-Untermenue),
// zusammen liefen so ~250 nmcli pro Minute. Jetzt eine Quelle:
//   - `nmcli monitor` meldet Verbindungs- und Funkwechsel sofort,
//   - nur die Signalstaerke wird langsam nachgelesen (meldet nmcli nicht),
//   - und das alles nur, solange eine Anzeige zu sehen ist (DemandRequest).
//
//     DemandRequest { demand: WifiStatus.demand; active: icon.visible }
Singleton {
    id: root

    readonly property Demand demand: Demand {}
    readonly property bool watching: root.demand.active

    property bool loaded: false
    property bool radioOn: true
    property bool connected: false
    property string ssid: ""
    property int signal: 0

    // Verbindungsaufbau: entweder aus der Netzliste angestossen (das weiss
    // Network sofort) oder vom NetworkManager selbst (Autoconnect, meldet
    // `nmcli monitor`) – Geraetezustand "connecting (...)"
    property bool deviceConnecting: false
    property string deviceConnection: ""
    readonly property bool connecting: root.radioOn && (Network.connectingSsid !== "" || root.deviceConnecting)
    readonly property string connectingSsid: Network.connectingSsid !== "" ? Network.connectingSsid
                                                                           : root.deviceConnection

    // Gleiche Stufen wie frueher im Leisten-Symbol
    readonly property string signalIcon: !root.radioOn || !root.connected ? "wifi_off"
        : root.signal >= 80 ? "network_wifi"
        : root.signal >= 60 ? "network_wifi_3_bar"
        : root.signal >= 40 ? "network_wifi_2_bar"
        : root.signal >= 20 ? "network_wifi_1_bar"
        : "signal_wifi_0_bar"

    // Beim Verbinden laufen die Balken durch, wie beim Telefon – so sieht man
    // in der Leiste, dass etwas passiert
    readonly property var connectingIcons: ["signal_wifi_0_bar", "network_wifi_1_bar",
        "network_wifi_2_bar", "network_wifi_3_bar", "network_wifi"]
    property int connectingStep: 0
    readonly property string icon: root.connecting ? root.connectingIcons[root.connectingStep]
                                                   : root.signalIcon

    Timer {
        interval: 260
        running: root.connecting
        repeat: true
        onRunningChanged: root.connectingStep = 0
        onTriggered: root.connectingStep = (root.connectingStep + 1) % root.connectingIcons.length
    }

    // Ende eines Aufbaus aus der Liste: sofort nachlesen statt auf das
    // naechste Ereignis zu warten
    onConnectingChanged: if (!root.connecting && root.watching) root.refresh()

    function refresh(): void {
        if (poll.running)
            poll.again = true;
        else
            poll.running = true;
    }

    function setRadio(on: bool): void {
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        root.radioOn = on;   // optimistisch, der naechste Refresh korrigiert
        if (!on)
            root.connected = false;
        settle.restart();
    }

    onWatchingChanged: if (root.watching) root.refresh()

    // Funk + Verbindung + Empfang in einem Rutsch. LC_ALL=C, sonst meldet
    // nmcli ACTIVE auf Deutsch ("ja"/"nein").
    Process {
        id: poll

        property bool again: false

        command: ["sh", "-c",
            "export LC_ALL=C; if nmcli -t radio wifi | grep -q enabled; then " +
            "nmcli -t -f TYPE,STATE,CONNECTION device | sed -n 's/^wifi:/STATE /p'; " +
            "nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list --rescan no; " +
            "else echo OFF; fi"]

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                root.loaded = true;
                if (text === "OFF") {
                    root.radioOn = false;
                    root.connected = false;
                    root.deviceConnecting = false;
                    root.signal = 0;
                    return;
                }
                root.radioOn = true;
                let connecting = false;
                let connection = "";
                let found = false;
                for (const line of text.split("\n")) {
                    if (line.startsWith("STATE ")) {
                        const f = Network.splitTerse(line.slice(6));
                        if ((f[0] ?? "").startsWith("connecting")) {
                            connecting = true;
                            connection = f[1] ?? "";
                        }
                        continue;
                    }
                    const f = Network.splitTerse(line);
                    if (!found && f[0] === "yes") {
                        found = true;
                        root.ssid = f[1] ?? "";
                        root.signal = parseInt(f[2]) || 0;
                    }
                }
                root.deviceConnecting = connecting;
                root.deviceConnection = connection;
                root.connected = found;
                if (!found)
                    root.signal = 0;
            }
        }

        onExited: if (poll.again) {
            poll.again = false;
            poll.running = true;
        }
    }

    // Ereignisse statt Takt: jede Zeile heisst "irgendwas hat sich geaendert",
    // gesammelt wird kurz, weil ein Wechsel mehrere Zeilen auf einmal bringt
    Process {
        running: root.watching
        command: ["nmcli", "monitor"]

        stdout: SplitParser {
            onRead: settle.restart()
        }
    }

    Timer {
        id: settle

        interval: 400
        onTriggered: root.refresh()
    }

    // Empfang aendert sich ohne Ereignis – den langsam nachlesen
    Timer {
        interval: 15000
        running: root.watching && root.connected
        repeat: true
        onTriggered: root.refresh()
    }
}
