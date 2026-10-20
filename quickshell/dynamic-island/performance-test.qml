import Quickshell
import QtQuick
import Quickshell.Wayland
import qs.modules.services.config
import "modules/performance"
import "modules/bar/components/notch"

// Non-interactive layout smoke test; settings are changed in memory only.
ShellRoot {
    id: root
    property int testCase: 0
    property var cases: [[320, 24, false, false, true], [520, 13, true, false, true],
        [1000, 24, false, false, true], [1200, 10, true, false, true],
        [520, 13, true, true, true], [520, 13, true, false, false]]

    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const found = root.findItem(child, name);
            if (found) return found;
        }
        return null;
    }

    Variants {
        id: bars
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property ShellScreen modelData
            readonly property alias testNotch: notch
            screen: modelData
            visible: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            implicitWidth: modelData.width
            implicitHeight: modelData.height
            Item {
                width: win.width
                height: 40
                Notch {
                    id: notch
                    verticalMargin: 10
                    borderWidth: 1
                    borderColor: "white"
                    cardRadius: 20
                }
            }
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            Config.performance.enabled = true;
            Config.performance.onlyGames = false;
            Config.performance.temperatures = true;
            Config.performance.ram = true;
            Config.performance.vram = true;
            Config.performance.power = true;
            Config.performance.clock = true;
        }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (root.testCase > 0) {
                for (const win of bars.instances) {
                    const notch = win.testNotch;
                    const strip = root.findItem(notch, "islandPerformanceStrip");
                    const ai = root.findItem(notch, "notchCompactAiButton");
                    const cover = root.findItem(notch, "notchMusicCover");
                    console.log("TEST Island", root.testCase, win.modelData.name,
                        notch.performanceActive, notch.width, notch.height, notch.open);
                    if (notch.width > win.modelData.width || notch.height > win.modelData.height
                        || notch.height < 30 || notch.width < 140)
                        throw new Error("Bad Island geometry");
                    if (!strip || strip.visible !== (notch.performanceActive && !notch.open))
                        throw new Error("Strip visibility mismatch");
                    if (ai?.visible) {
                        const aiAt = ai.mapToItem(notch, 0, 0);
                        const clockAt = notch.clock.mapToItem(notch, 0, 0);
                        if (aiAt.x < clockAt.x + notch.clock.width)
                            throw new Error("KI button overlaps clock");
                    }
                    if (strip.visible) {
                        const stripAt = strip.mapToItem(notch, 0, 0);
                        const clockAt = notch.clock.mapToItem(notch, 0, 0);
                        if (stripAt.x + strip.width > clockAt.x || strip.width < 1)
                            throw new Error("FPS strip is not left of clock");
                        if (Math.abs(stripAt.y + strip.height / 2 - clockAt.y - notch.clock.height / 2) > 1)
                            throw new Error("FPS strip is not vertically aligned with clock");
                        if (cover?.visible && cover.mapToItem(notch, 0, 0).x + cover.width > stripAt.x)
                            throw new Error("FPS strip overlaps music cover");
                    }
                }
            }
            if (root.testCase === root.cases.length) {
                console.log("TEST status", GamePerformance.pid, GamePerformance.appClass);
                Qt.quit();
                return;
            }
            const spec = root.cases[root.testCase++];
            Config.performance.maxWidth = spec[0];
            Config.performance.fontSize = spec[1];
            Config.performance.compact = spec[2];
            Config.performance.enabled = spec[4];
            for (const win of bars.instances)
                win.testNotch.expanded = spec[3];
        }
    }
}
