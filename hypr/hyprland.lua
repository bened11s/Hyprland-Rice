-- Hyprland-Hauptconfig: Monitore + Profil-Weiche.
--
--   ~/.config/hypr/profile             Name des aktiven Profils
--   ~/.config/hypr/profiles/*.lua      die Profile selbst
--   ~/.local/bin/hypr-profile          Umschalter (Shell-Script)
--
-- Umschalten im laufenden Betrieb:  CTRL + SUPER + SHIFT + P (schaltet durch)
-- oder im Terminal:                 hypr-profile [<name>|toggle|status]
--
-- caelestia = volle Config + Caelestia-Quickshell-Shell (Bar, Notifications, Wallpaper)
-- simple    = eine schlanke Datei mit den wichtigsten Einstellungen, Shell dynamic-island
-- shell2    = dieselbe schlanke Basis, aber mit der neuen Shell shell2
--
-- Ein weiteres Profil braucht nur profiles/<name>.lua und einen Eintrag in
-- hypr-profile (PROFILE_SHELL + PROFILE_ORDER) — hier ist nichts zu aendern.

local home            = os.getenv("HOME")
local hypr            = home .. "/.config/hypr"
local profileFile     = hypr .. "/profile"
local defaultProfile  = "caelestia"
local switchBind      = "CTRL + SUPER + SHIFT + P"

--------------------------------------------------------------------------------
-- Monitore (gelten fuer beide Profile)
--------------------------------------------------------------------------------
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "2560x1440@60",
    position = "0x0",
    scale    = 1,
    vrr      = false,
})

hl.monitor({
    output   = "DP-2",
    mode     = "2560x1440@180",
    position = "2560x0",
    scale    = 1,
})

hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "auto",
    scale    = 1.25,
})

--------------------------------------------------------------------------------
-- Profil bestimmen
--------------------------------------------------------------------------------
local function read_profile()
    local f = io.open(profileFile)
    if not f then
        return defaultProfile
    end

    local name = (f:read("*l") or ""):gsub("%s", "")
    f:close()

    -- Gueltig ist jeder schlichte Name, zu dem es auch eine Profildatei gibt.
    -- Das Muster haelt Pfadtrenner und Punkte heraus, damit `require` nicht
    -- irgendwo anders im Dateisystem landet.
    if name:match("^[%w_%-]+$") then
        local profileLua = io.open(hypr .. "/profiles/" .. name .. ".lua")
        if profileLua then
            profileLua:close()
            return name
        end
    end
    return defaultProfile
end

local function write_profile(name)
    local f = io.open(profileFile, "w")
    if f then
        f:write(name .. "\n")
        f:close()
    end
end

-- Bei `hyprctl reload` laeuft diese Datei erneut, `require` wuerde die Module aber
-- aus dem Cache nehmen und nichts mehr setzen. Darum vorher gezielt entladen.
local function flush_modules()
    for key in pairs(package.loaded) do
        if key == "variables"
            or key == "hypr-vars"
            or key == "hypr-user"
            or key:match("^hyprland%.")
            or key:match("^scheme%.")
            or key:match("^profiles%.")
        then
            package.loaded[key] = nil
        end
    end
end

local function load_profile(name)
    flush_modules()
    return pcall(require, "profiles." .. name)
end

-- systemd graphical session (Portale, deckhand.service & andere User-Services) fuer
-- jedes Profil; ohne das startet nichts mit WantedBy=graphical-session.target.
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target")
end)

--------------------------------------------------------------------------------
-- Klickbare Tastenkuerzel-Uebersicht der Shell (dynamic-island, SUPER + K)
--------------------------------------------------------------------------------
-- Binds mit Beschreibung ("Gruppe|Text") legen ueber bind_described ihre
-- Aktion unter genau dieser Beschreibung ab; ein Klick in der Uebersicht
-- loest sie aus:  hyprctl eval 'run_keybind([==[Gruppe|Text]==])'
-- Global, weil `hyprctl eval` im selben Lua-Zustand laeuft wie diese Config.
-- Bei jedem Reload neu angelegt, damit keine Aktionen alter Binds bleiben.
keybind_actions = {}

-- Aenderungen aus der Uebersicht (Taste neu belegt, abgeschaltet) und Binds,
-- die die Shell selbst mitbringt (Plugins, eigene Kuerzel), schreibt die
-- Shell nach keybindFile (modules/services/hypr/Keybinds.qml). sync_keybinds()
-- wendet die Datei an – beim Laden der Config und live per
--   hyprctl eval 'sync_keybinds()'
-- Nur Profile, die `keybinds_from_shell = true` setzen (simple), nehmen sie.
local keybindFile = home .. "/.local/state/dynamic-island/keybinds.lua"
keybinds_from_shell = nil
idle_from_shell = nil
-- Beschriebene Binds der Config: { ref, keys, action, opts, handle, current }
-- ref = "Gruppe|Text@<modmask>:<taste>" der urspruenglichen Belegung
described_binds = {}
-- Was sync_keybinds() selbst gebunden hat (wird bei jedem Sync ersetzt)
shell_binds = {}

local function bind_ref(description, handle)
    if handle.key == "" then
        return description .. "@" .. handle.modmask .. ":code:" .. handle.keycode
    end
    return description .. "@" .. handle.modmask .. ":" .. string.lower(handle.key)
end

function bind_described(keys, action, opts)
    local handle = hl.bind(keys, action, opts)
    if opts and opts.description then
        keybind_actions[opts.description] = action
        if handle then
            described_binds[#described_binds + 1] = {
                ref = bind_ref(opts.description, handle),
                keys = keys, action = action, opts = opts,
                handle = handle, current = keys,
            }
        end
    end
    return handle
end

function sync_keybinds()
    if not keybinds_from_shell then
        return
    end
    local ok, data = pcall(dofile, keybindFile)
    if not ok or type(data) ~= "table" then
        data = {}
    end
    local overrides = data.overrides or {}

    -- Binds der Config: neu belegen bzw. an/aus
    for _, b in ipairs(described_binds) do
        local o = overrides[b.ref] or {}
        local keys = o.keys or b.keys
        if keys ~= b.current then
            b.handle:remove()
            local okBind, handle = pcall(hl.bind, keys, b.action, b.opts)
            if not okBind or not handle then
                -- Unbrauchbare Taste: bei der alten bleiben
                keys = b.keys
                handle = hl.bind(keys, b.action, b.opts)
            end
            b.handle, b.current = handle, keys
        end
        b.handle:set_enabled(not o.disabled)
    end

    -- Binds der Shell: alle weg, dann neu aus der Datei
    for _, s in ipairs(shell_binds) do
        pcall(s.handle.remove, s.handle)
        keybind_actions[s.description] = nil
    end
    shell_binds = {}
    for _, s in ipairs(data.binds or {}) do
        local action = hl.dsp.exec_cmd(s.exec)
        local opts = {
            description = s.description,
            release = s.release or nil,
            repeating = s.repeating or nil,
            locked = s.locked or nil,
        }
        local okBind, handle = pcall(hl.bind, s.keys, action, opts)
        if okBind and handle then
            if s.disabled then
                handle:set_enabled(false)
            end
            keybind_actions[s.description] = action
            shell_binds[#shell_binds + 1] = { handle = handle, description = s.description }
        end
    end
end

-- Taste aufnehmen: solange die Uebersicht eine neue Kombination abfragt,
-- steht Hyprland in einer Submap ohne eigene Binds – sonst loeste SUPER+Q
-- das Terminal aus, statt bei der Shell anzukommen. Notbremse falls die
-- Shell haengt: CTRL+SUPER+ALT+Escape oder nach 20 s von selbst zurueck.
hl.define_submap("keybind-capture", function()
    hl.bind("CTRL + SUPER + ALT + Escape", hl.dsp.submap("reset"))
end)

local captureGeneration = 0

function keybind_capture(on)
    captureGeneration = captureGeneration + 1
    local generation = captureGeneration
    if on then
        hl.dispatch(hl.dsp.submap("keybind-capture"))
        hl.timer(function()
            if generation == captureGeneration and hl.get_current_submap() == "keybind-capture" then
                hl.dispatch(hl.dsp.submap("reset"))
            end
        end, { timeout = 20000, type = "oneshot" })
    elseif hl.get_current_submap() == "keybind-capture" then
        hl.dispatch(hl.dsp.submap("reset"))
    end
end

function run_keybind(id)
    local action = keybind_actions[id]
    if type(action) == "function" then
        return action()
    elseif action then
        return hl.dispatch(action)
    end
end

local profile = read_profile()
local ok, err = load_profile(profile)

if not ok then
    local msg = "Hyprland-Profil '" .. profile .. "' fehlerhaft: " .. tostring(err)
    io.stderr:write(msg .. "\n")
    hl.exec_cmd("hyprctl notify -1 10000 'rgb(ff4444)' " .. string.format("%q", msg))

    -- Zurueck auf das Standardprofil, damit der naechste Start wieder hochkommt
    if profile ~= defaultProfile then
        write_profile(defaultProfile)
        local okFallback, errFallback = load_profile(defaultProfile)
        if not okFallback then
            io.stderr:write("Fallback-Profil ebenfalls fehlerhaft: " .. tostring(errFallback) .. "\n")
        end
    end
end

--------------------------------------------------------------------------------
-- Profil-Umschalter (nach dem Profil gesetzt, damit er immer gewinnt)
--------------------------------------------------------------------------------
-- description: Zeile in der Tastenkuerzel-Uebersicht der Shell ("Gruppe|Text")
bind_described(switchBind, hl.dsp.exec_cmd(home .. "/.local/bin/hypr-profile toggle"),
    { release = true, description = "Shell|Hypr-Profil wechseln" })

-- Aenderungen aus der Tastenkuerzel-Uebersicht + Plugin-Binds (nach allen
-- Binds, damit auch der Profil-Umschalter neu belegt werden kann)
sync_keybinds()

-- Idle-Management per hypridle, nur einmal beim Sessionstart. Profile mit
-- `idle_from_shell = true` (simple) lassen die Shell sperren; den Wechsel
-- zur Laufzeit erledigt hypr-profile (sync_idle).
hl.on("hyprland.start", function()
    if not idle_from_shell then
        hl.exec_cmd("hypridle")
    end
end)
