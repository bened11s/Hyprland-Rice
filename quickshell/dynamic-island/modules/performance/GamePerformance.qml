pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.services.system

Singleton {
    id: root

    // activeToplevel is not populated reliably for this Hyprland build/XWayland.
    // Query activewindow via IPC; invalidate immediately on focus events.
    property var focused: ({})
    readonly property int pid: focused.pid ?? 0
    readonly property string appClass: focused.class ?? ""
    readonly property string title: focused.title ?? ""
    readonly property string address: root.focused.address ?? ""
    property int generation: 0
    property var sample: ({})
    property string sampledAddress: ""
    readonly property bool current: root.sampledAddress === root.address && root.sample.pid === root.pid
    readonly property var metrics: root.current ? (root.sample.metrics ?? ({})) : ({})
    readonly property bool game: /^(steam_app_[0-9]+|gamescope)$/i.test(root.appClass)
        || (root.current && !!root.sample.game)
    readonly property bool shown: Config.performance.enabled && (!Config.performance.onlyGames || root.game)
    readonly property string status: root.current ? (root.sample.status ?? "Keine Messdaten") : "Warte auf Messdaten"

    // Reuse the shell's existing shared system poller, never one per monitor.
    DemandRequest {
        demand: SystemStats.demand
        active: root.shown && (Config.performance.cpu || Config.performance.gpu || Config.performance.ram
            || Config.performance.vram || Config.performance.temperatures)
    }

    function refresh(): void {
        if (!Config.performance.enabled || poll.running)
            return;
        poll.requestGeneration = root.generation;
        poll.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name !== "activewindowv2")
                return;
            root.generation++;
            root.focused = ({});
            root.sample = ({});
            if (Config.performance.enabled)
                Qt.callLater(root.refresh);
        }
    }

    Connections {
        target: Config.performance
        function onEnabledChanged(): void {
            root.sample = ({});
            root.generation++;
            if (Config.performance.enabled)
                root.refresh();
        }
    }

    Process {
        id: poll
        property int requestGeneration: 0
        command: ["python3", Quickshell.shellPath("modules/performance/telemetry.py")]
        onExited: (code) => {
            if (code !== 0) root.sample = ({});
            if (poll.requestGeneration !== root.generation)
                Qt.callLater(root.refresh);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (poll.requestGeneration === root.generation && Config.performance.enabled) {
                        root.focused = data.window ?? ({});
                        root.sample = data;
                        root.sampledAddress = root.address;
                    }
                } catch (e) {
                    root.sample = ({});
                }
            }
        }
    }

    Timer {
        interval: Math.max(250, Math.min(5000, Config.performance.interval))
        running: Config.performance.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    IpcHandler {
        target: "performance"
        function toggle(): void { Config.set("performance", "enabled", !Config.performance.enabled); }
        function status(): string {
            return JSON.stringify({ enabled: Config.performance.enabled, shown: root.shown,
                pid: root.pid, game: root.game, title: root.title, status: root.status,
                monitor: Hyprland.focusedMonitor?.name ?? "", metrics: root.metrics });
        }
    }

    function value(key: string, fallback: var): var {
        const v = root.metrics[key];
        return v !== undefined && v !== null && isFinite(v) ? v : fallback;
    }

    function entries(): var {
        const c = Config.performance;
        const entries = [];
        const fps = root.value("fps", null);
        if (c.title)
            entries.push({ label: root.title || "Kein Spiel fokussiert", accent: false, title: true });
        if (c.fps)
            entries.push({ label: fps === null ? "FPS —" : Math.round(fps) + " FPS", accent: true });
        if (c.frametime) {
            const ft = root.value("frametime", null);
            entries.push({ label: ft === null ? "FT —" : ft.toFixed(1) + " ms", accent: false });
        }
        const ready = SystemStats.loaded;
        if (c.cpu) {
            const cpu = root.value("cpu_load", ready ? SystemStats.cpuUsage * 100 : null);
            entries.push({ label: "CPU " + (cpu === null ? "—" : Math.round(cpu) + "%"), accent: false });
        }
        if (c.gpu) {
            const gpu = root.value("gpu_load", ready && SystemStats.hasGpu ? SystemStats.gpuUsage * 100 : null);
            entries.push({ label: "GPU " + (gpu === null ? "—" : Math.round(gpu) + "%"), accent: false });
        }
        if (c.temperatures) {
            const cpuT = root.value("cpu_temp", ready ? SystemStats.cpuTemp : null);
            const gpuT = root.value("gpu_temp", ready && SystemStats.hasGpu ? SystemStats.gpuTemp : null);
            entries.push({ label: "CPU " + (cpuT > 0 ? Math.round(cpuT) + "°C" : "—"), accent: false });
            entries.push({ label: "GPU " + (gpuT > 0 ? Math.round(gpuT) + "°C" : "—"), accent: false });
        }
        if (c.ram) {
            const ram = root.value("ram_used", ready ? SystemStats.memUsed / 1073741824 : null);
            entries.push({ label: "RAM " + (ram === null ? "—" : ram.toFixed(1) + " GiB"), accent: false });
        }
        if (c.vram) {
            const vram = root.value("gpu_vram_used", ready && SystemStats.hasGpu ? SystemStats.vramUsed / 1073741824 : null);
            entries.push({ label: "VRAM " + (vram === null ? "—" : vram.toFixed(1) + " GiB"), accent: false });
        }
        if (c.power) {
            const watts = root.value("gpu_power", null);
            entries.push({ label: "GPU " + (watts === null ? "— W" : watts.toFixed(0) + " W"), accent: false });
        }
        if (c.clock) {
            const clock = root.value("gpu_core_clock", null);
            entries.push({ label: clock === null ? "GPU — MHz" : Math.round(clock) + " MHz", accent: false });
        }
        if (c.source)
            entries.push({ label: fps === null ? root.status : "MangoHud · CPU/RAM: System gesamt", accent: false, title: true });
        if (!entries.length)
            entries.push({ label: "Performance · keine Anzeigen gewählt", accent: false });
        return entries;
    }
}
