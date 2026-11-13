local scheme = require("scheme.current")
local pick = require("apps")

return {
    ------------------
    ---- HYPRLAND ----
    ------------------

    -- Apps: die erste installierte gewinnt (apps.lua), vorne steht meine Wahl
    terminal = pick({ "kitty", "alacritty", "foot", "wezterm", "ghostty", "konsole", "gnome-terminal", "xfce4-terminal", "xterm" }),
    browser = pick({ "zen-browser", "firefox", "librewolf", "brave", "chromium", "google-chrome-stable", "vivaldi-stable" }),
    editor = pick({ "codium", "code", "zed", "kate", "gnome-text-editor", "mousepad" }),
    fileExplorer = pick({ "dolphin", "nautilus", "thunar", "nemo", "pcmanfm-qt", "pcmanfm" }),
    audioSettings = pick({ "pavucontrol", "pwvucontrol", "pavucontrol-qt" }),

    -- Touchpad
    touchpadDisableTyping = true,
    touchpadScrollFactor = 0.3,
    gestureFingers = 3,
    workspaceSwipeFingers = 4,
    gestureFingersMore = 4,

    -- Blur
    blurEnabled = true,
    blurSpecialWs = false,
    blurPopups = true,
    blurInputMethods = true,
    blurSize = 4,
    blurPasses = 2,
    blurXray = false,

    -- Shadow
    shadowEnabled = true,
    shadowRange = 15,
    shadowRenderPower = 4,
    shadowColour = "rgba(" .. scheme.inversePrimary .. "10)",

    -- Gaps
    workspaceGaps = 20,
    windowGapsIn = 5,
    windowGapsOut = 10,
    singleWindowGapsOut = 20,

    -- Window styling
    activeWindowOpacity = 0.85,
    inActiveWindowOpacity = 0.65,
    windowRounding = 15,
    windowBorderSize = 1,
    activeWindowBorderColour = "rgba(" .. scheme.primary .. "e6)",
    inactiveWindowBorderColour = "rgba(" .. scheme.onSurfaceVariant .. "11)",

    -- Misc
    volumeStep = 10,
    volumeMax = 100,
    cursorTheme = "breeze_cursors",
    cursorSize = 24,
    -- ohne eingerichtete Hibernation scheitert suspend-then-hibernate -> nur Standby
    sleepGestureCmd = "systemctl suspend-then-hibernate || systemctl suspend",

    ------------------
    ---- KEYBINDS ----
    ------------------

    kbMoveWinToWs = "SUPER + ALT",
    kbMoveWinToWsGroup = "CTRL + SUPER + ALT",
    kbGoToWs = "SUPER",
    kbGoToWsGroup = "CTRL + SUPER",
    kbNextWs = "CTRL + SUPER + Right",
    kbPrevWs = "CTRL + SUPER + Left",

    -- Window Group
    kbWindowGroupCycleNext = "ALT + TAB",
    kbWindowGroupCyclePrev = "SHIFT + ALT + TAB",
    kbUngroup = "SUPER + U",
    kbToggleGroup = "SUPER + Comma",

    -- Window Action
    kbMoveWindow = "SUPER + mouse:272",
    kbResizeWindow = "SUPER + mouse:271",
    kbWindowPip = "SUPER + ALT + backslash",
    kbPinWindow = "SUPER + P",
    kbWindowFullscreen = "SUPER + F",
    kbWindowBorderedFullscreen = "SUPER + ALT + F",
    kbToggleWindowFloating = "SUPER + ALT + space",
    kbCloseWindow = "SUPER + C",

    -- Special workspaces toggles
    kbSpecialWs = "SUPER + S",
    kbSystemMonitorWs = "CTRL + SHIFT + Escape",
    kbMusicWs = "SUPER + M",
    kbCommunicationWs = "SUPER + D",
    kbTodoWs = "SUPER + R",

    -- Apps
    kbTerminal = "SUPER + Q",
    kbBrowser = "SUPER + W",
    kbEditor = "SUPER + P",
    kbFileExplorer = "SUPER + E",

    -- Misc
    kbSession = "CTRL + ALT + Delete",
    kbShowSidebar = "SUPER + N",
    kbClearNotifs = "CTRL + ALT + C",
    kbShowPanels = "SUPER + K",
    kbLock = "SUPER + L",
    kbRestoreLock = "SUPER + ALT + L",
}
