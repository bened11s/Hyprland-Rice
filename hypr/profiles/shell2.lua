-- Profil "shell2" — dieselbe schlanke Hyprland-Config wie "simple", aber mit
-- der neuen Shell "shell2" statt dynamic-island.
--
-- Diese Datei ist als Kopie von simple.lua entstanden und bleibt bewusst eine
-- eigene Kopie: am neuen Profil wird geschraubt, waehrend simple.lua das
-- funktionierende Rueckfallprofil bleibt.
--
-- Die Shell liegt in einem eigenen Repo:
--   ~/projects/shell2                      hier wird gearbeitet (github.com/Gamecat-HD/shell2)
--   ~/.config/quickshell/shell2            Symlink dorthin, darueber findet qs sie
--   ~/.config/shell2/shell.json            Einstellungen, pro Rechner
--
-- Ihr Name steht NICHT hier, sondern in ~/.local/bin/hypr-profile (Tabelle
-- PROFILE_SHELL oben im Script); Autostart und die Shell-Keybinds unten rufen
-- nur dieses Script auf, damit es genau eine Stelle gibt, die weiss welche
-- Shell zu welchem Profil gehoert.
--
-- Was die Shell (noch) nicht abdeckt und dieses Profil deshalb nicht hat:
-- Notifications, OSDs fuer Lautstaerke/Helligkeit, Sidebar, Launcher-Overlay.
-- Launcher = fuzzel, Lockscreen = hyprlock.
--
-- Umschalten: hypr-profile shell2   (oder CTRL + SUPER + SHIFT + P durchschalten)

local home = os.getenv("HOME")
local hyprProfile = home .. "/.local/bin/hypr-profile"

--------------------------------------------------------------------------------
-- Farben
--------------------------------------------------------------------------------
-- Nimmt das aktive Schema (scheme/current.lua, wird von `dynamic-island scheme`/
-- `dynamic-island wallpaper` bzw. `theme-set` geschrieben). Fehlt es, greift die eingebaute Palette.
local fallback = {
	primary = "0ED2FC",
	onPrimary = "000A0F",
	secondary = "0372DC",
	outline = "3A5561",
	onSurfaceVariant = "A9C2CC",
	surfaceContainer = "0B1F29",
	inversePrimary = "036B85",
}

local ok, scheme = pcall(require, "scheme.current")
if not ok or type(scheme) ~= "table" then
	scheme = fallback
end
local function colour(key)
	return scheme[key] or fallback[key] or "888888"
end

--------------------------------------------------------------------------------
-- Die wichtigsten Einstellungen
--------------------------------------------------------------------------------
local cfg = {
	-- Apps
	terminal = "kitty",
	browser = "zen-browser",
	editor = "codium",
	fileExplorer = "dolphin",
	audioSettings = "pavucontrol",
	launcher = "fuzzel",
	-- Sperrbildschirm (SUPER + L): die eigene Config, ~/.config/hypr/hyprlock.conf.
	-- Layout 12 aus Hyprlock-Dots liegt weiterhin unter ~/.config/hyprlock.
	-- Wieder darauf umstellen:
	--   lockCmd = "hyprlock -c " .. home .. "/.config/hyprlock/layout12.conf"
	-- oder mit vorher gebautem Hintergrund (unscharfe Spalte links):
	--   lockCmd = home .. "/.config/hyprlock/scripts/lock.sh"
	lockCmd = "hyprlock",

	-- Tastatur / Maus
	kbLayout = "de",
	repeatDelay = 250,
	repeatRate = 35,
	cursorTheme = "breeze_cursors",
	cursorSize = 24,

	-- Layout / Abstaende
	layout = "dwindle",
	windowGapsIn = 5,
	windowGapsOut = 10,
	-- Notch-Optik: Die Notch (30px) haengt zentriert in der 50px-Bar -> 10px Luft
	-- ober- und unterhalb. Der Top-Gap muss 0 sein, damit der Abstand zum Fenster
	-- genau diesen 10px entspricht und nicht 10+Gap.
	windowGapsOutTop = 0,
	singleWindowGapsOut = 20,
	singleWindowGapsOutTop = 0, -- wie windowGapsOutTop: Notch-Symmetrie
	workspaceGaps = 20,
	windowBorderSize = 1,
	windowRounding = 15,

	-- Optik
	activeWindowOpacity = 0.85,
	inActiveWindowOpacity = 0.60,
	blurEnabled = true,
	blurSize = 4,
	blurPasses = 2,
	shadowEnabled = false,
	shadowRange = 15,

	-- Schritte fuer Lautstaerke / Helligkeit
	volumeStep = 10,
	volumeMax = 100,
	brightnessStep = 5,

	-- Energie
	sleepCmd = "systemctl suspend-then-hibernate",

	-- Workspaces: jeder Monitor hat seine eigene 10er-Gruppe (Anzeige jeweils 1-10)
	wsMonitorOffset = {
		["HDMI-A-1"] = 0, -- links:  Workspaces 1-10
		["DP-2"] = 10, -- rechts: Workspaces 11-20
	},
}

--------------------------------------------------------------------------------
-- Umgebungsvariablen
--------------------------------------------------------------------------------
hl.env("QT_QPA_PLATFORMTHEME", "kde") -- Qt-Apps folgen ~/.config/kdeglobals
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("XCURSOR_THEME", cfg.cursorTheme)
hl.env("XCURSOR_SIZE", cfg.cursorSize)

hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland,x11,windows")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")

--------------------------------------------------------------------------------
-- Basis-Config
--------------------------------------------------------------------------------
hl.config({
	general = {
		layout = cfg.layout,
		gaps_in = cfg.windowGapsIn,
		gaps_out = {
			top = cfg.windowGapsOutTop,
			right = cfg.windowGapsOut,
			bottom = cfg.windowGapsOut,
			left = cfg.windowGapsOut,
		},
		gaps_workspaces = cfg.workspaceGaps,
		border_size = cfg.windowBorderSize,
		allow_tearing = false,
		col = {
			active_border = "rgba(" .. colour("primary") .. "e6)",
			inactive_border = "rgba(" .. colour("onSurfaceVariant") .. "11)",
		},
	},

	dwindle = {
		preserve_split = true,
		smart_resizing = true,
	},

	decoration = {
		rounding = cfg.windowRounding,
		blur = {
			enabled = cfg.blurEnabled,
			size = cfg.blurSize,
			passes = cfg.blurPasses,
			ignore_opacity = true,
			new_optimizations = true,
			popups = true,
		},
		shadow = {
			enabled = cfg.shadowEnabled,
			range = cfg.shadowRange,
			color = "rgba(" .. colour("inversePrimary") .. "10)",
		},
	},

	animations = {
		enabled = true,
	},

	input = {
		kb_layout = cfg.kbLayout,
		numlock_by_default = true,
		repeat_delay = cfg.repeatDelay,
		repeat_rate = cfg.repeatRate,
		follow_mouse = 1,
		touchpad = {
			natural_scroll = true,
			disable_while_typing = true,
			scroll_factor = 0.3,
		},
	},

	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		force_default_wallpaper = 0,
		focus_on_activate = true,
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,
		-- Stirbt hyprlock ab, waehrend die Session gesperrt ist, bleibt der
		-- Compositor sonst unbedienbar zurueck ("lockdead") -- Rettung nur noch
		-- ueber ein TTY. Mit dieser Option genuegt ein erneutes `hyprlock`.
		allow_session_lock_restore = true,
		-- Farbe hinter allem. Das Wallpaper zeichnet die Shell (Layer
		-- shell2-background); laeuft keine Shell, bleibt diese Farbe stehen.
		background_color = "rgb(" .. colour("surfaceContainer") .. ")",
	},

	gestures = {
		workspace_swipe_distance = 700,
		workspace_swipe_cancel_ratio = 0.15,
		workspace_swipe_direction_lock = true,
	},
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "special" })

--------------------------------------------------------------------------------
-- Fenster-Regeln (nur das Noetigste)
--------------------------------------------------------------------------------
-- Transparenz fuer normale Fenster
hl.window_rule({
	match = { fullscreen = false },
	opacity = cfg.activeWindowOpacity .. " " .. cfg.inActiveWindowOpacity .. " override",
})

-- Terminals, Bild-/Grafik-Apps und Spiele bleiben deckend
hl.window_rule({
	match = {
		class = "kitty|foot|imv|swappy|krita|gimp|inkscape|blender|kdenlive|zen|firefox|"
			.. "(steam_app_(default|[0-9]+))|gamescope",
	},
	opaque = true,
})

-- Dialoge floaten und mittig
hl.window_rule({ match = { float = true, xwayland = false }, center = true })
hl.window_rule({
	match = {
		title = "(Select|Open)( a)? (File|Folder)(s)?|File (Operation|Upload)( Progress)?|"
			.. ".* Properties|Save As|Library",
	},
	float = true,
})
hl.window_rule({
	match = { class = "yad|zenity|blueman-manager|org.pulseaudio.pavucontrol|feh|imv|org.quickshell" },
	float = true,
})

-- Spiele: kein Tearing-Limit, kein Idle
hl.window_rule({
	match = { class = "(steam_app_(default|[0-9]+))|gamescope" },
	immediate = true,
	idle_inhibit = "always",
})

-- Picture-in-Picture: klein, unten rechts, immer sichtbar
hl.window_rule({
	match = { title = "Picture(-| )in(-| )[Pp]icture" },
	float = true,
	pin = true,
	keep_aspect_ratio = true,
	move = "(monitor_w*0.98-window_w) (monitor_h*0.97-window_h)",
})

-- Feste Plaetze auf den Special-Workspaces (Binds siehe unten)
hl.window_rule({ match = { class = "btop" }, workspace = "special:sysmon" })
hl.window_rule({
	match = { class = "feishin|Spotify|Supersonic|Cider|com.github.th_ch.youtube_music|Plexamp" },
	workspace = "special:music",
})
hl.window_rule({ match = { class = "discord|equibop|vesktop|whatsapp" }, workspace = "special:communication" })

-- Einzelfenster bekommen mehr Luft (oben halbiert, siehe Variablen oben)
hl.workspace_rule({
	workspace = "w[tv1]s[false]",
	gaps_out = {
		top = cfg.singleWindowGapsOutTop,
		right = cfg.singleWindowGapsOut,
		bottom = cfg.singleWindowGapsOut,
		left = cfg.singleWindowGapsOut,
	},
})
hl.workspace_rule({
	workspace = "f[1]s[false]",
	gaps_out = {
		top = cfg.singleWindowGapsOutTop,
		right = cfg.singleWindowGapsOut,
		bottom = cfg.singleWindowGapsOut,
		left = cfg.singleWindowGapsOut,
	},
})

-- Jede 10er-Gruppe fest an ihren Monitor binden
for monitor, offset in pairs(cfg.wsMonitorOffset) do
	for i = 1, 10 do
		hl.workspace_rule({
			workspace = tostring(offset + i),
			monitor = monitor,
			default = (i == 1),
		})
	end
end

-- Launcher-Overlay huebsch einblenden
hl.layer_rule({ match = { namespace = "launcher" }, animation = "popin 80%", blur = true })
hl.layer_rule({ match = { namespace = "selection" }, animation = "fade" }) -- slurp
hl.layer_rule({ match = { namespace = "hyprpicker" }, animation = "fade" })

--------------------------------------------------------------------------------
-- Autostart (nur beim Hyprland-Start, nicht bei jedem Reload)
--------------------------------------------------------------------------------
hl.on("hyprland.start", function()
	-- Passwort-Dialoge fuer GUI-Apps
	hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")

	-- Zwischenablage-Verlauf
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")

	-- Cursor
	hl.exec_cmd("hyprctl setcursor " .. cfg.cursorTheme .. " " .. cfg.cursorSize)
	hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. cfg.cursorTheme)
	hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. cfg.cursorSize)

	-- Bluetooth-Medientasten an MPRIS weiterreichen
	hl.exec_cmd("mpris-proxy")

	-- Papierkorb aufraeumen
	hl.exec_cmd("trash-empty -f 30")

	-- Shell dieses Profils starten (Zuordnung steht in hypr-profile):
	-- beendet eine noch laufende andere Shell und faehrt shell2 hoch.
	hl.exec_cmd(hyprProfile .. " shell-sync")
end)

--------------------------------------------------------------------------------
-- Workspace-Helfer: SUPER+N = Workspace N des fokussierten Monitors
--------------------------------------------------------------------------------
local function monitor_offset()
	local mon = hl.get_active_monitor()
	if mon and cfg.wsMonitorOffset[mon.name] then
		return cfg.wsMonitorOffset[mon.name]
	end
	return 0
end

local function wsaction(action, i)
	return function()
		local target = monitor_offset() + i
		if action == "move" then
			return hl.dispatch(hl.dsp.window.move({ workspace = target }))
		end
		return hl.dispatch(hl.dsp.focus({ workspace = target }))
	end
end

--------------------------------------------------------------------------------
-- Keybinds
--------------------------------------------------------------------------------
-- Apps
hl.bind("SUPER + Q", hl.dsp.exec_cmd(cfg.terminal))
hl.bind("SUPER + W", hl.dsp.exec_cmd(cfg.browser))
hl.bind("SUPER + P", hl.dsp.exec_cmd(cfg.editor))
hl.bind("SUPER + E", hl.dsp.exec_cmd(cfg.fileExplorer))
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd(cfg.audioSettings))
-- Super allein oeffnet das App-Menue der Shell (per Quickshell-IPC).
-- Laeuft die Shell gerade nicht, faellt es auf cfg.launcher (fuzzel) zurueck.
hl.bind(
	"SUPER + SUPER_L",
	hl.dsp.exec_cmd("qs -c shell2 ipc call launcher toggle || " .. cfg.launcher),
	{ release = true }
)
hl.bind("SUPER + Space", hl.dsp.exec_cmd(cfg.launcher))
hl.bind("SUPER + L", hl.dsp.exec_cmd(cfg.lockCmd))
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(cfg.sleepCmd), { locked = true })

-- Fenster
hl.bind("SUPER + C", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + ALT + space", hl.dsp.window.float())
hl.bind("SUPER + SHIFT + P", hl.dsp.window.pin())
hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.center())
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Fokus / verschieben
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

-- Fenstergruppen (Tabs)
hl.bind("SUPER + Comma", hl.dsp.group.toggle())
hl.bind("SUPER + U", hl.dsp.window.move({ out_of_group = true }))
hl.bind("ALT + TAB", hl.dsp.window.cycle_next(), { repeating = true })
hl.bind("SHIFT + ALT + TAB", hl.dsp.window.cycle_next({ next = false }), { repeating = true })

-- Workspaces des fokussierten Monitors
for i = 1, 10 do
	local key = i % 10 -- 10 liegt auf der Taste 0
	hl.bind("SUPER + " .. key, wsaction("focus", i))
	hl.bind("SUPER + ALT + " .. key, wsaction("move", i))
end
hl.bind("CTRL + SUPER + Left", hl.dsp.focus({ workspace = "m-1" }), { repeating = true })
hl.bind("CTRL + SUPER + Right", hl.dsp.focus({ workspace = "m+1" }), { repeating = true })
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "m-1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "m+1" }))
hl.bind("CTRL + SUPER + SHIFT + Left", hl.dsp.window.move({ workspace = "m-1" }), { repeating = true })
hl.bind("CTRL + SUPER + SHIFT + Right", hl.dsp.window.move({ workspace = "m+1" }), { repeating = true })

-- Special-Workspaces (Scratchpads)
-- ueber die CLI: startet die zugehoerige App gleich mit, wenn der Workspace leer ist
-- (Zuordnung in ~/.config/dynamic-island/cli.json unter "toggles")
hl.bind("SUPER + S", hl.dsp.exec_cmd("dynamic-island toggle specialws"))
-- Music: laeuft Spotify schon, wird special:music auf dem Fokus-Monitor
-- getoggelt (offen -> zu, zu/anderer Monitor -> hierher). Sonst startet
-- Spotify zuerst und der Special wird geöffnet, sobald das Fenster da ist.
hl.bind(
	"SUPER + M",
	hl.dsp.exec_cmd([[
		if hyprctl -j clients | grep -q '"class": *"Spotify"'; then
			hyprctl dispatch 'hl.dsp.workspace.toggle_special("music")'
		else
			spotify-launcher >/dev/null 2>&1 &
			for i in $(seq 1 30); do
				hyprctl -j clients | grep -q '"class": *"Spotify"' && break
				sleep 0.5
			done
			hyprctl dispatch 'hl.dsp.focus({ workspace = "special:music" })'
		fi
	]])
)
hl.bind("SUPER + D", hl.dsp.exec_cmd("dynamic-island toggle communication"))
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("dynamic-island toggle sysmon"))
hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special" }))

-- Lautstaerke / Mikrofon
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd(
		"wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l "
			.. (cfg.volumeMax / 100)
			.. " @DEFAULT_AUDIO_SINK@ "
			.. cfg.volumeStep
			.. "%+"
	),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. cfg.volumeStep .. "%-"),
	{ locked = true, repeating = true }
)

-- Helligkeit
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s " .. cfg.brightnessStep .. "%+"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s " .. cfg.brightnessStep .. "%-"), { locked = true })

-- Medien
-- Medientasten gehen an die Shell statt an playerctl: nur die kennt die im
-- Medien-Selektor gewaehlte Quelle. playerctl wuerde sich selbst einen Player
-- aussuchen und damit womoeglich einen anderen als die Leiste anzeigt.
-- Die Gegenstelle sind die GlobalShortcuts in
-- ~/projects/shell2/modules/services/media/Media.qml (appid "shell2")
hl.bind("CTRL + SUPER + Space", hl.dsp.global("shell2:mediaToggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.global("shell2:mediaToggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.global("shell2:mediaNext"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("shell2:mediaPrev"), { locked = true })

-- Screenshots / Farbpicker  (dynamic-island uebernimmt Zwischenablage,
-- Benachrichtigung mit Open/Save und den Cache unter ~/.cache/dynamic-island)
hl.bind("Print", hl.dsp.exec_cmd("dynamic-island screenshot"), { locked = true })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("dynamic-island screenshot -r -f"))
hl.bind("SUPER + SHIFT + ALT + S", hl.dsp.exec_cmd("dynamic-island screenshot -r -e"))
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))

-- Bildschirmaufnahme (gpu-screen-recorder; derselbe Bind stoppt wieder)
hl.bind("CTRL + ALT + R", hl.dsp.exec_cmd("dynamic-island record"))
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("dynamic-island record -s"))
hl.bind("SUPER + SHIFT + ALT + R", hl.dsp.exec_cmd("dynamic-island record -r"))

-- Zwischenablage-Verlauf (cliphist via fuzzel)
hl.bind("SUPER + V", hl.dsp.exec_cmd("pkill fuzzel || dynamic-island clipboard"))
hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd("pkill fuzzel || dynamic-island clipboard -d"))

-- Emoji-/Glyph-Picker
hl.bind("SUPER + Period", hl.dsp.exec_cmd("pkill fuzzel || dynamic-island emoji -p"))

-- Wallpaper und Farbschema
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("dynamic-island wallpaper -r"))
hl.bind("CTRL + SUPER + SHIFT + T", hl.dsp.exec_cmd("dynamic-island scheme set -r"))

-- Shell dieses Profils neu starten / beenden
hl.bind("CTRL + SUPER + ALT + R", hl.dsp.exec_cmd(hyprProfile .. " shell-restart"), { release = true })
hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd(hyprProfile .. " shell-kill"), { release = true })

-- Hinweis: Der Profil-Umschalter CTRL + SUPER + SHIFT + P wird in ../hyprland.lua
-- gesetzt und gilt damit in allen Profilen.
