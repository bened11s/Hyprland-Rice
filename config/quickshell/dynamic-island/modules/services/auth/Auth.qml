pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit

Singleton {
    id: root

    readonly property bool active: agent.isActive
    readonly property bool registered: agent.isRegistered
    readonly property alias flow: agent.flow
    property ShellScreen screen: null

    function focusedScreen(): ShellScreen {
        const name = Hyprland.focusedMonitor?.name ?? "";
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0] ?? null;
    }

    PolkitAgent {
        id: agent

        onAuthenticationRequestStarted: root.screen = root.focusedScreen()
        onIsActiveChanged: if (!isActive) root.screen = null
    }
}
