-- Profil "simple" — schlanke Hyprland-Config ohne Caelestia und ohne Quickshell.
--
-- Bewusst EINE Datei mit allen wichtigen Stellschrauben oben in `cfg`.
-- Haengt an nichts aus ~/.config/hypr/hyprland/ (das gehoert zum Caelestia-Profil),
-- laeuft also auch dann noch, wenn dort etwas kaputt ist.
--
-- Die Shell dieses Profils ist die eigene Quickshell-Config "dynamic-island"
-- (~/.config/quickshell/dynamic-island, zeichnet Wallpaper + Bar). Ihr Name steht NICHT
-- hier, sondern in ~/.local/bin/hypr-profile (Tabelle PROFILE_SHELL oben im
-- Script); Autostart und die Shell-Keybinds unten rufen nur dieses Script auf,
-- damit es genau eine Stelle gibt, die weiss welche Shell zu welchem Profil gehoert.
--
-- Was die Shell (noch) nicht abdeckt und dieses Profil deshalb nicht hat:
-- Notifications, OSDs fuer Lautstaerke/Helligkeit, Sidebar, Launcher-Overlay.
-- Launcher = fuzzel, Lockscreen = hyprlock.
--
-- Umschalten: hypr-profile caelestia   (oder CTRL + SUPER + SHIFT + P)

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
	-- Sperrbildschirm (SUPER + L): der Lockscreen der dynamic-island-Shell
	-- (quickshell/dynamic-island/modules/lock); laeuft die Shell nicht, nimmt
	-- das Skript hyprlock mit ~/.config/hypr/hyprlock.conf.
	-- Nur hyprlock:  lockCmd = "hyprlock"
	lockCmd = home .. "/.config/hypr/scripts/lock.sh",

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
		-- dynamic-island-background); laeuft keine Shell, bleibt diese Farbe stehen.
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

-- Einstellungs-Fenster der Shell: schwebt mittig, Rand/Schatten/Rundung
-- zeichnet die Karte selbst (das Fenster ist rundum 28 px transparent)
hl.window_rule({
	match = { class = "org.quickshell", title = "dynamic-island-settings" },
	float = true,
	center = true,
	opaque = true,
	no_blur = true,
	no_shadow = true,
	border_size = 0,
	rounding = 0,
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
	-- beendet eine noch laufende Caelestia-Shell und faehrt dynamic-island hoch.
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
-- Beschreibungen fuer die Tastenkuerzel-Uebersicht der Shell (SUPER + K).
-- Die Shell liest sie live aus `hyprctl binds -j`, Format "Gruppe|Text",
-- optional "|Anzeige" statt der echten Taste (z.B. "1 … 0" fuer zehn Binds).
-- Ein Klick auf die Zeile fuehrt den Bind aus. Binds ohne Beschreibung
-- tauchen dort nicht auf; gleicher Text in derselben
-- Gruppe wird zu einer Zeile mit mehreren Kuerzeln zusammengefasst.
-- bind() merkt sich die Aktion beschriebener Binds, damit die Uebersicht sie
-- per Klick ausloesen kann (bind_described/run_keybind in ../hyprland.lua).
-- Neu belegte/abgeschaltete Binds und die Binds der Plugins kommen aus der
-- Shell (keybinds_from_shell, sync_keybinds() in ../hyprland.lua).
keybinds_from_shell = true
-- Sperren/Displays aus/ScreenSaver-Inhibit macht die Shell (services/idle),
-- hypridle laeuft hier nicht (hyprland.lua, hypr-profile sync_idle)
idle_from_shell = true
local bind = bind_described
local group = ""
local function desc(text, opts, label)
	opts = opts or {}
	opts.description = group .. "|" .. text .. (label and "|" .. label or "")
	return opts
end

-- Apps
group = "Apps"
bind("SUPER + Q", hl.dsp.exec_cmd(cfg.terminal), desc("Terminal"))
bind("SUPER + W", hl.dsp.exec_cmd(cfg.browser), desc("Browser"))
bind("SUPER + P", hl.dsp.exec_cmd(cfg.editor), desc("Editor"))
bind("SUPER + E", hl.dsp.exec_cmd(cfg.fileExplorer), desc("Dateimanager"))
bind("CTRL + ALT + V", hl.dsp.exec_cmd(cfg.audioSettings), desc("Audio-Einstellungen"))
group = "Shell"
-- Super allein oeffnet das App-Menue der Shell (per Quickshell-IPC).
-- Laeuft die Shell gerade nicht, faellt es auf cfg.launcher (fuzzel) zurueck.
bind(
	"SUPER + SUPER_L",
	hl.dsp.exec_cmd("qs -c dynamic-island ipc call launcher toggle || " .. cfg.launcher),
	desc("App-Menü", { release = true })
)
bind("SUPER + Space", hl.dsp.exec_cmd(cfg.launcher), desc("App-Starter (fuzzel)"))
-- Untermenues der Notch (Quickshell-IPC), nochmal druecken = zu.
-- Dieselben Ansichten erreicht man im Launcher mit >medien, >steuerung,
-- >benachrichtigungen, >system, >power oder durch Blaettern in der Notch.
-- Medien hat bewusst kein Kuerzel: SUPER+M gehoert dem Music-Workspace.
bind("SUPER + A", hl.dsp.exec_cmd("qs -c dynamic-island ipc call launcher control"), desc("Steuerung"))
bind("SUPER + N", hl.dsp.exec_cmd("qs -c dynamic-island ipc call launcher notifications"), desc("Benachrichtigungen"))
bind("SUPER + I", hl.dsp.exec_cmd("qs -c dynamic-island ipc call launcher system"), desc("System"))
bind("SUPER + X", hl.dsp.exec_cmd("qs -c dynamic-island ipc call launcher power"), desc("Power-Menü"))
bind("SUPER + K", hl.dsp.exec_cmd("qs -c dynamic-island ipc call launcher keys"), desc("Tastenkürzel"))
bind("SUPER + L", hl.dsp.exec_cmd(cfg.lockCmd), desc("Sperren"))
-- Stuerzt die Shell bei gesperrter Sitzung ab, bleibt Hyprland gesperrt ohne
-- Oberflaeche zurueck – hyprlock uebernimmt dann (allow_session_lock_restore)
bind("SUPER + ALT + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), desc("Sperre retten (hyprlock)", { locked = true }))
bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(cfg.sleepCmd), desc("Standby", { locked = true }))

-- Fenster
group = "Fenster"
bind("SUPER + C", hl.dsp.window.close(), desc("Schließen"))
bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), desc("Vollbild"))
bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), desc("Maximieren"))
bind("SUPER + ALT + space", hl.dsp.window.float(), desc("Schwebend an/aus"))
bind("SUPER + SHIFT + P", hl.dsp.window.pin(), desc("Anheften"))
bind("CTRL + SUPER + Backslash", hl.dsp.window.center(), desc("Zentrieren"))
bind("SUPER + mouse:272", hl.dsp.window.drag(), desc("Fenster ziehen", { mouse = true }))
bind("SUPER + mouse:273", hl.dsp.window.resize(), desc("Größe ändern", { mouse = true }))

-- Fokus / verschieben
group = "Fokus"
bind("SUPER + left", hl.dsp.focus({ direction = "left" }), desc("Fokus wechseln", nil, "Pfeile"))
bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "left" }), desc("Fenster verschieben", nil, "Pfeile"))
bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

-- Fenstergruppen (Tabs)
group = "Fokus"
bind("SUPER + Comma", hl.dsp.group.toggle(), desc("Fenstergruppe an/aus"))
bind("SUPER + U", hl.dsp.window.move({ out_of_group = true }), desc("Aus Gruppe lösen"))
bind("ALT + TAB", hl.dsp.window.cycle_next(), desc("Nächstes Fenster", { repeating = true }))
bind("SHIFT + ALT + TAB", hl.dsp.window.cycle_next({ next = false }), desc("Vorheriges Fenster", { repeating = true }))

-- Workspaces des fokussierten Monitors
group = "Workspaces"
for i = 1, 10 do
	local key = i % 10 -- 10 liegt auf der Taste 0
	-- in der Uebersicht eine Zeile fuer alle zehn
	bind("SUPER + " .. key, wsaction("focus", i), i == 1 and desc("Workspace 1–10", nil, "1 … 0") or {})
	bind("SUPER + ALT + " .. key, wsaction("move", i), i == 1 and desc("Fenster auf Workspace 1–10", nil, "1 … 0") or {})
end
bind("CTRL + SUPER + Left", hl.dsp.focus({ workspace = "m-1" }), desc("Vorheriger Workspace", { repeating = true }))
bind("CTRL + SUPER + Right", hl.dsp.focus({ workspace = "m+1" }), desc("Nächster Workspace", { repeating = true }))
bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "m-1" }), desc("Workspace blättern", nil, "Mausrad"))
bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "m+1" }))
bind("CTRL + SUPER + SHIFT + Left", hl.dsp.window.move({ workspace = "m-1" }), desc("Fenster zurückschieben", { repeating = true }))
bind("CTRL + SUPER + SHIFT + Right", hl.dsp.window.move({ workspace = "m+1" }), desc("Fenster weiterschieben", { repeating = true }))

-- Special-Workspaces (Scratchpads)
group = "Scratchpads"
-- ueber die CLI: startet die zugehoerige App gleich mit, wenn der Workspace leer ist
-- (Zuordnung in ~/.config/dynamic-island/cli.json unter "toggles")
bind("SUPER + S", hl.dsp.exec_cmd("dynamic-island toggle specialws"), desc("Scratchpad"))
-- Music: laeuft Spotify schon, wird special:music auf dem Fokus-Monitor
-- getoggelt (offen -> zu, zu/anderer Monitor -> hierher). Sonst startet
-- Spotify zuerst und der Special wird geöffnet, sobald das Fenster da ist.
bind(
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
	]]),
	desc("Spotify")
)
bind("SUPER + D", hl.dsp.exec_cmd("dynamic-island toggle communication"), desc("Kommunikation"))
bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("dynamic-island toggle sysmon"), desc("Systemmonitor"))
bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special" }), desc("Fenster ins Scratchpad"))

-- Lautstaerke / Mikrofon
group = "Audio & Medien"
bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), desc("Ton stumm", { locked = true }))
bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), desc("Ton stumm", { locked = true }))
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), desc("Mikrofon stumm", { locked = true }))
bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd(
		"wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l "
			.. (cfg.volumeMax / 100)
			.. " @DEFAULT_AUDIO_SINK@ "
			.. cfg.volumeStep
			.. "%+"
	),
	desc("Lauter", { locked = true, repeating = true })
)
bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. cfg.volumeStep .. "%-"),
	desc("Leiser", { locked = true, repeating = true })
)

-- Helligkeit
bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s " .. cfg.brightnessStep .. "%+"), desc("Heller", { locked = true }))
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s " .. cfg.brightnessStep .. "%-"), desc("Dunkler", { locked = true }))

-- Medien
-- Medientasten gehen an die Shell statt an playerctl: nur die kennt die im
-- Medien-Selektor gewaehlte Quelle. playerctl wuerde sich selbst einen Player
-- aussuchen und damit womoeglich einen anderen als die Leiste anzeigt.
-- Die Gegenstelle sind die GlobalShortcuts in
-- ~/.config/quickshell/dynamic-island/modules/services/media/Media.qml
bind("CTRL + SUPER + Space", hl.dsp.global("dynamic-island:mediaToggle"), desc("Play/Pause", { locked = true }))
bind("XF86AudioPlay", hl.dsp.global("dynamic-island:mediaToggle"), desc("Play/Pause", { locked = true }))
bind("XF86AudioNext", hl.dsp.global("dynamic-island:mediaNext"), desc("Nächster Titel", { locked = true }))
bind("XF86AudioPrev", hl.dsp.global("dynamic-island:mediaPrev"), desc("Vorheriger Titel", { locked = true }))

group = "Aufnahme"
-- Screenshots: Print direkt (grim), Bereich/Text/Code ueber das Overlay der
-- Shell (Standbild, Fenster einrasten); ohne Shell faellt die CLI auf slurp
-- zurueck. Kopiert wird immer, die Nachricht bietet Speichern/Bearbeiten.
bind("Print", hl.dsp.exec_cmd("dynamic-island screenshot"), desc("Screenshot ganzer Bildschirm", { locked = true }))
bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("dynamic-island screenshot -r"), desc("Screenshot Bereich"))
bind("SUPER + SHIFT + ALT + S", hl.dsp.exec_cmd("dynamic-island screenshot -r -e"), desc("Screenshot bearbeiten"))
bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("dynamic-island screenshot --ocr"), desc("Text vom Bildschirm kopieren"))
bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("dynamic-island screenshot --qr"), desc("QR-Code lesen"))

-- Bildschirmaufnahme (gpu-screen-recorder; derselbe Bind stoppt wieder)
bind("CTRL + ALT + R", hl.dsp.exec_cmd("dynamic-island record"), desc("Aufnahme an/aus"))
bind("SUPER + ALT + R", hl.dsp.exec_cmd("dynamic-island record -s"), desc("Aufnahme mit Ton"))
bind("SUPER + SHIFT + ALT + R", hl.dsp.exec_cmd("dynamic-island record -r"), desc("Aufnahme Bereich"))

-- Zwischenablage-Verlauf: Launcher-Modus der Shell (cliphist), ohne Shell fuzzel
group = "Werkzeuge"
bind("SUPER + V", hl.dsp.exec_cmd("pkill fuzzel || qs -c dynamic-island ipc call launcher clipboard || dynamic-island clipboard"), desc("Zwischenablage"))
bind("SUPER + ALT + V", hl.dsp.exec_cmd("pkill fuzzel || dynamic-island clipboard -d"), desc("Aus Zwischenablage löschen"))

-- Farbpipette
bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"), desc("Farbpipette"))

-- Emoji-/Glyph-Picker
bind("SUPER + Period", hl.dsp.exec_cmd("pkill fuzzel || dynamic-island emoji -p"), desc("Emoji-Picker"))

-- Wallpaper und Farbschema
bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("dynamic-island wallpaper -r"), desc("Zufälliges Wallpaper"))
-- Wallhaven-Suche (SUPER + ALT + W) und Desktop-Widgets anordnen (SUPER + ALT + D)
-- bringen die Plugins `wallhaven`/`desktop` selbst mit (Manifest `keybinds`)
bind("CTRL + SUPER + SHIFT + T", hl.dsp.exec_cmd("dynamic-island scheme set -r"), desc("Zufälliges Farbschema"))

-- Shell dieses Profils neu starten / beenden
group = "Shell"
bind("CTRL + SUPER + ALT + R", hl.dsp.exec_cmd(hyprProfile .. " shell-restart"), desc("Shell neu starten", { release = true }))
bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd(hyprProfile .. " shell-kill"), desc("Shell beenden", { release = true }))

-- Hinweis: Der Profil-Umschalter CTRL + SUPER + SHIFT + P wird in ../hyprland.lua
-- gesetzt und gilt damit in beiden Profilen.
