pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

import qs
import qs.modules.services.config

// Akku und Energieprofile.
//
// Beides kommt fertig aus Quickshell (Quickshell.Services.UPower) – weder
// `upower` noch `powerprofilesctl` muessen aufgerufen werden, `profile` ist
// sogar schreibbar.
//
// Zwei Fallen stecken in der UPower-API:
//   * `percentage` ist 0…1, nicht 0…100.
//   * Ohne Systemakku gibt es das `displayDevice` trotzdem – hier mit Typ
//     "unknown" und 0 %. Der richtige Test ist `isLaptopBattery`, nicht die
//     Prozentzahl.
//
// Dazu kommen Akkus, die UPower nicht kennt (extraBatteries): das Handy ueber
// KDE Connect und das Arctis-Headset samt Ersatzakku ueber den novabase-
// Daemon. Sie sehen aus wie UPower-Geraete (model, type, percentage, state,
// isPresent), sind aber einfache Objekte – neu je Abfrage, jede Minute.
// upowerd zeichnet sie nicht auf, deshalb schreibt Power ihren Verlauf selbst
// (~/.local/state/dynamic-island/battery-history, Format wie upowerd).
//
// Warnungen (battery.warnLow/warnCritical) und die Meldung "voll geladen"
// gelten fuer alle Geraete, einmal je Entladung bzw. Ladung.
//
// Benutzung:  import qs.modules.services.system
Singleton {
    id: root

    readonly property bool hasSystemBattery: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property var systemDevice: root.hasSystemBattery ? UPower.displayDevice : null

    // Laedt oder haengt am Kabel (voll zaehlt mit)
    function isCharging(device: var): bool {
        const s = device?.state ?? UPowerDeviceState.Unknown;
        return s === UPowerDeviceState.Charging || s === UPowerDeviceState.FullyCharged
            || s === UPowerDeviceState.PendingCharge;
    }

    // Akkus in Geraeten (Maus, Tastatur, Headset ...) – am Desktop das
    // einzige, was es zu zeigen gibt
    readonly property var deviceBatteries: {
        const wanted = [UPowerDeviceType.Mouse, UPowerDeviceType.Keyboard, UPowerDeviceType.Headset,
            UPowerDeviceType.Headphones, UPowerDeviceType.GamingInput, UPowerDeviceType.Pen,
            UPowerDeviceType.Tablet, UPowerDeviceType.Speakers];

        const out = [];
        for (const d of UPower.devices?.values ?? [])
            if (d?.isPresent && wanted.includes(d.type))
                out.push(d);
        // Zusatzquellen, ausser UPower kennt das Geraet schon (Handy per
        // Bluetooth und KDE Connect zugleich)
        const known = out.map(d => d.model);
        for (const e of root.extraBatteries)
            if (!known.includes(e.model))
                out.push(e);

        out.sort((a, b) => a.percentage - b.percentage);   // schwaechster zuerst
        return out;
    }

    // Schluessel eines Akkus fuer die Einstellung bar.batteryDevice. UPower
    // kennt keine Seriennummer; das Modell ueberlebt Neuverbindungen,
    // hidpp_battery_N dagegen zaehlt bei jedem Einstecken hoch.
    function deviceKey(device: var): string {
        return device?.model || device?.nativePath || "";
    }

    // Welcher Akku angezeigt wird (bar.batteryDevice):
    //   "auto"    Systemakku, sonst der schwaechste Geraete-Akku
    //   "system"  nur der Systemakku
    //   Modell    genau dieses Geraet ("Logitech G502 X PLUS")
    // Fehlt das gewaehlte Geraet (Maus aus), zeigt die Leiste gar keinen
    // Akku – ein anderer Wert unter demselben Symbol waere irrefuehrend.
    readonly property string target: Config.bar.batteryDevice || "auto"
    readonly property var shown: {
        // Automatisch nur unter den UPower-Geraeten: Handy und Ersatzakku
        // gehoeren nicht ungefragt in die Leiste
        if (root.target === "auto")
            return root.hasSystemBattery ? UPower.displayDevice
                                         : (root.deviceBatteries.find(d => !d.extra) ?? null);
        if (root.target === "system")
            return root.hasSystemBattery ? UPower.displayDevice : null;
        return root.deviceBatteries.find(d => root.deviceKey(d) === root.target) ?? null;
    }
    readonly property bool hasBattery: root.shown !== null
    // Zeigt die Anzeige den Systemakku oder ein Geraet (dann gehoert das
    // Geraetesymbol dazu)?
    readonly property bool showsSystem: root.hasBattery && root.shown === UPower.displayDevice

    // Auswahl fuer das Einstellungs-Menue (Config.meta source "batteries"):
    // Automatisch, Systemakku und alle Geraete, alphabetisch – nach Ladestand
    // sortiert sprangen die Chips bei jeder Aenderung umher
    readonly property var targetChoices: {
        const devices = root.deviceBatteries.map(d => root.deviceKey(d)).filter(k => k !== "");
        return ["auto"].concat(root.hasSystemBattery ? ["system"] : [],
                               [...new Set(devices)].sort((a, b) => a.localeCompare(b)));
    }
    readonly property var targetLabels: ({
        "auto": I18n.tr("Automatisch"),
        "system": I18n.tr("Systemakku")
    })

    readonly property int percent: Math.round((root.shown?.percentage ?? 0) * 100)
    readonly property bool activelyCharging: root.hasBattery
        && root.shown.state === UPowerDeviceState.Charging
    // UPower meldet die momentane Energieaenderung in Watt.
    readonly property real chargeRate: root.activelyCharging
        ? Math.max(0, root.shown.changeRate ?? 0) : 0
    readonly property bool charging: root.isCharging(root.shown)

    // Stufen, nach denen sich Farbe und Warnung richten. Am Kabel ist nichts
    // knapp – auch nicht, wenn ein Geraet dabei Unsinn meldet (die G915
    // sagt "fully-charged" bei 12 %).
    //   kritisch  unter 10 %   rot, Warnung
    //   knapp     bis 20 %     Mischton, Warnung
    readonly property bool critical: root.hasBattery && !root.charging && root.percent < 10
    readonly property bool low: root.hasBattery && !root.charging && root.percent <= 20

    // Material-Symbol fuer den Akkustand (fuer Stellen, die nur Symbole
    // setzen; sonst BatteryGlyph). Die Stufen sind ungleich breit: unten
    // fein, damit "fast leer" frueh zu sehen ist, oben grob.
    readonly property string batteryIcon: {
        if (!root.hasBattery)
            return "battery_unknown";
        const p = root.percent;
        if (root.charging) {
            // Material Symbols hat nur diese Ladestufen; Namen wie
            // battery_charging_40 erscheinen sonst als Klartext.
            const steps = [[95, "full"], [85, "90"], [70, "80"], [55, "60"], [40, "50"], [25, "30"]];
            const hit = steps.find(s => p >= s[0]);
            return `battery_charging_${hit ? hit[1] : "20"}`;
        }
        const steps = [[95, "full"], [80, "6_bar"], [65, "5_bar"], [50, "4_bar"],
                       [35, "3_bar"], [20, "2_bar"], [10, "1_bar"], [5, "0_bar"]];
        const hit = steps.find(s => p >= s[0]);
        return hit ? `battery_${hit[1]}` : "battery_alert";
    }

    // Womit der Akku steckt – am Desktop sagt "Maus" mehr als ein Akku-Symbol
    function deviceIcon(device: var): string {
        switch (device?.type ?? UPowerDeviceType.Unknown) {
        case UPowerDeviceType.Mouse:
            return "mouse";
        case UPowerDeviceType.Keyboard:
            return "keyboard";
        case UPowerDeviceType.Headset:
        case UPowerDeviceType.Headphones:
            return "headphones";
        case UPowerDeviceType.GamingInput:
            return "sports_esports";
        case UPowerDeviceType.Phone:
            return "smartphone";
        default:
            return "battery_full";
        }
    }

    function deviceName(device: var): string {
        const model = device?.model ?? "";
        if (model !== "")
            return model;
        return UPowerDeviceType.toString(device?.type ?? UPowerDeviceType.Unknown);
    }

    // ---- Zusatzquellen (KDE Connect, novabase) ----
    property var extraBatteries: []
    readonly property bool extrasWanted: Config.battery.kdeconnect || Config.battery.novabase
    readonly property string novabasePython: Quickshell.env("HOME") + "/projects/novabase/.venv/bin/python"

    onExtrasWantedChanged: if (!root.extrasWanted) root.extraBatteries = []

    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: root.extrasWanted
        onTriggered: if (!extraPoll.running) extraPoll.running = true
    }

    // Eine Zeile je Akku: Quelle<TAB>ID<TAB>Name<TAB>Art<TAB>Prozent<TAB>laedt
    // (novabase liefert sein JSON in einer Zeile, ausgewertet wird hier)
    Process {
        id: extraPoll

        command: ["sh", "-c",
            'if [ "$1" = 1 ] && command -v qdbus6 >/dev/null; then'
            // kdeconnectd startet unter Hyprland nicht von selbst (kein
            // XDG-Autostart) und beendet sich gelegentlich; qdbus6 aktiviert
            // nicht, also hier per D-Bus wecken (laeuft er, passiert nichts)
            + '  qdbus6 org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.StartServiceByName org.kde.kdeconnect 0 >/dev/null 2>&1;'
            + '  for d in $(qdbus6 org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices true true 2>/dev/null); do'
            + '    p=/modules/kdeconnect/devices/$d;'
            + '    c=$(qdbus6 org.kde.kdeconnect $p/battery org.kde.kdeconnect.device.battery.charge 2>/dev/null) || continue;'
            + '    printf "K\\t%s\\t%s\\t%s\\t%s\\t%s\\n" "$d"'
            + '      "$(qdbus6 org.kde.kdeconnect $p org.kde.kdeconnect.device.name)"'
            + '      "$(qdbus6 org.kde.kdeconnect $p org.kde.kdeconnect.device.type)" "$c"'
            + '      "$(qdbus6 org.kde.kdeconnect $p/battery org.kde.kdeconnect.device.battery.isCharging)";'
            + '  done;'
            + ' fi;'
            + ' if [ "$2" = 1 ] && [ -x "$3" ] && systemctl --user -q is-active novabase; then'
            + '   printf "N\\t%s\\n" "$(cd "$HOME/projects/novabase" && "$3" -m novabase get 2>/dev/null | tr -d "\\n")";'
            + ' fi',
            "sh", Config.battery.kdeconnect ? "1" : "0", Config.battery.novabase ? "1" : "0", root.novabasePython]

        stdout: StdioCollector {
            onStreamFinished: root.extraBatteries = root.parseExtras(text)
        }
    }

    function extra(id: string, model: string, type: int, percent: real, state: int): var {
        return { extra: true, nativePath: id, model, type, percentage: Math.max(0, Math.min(1, percent / 100)),
                 state, isPresent: true, changeRate: 0 };
    }

    function parseExtras(text: string): var {
        const out = [];
        for (const line of text.split("\n")) {
            const cols = line.split("\t");
            if (cols[0] === "K" && cols.length >= 6) {
                const charge = Number(cols[4]);
                if (!(charge >= 0))
                    continue;
                out.push(root.extra(`kdeconnect:${cols[1]}`, cols[2],
                    cols[3] === "tablet" ? UPowerDeviceType.Tablet
                    : cols[3] === "phone" ? UPowerDeviceType.Phone : UPowerDeviceType.Battery, charge,
                    cols[5] === "true" ? (charge >= 100 ? UPowerDeviceState.FullyCharged : UPowerDeviceState.Charging)
                                       : UPowerDeviceState.Discharging));
            } else if (cols[0] === "N" && cols.length >= 2) {
                let st;
                try {
                    st = JSON.parse(cols[1]);
                } catch (e) {
                    continue;
                }
                if (!st?.connected)
                    continue;
                // Headset nur, wenn es eingeschaltet ist; der Ersatzakku
                // steckt immer in der Basis und laedt dort
                if (st["headset.status"] === "online" && st["battery.headset"] !== undefined) {
                    const c = st["battery.charging"];
                    out.push(root.extra("novabase:headset", "Arctis Nova Pro", UPowerDeviceType.Headset, st["battery.headset"],
                        c === "charging" ? UPowerDeviceState.Charging
                        : c === "charged" ? UPowerDeviceState.FullyCharged
                        : UPowerDeviceState.Discharging));
                }
                if (st["battery.spare"] !== undefined) {
                    const spare = root.extra("novabase:spare", "Arctis Nova Pro Ersatzakku", UPowerDeviceType.Battery,
                        st["battery.spare"], st["battery.spare"] >= 100 ? UPowerDeviceState.FullyCharged : UPowerDeviceState.Charging);
                    spare.spare = true;
                    out.push(spare);
                }
            }
        }
        root.recordExtras(out);
        for (const d of out)
            root.checkWarnings(d);
        return out;
    }

    // ---- Verlauf der Zusatzquellen ----
    // Je Geraet eine Datei wie bei upowerd ("Zeit<TAB>Wert<TAB>Zustand",
    // Dezimalkomma), geschrieben bei jeder Aenderung. Ein Geraet, das in der
    // letzten Abfrage fehlte, bekommt vorher die Lueckenmarke "0,000 unknown".
    readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/dynamic-island/battery-history"
    property var recorded: ({})

    function stateName(state: int): string {
        return state === UPowerDeviceState.Charging ? "charging"
             : state === UPowerDeviceState.FullyCharged ? "fully-charged"
             : "discharging";
    }

    function recordExtras(list: var): void {
        const now = Math.floor(Date.now() / 1000);
        const seen = {};
        for (const d of list) {
            const v = Math.round(d.percentage * 100);
            const state = root.stateName(d.state);
            const last = root.recorded[d.nativePath];
            seen[d.nativePath] = { v, state };
            if (last && last.v === v && last.state === state)
                continue;
            // Name ohne Leer- und Bindestriche: BatteryHistory haelt den Teil
            // nach dem letzten "-" sonst fuer eine Seriennummer
            const file = `history-charge-${d.model.replace(/[\s\-\/]+/g, "_")}.dat`;
            const lines = (last ? "" : `${now}\t0,000\tunknown\n`) + `${now}\t${v},000\t${state}\n`;
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s" "$2" >> "$1/$3"',
                "sh", root.historyDir, lines, file]);
        }
        root.recorded = seen;
    }

    // ---- Warnungen ----
    // Je Geraet: { low, critical, full } schon gemeldet? Beim ersten Blick auf
    // ein Geraet wird nur der Zustand gemerkt – sonst kaeme bei jedem
    // Shell-Start eine Meldung fuer die Tastatur, die eh bei 12 % steht.
    property var warned: ({})

    function checkWarnings(device: var): void {
        if (!device || device.spare)
            return;
        const key = device.nativePath || device.model;
        const p = Math.round(device.percentage * 100);
        const charging = root.isCharging(device);
        const low = Config.battery.warnLow;
        const critical = Config.battery.warnCritical;
        const name = device.isLaptopBattery ? I18n.tr("Akku") : (device.model || I18n.tr("Akku"));

        let st = root.warned[key];
        if (!st) {
            root.warned[key] = { low: p <= low, critical: p <= critical, full: charging && p >= 100 };
            return;
        }
        if (charging) {
            st.low = false;
            st.critical = false;
            if (p >= 100 && !st.full) {
                st.full = true;
                if (Config.battery.notifyFull)
                    root.notify(name, I18n.tr("Voll geladen – das Kabel kann ab"), "battery-full-charged", "normal");
            }
            return;
        }
        st.full = false;
        if (p > low + 5)
            st.low = false;
        if (p > critical + 3)
            st.critical = false;
        if (critical > 0 && p <= critical && !st.critical) {
            st.critical = true;
            st.low = true;
            root.notify(name, I18n.tr("Akku fast leer: %1 %").arg(p), "battery-empty", "critical");
        } else if (low > 0 && p <= low && !st.low) {
            st.low = true;
            root.notify(name, I18n.tr("Akku schwach: %1 %").arg(p), "battery-caution", "normal");
        }
    }

    function notify(title: string, body: string, icon: string, urgency: string): void {
        Quickshell.execDetached(["notify-send", "-a", I18n.tr("Akku"), "-i", icon, "-u", urgency, title, body]);
    }

    // UPower-Geraete melden Aenderungen selbst
    Instantiator {
        model: UPower.devices

        delegate: QtObject {
            id: watch

            required property var modelData

            function check(): void {
                const d = watch.modelData;
                if (d?.isPresent && (d.isLaptopBattery || root.deviceBatteries.includes(d)))
                    root.checkWarnings(d);
            }

            readonly property Connections conn: Connections {
                target: watch.modelData

                function onPercentageChanged(): void {
                    watch.check();
                }

                function onStateChanged(): void {
                    watch.check();
                }
            }

            Component.onCompleted: watch.check()
        }
    }

    // ---- Energieprofile ----
    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property bool degraded: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
    readonly property string degradedReason: PerformanceDegradationReason.toString(PowerProfiles.degradationReason)

    readonly property var profiles: [
        { value: PowerProfile.PowerSaver, icon: "energy_savings_leaf", label: I18n.tr("Sparen") },
        { value: PowerProfile.Balanced, icon: "balance", label: I18n.tr("Ausgewogen") },
        { value: PowerProfile.Performance, icon: "rocket_launch", label: I18n.tr("Leistung") }
    ]

    function setProfile(value: int): void {
        PowerProfiles.profile = value;
    }
}
