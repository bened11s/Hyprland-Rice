pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.UPower

import qs

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
// Benutzung:  import qs.modules.services.system
Singleton {
    id: root

    readonly property bool hasSystemBattery: UPower.displayDevice?.isLaptopBattery ?? false

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

        out.sort((a, b) => a.percentage - b.percentage);   // schwaechster zuerst
        return out;
    }

    // Was die Pille zeigt: der Systemakku, sonst der schwaechste Geraete-Akku
    readonly property var shown: root.hasSystemBattery ? UPower.displayDevice
                                                       : (root.deviceBatteries[0] ?? null)
    readonly property bool hasBattery: root.shown !== null
    readonly property int percent: Math.round((root.shown?.percentage ?? 0) * 100)
    readonly property bool activelyCharging: root.hasSystemBattery
        && UPower.displayDevice.state === UPowerDeviceState.Charging
    // UPower meldet die momentane Energieaenderung in Watt.
    readonly property real chargeRate: root.activelyCharging
        ? Math.max(0, UPower.displayDevice.changeRate ?? 0) : 0
    readonly property bool charging: {
        const s = root.shown?.state ?? UPowerDeviceState.Unknown;
        return s === UPowerDeviceState.Charging || s === UPowerDeviceState.FullyCharged
            || s === UPowerDeviceState.PendingCharge;
    }

    // Symbol fuer den Akkustand; geladen hat eine eigene Reihe
    readonly property string batteryIcon: {
        if (!root.hasBattery)
            return "battery_unknown";
        const step = Math.max(0, Math.min(6, Math.floor(root.percent / 100 * 7)));
        if (root.charging) {
            // Material Symbols hat keine gleichmaessigen 10er-Stufen; Namen
            // wie battery_charging_40 werden sonst als Klartext dargestellt.
            const levels = [20, 30, 50, 60, 80, 90];
            return step >= 6 ? "battery_charging_full" : `battery_charging_${levels[step]}`;
        }
        return step >= 6 ? "battery_full" : `battery_${step}_bar`;
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
