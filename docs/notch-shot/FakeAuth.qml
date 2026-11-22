pragma Singleton
import QtQuick
import Quickshell

// Ersetzt in der Harness-Kopie services/auth/Auth.qml (STATE=auth[:failed|:root|:long]):
// immer aktiv, screen null wie LauncherState in der Harness.
Singleton {
    readonly property string variant: (Quickshell.env("STATE") || "").split(":")[1] ?? ""
    readonly property bool active: true
    readonly property bool registered: true
    property ShellScreen screen: null
    // Panel entsteht erst nach dem Harness-Start → Fehlschlag spaeter ausloesen
    Timer {
        interval: 3000
        running: variant === "failed"
        onTriggered: flow.authenticationFailed()
    }

    readonly property QtObject flow: QtObject {
        signal authenticationFailed()
        readonly property string message: variant === "long"
            ? "Authentication is needed to run `/usr/bin/pacman -Syu --noconfirm --needed linux-cachyos linux-cachyos-headers /home/gamecat/.cache/paru/clone/quickshell-git/quickshell-git-0.2.1.r412.g3f9e2a1-1-x86_64.pkg.tar.zst` as the super user"
            : "Authentication is needed to run `/usr/bin/true' as the super user"
        readonly property bool isResponseRequired: true
        readonly property string inputPrompt: "Password: "
        readonly property bool responseVisible: false
        readonly property string supplementaryMessage: ""
        readonly property bool supplementaryIsError: false
        readonly property var selectedIdentity: (variant === "root" || variant === "long")
            ? ({ displayName: "root", string: "unix-user:root" })
            : ({ displayName: Quickshell.env("USER"), string: "unix-user:" + Quickshell.env("USER") })
        function submit(t) {}
        function cancelAuthenticationRequest() {}
    }
}
