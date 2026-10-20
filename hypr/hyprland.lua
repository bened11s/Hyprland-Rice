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
local defaultProfile  = "simple"
local switchBind      = "CTRL + SUPER + SHIFT + P"

--------------------------------------------------------------------------------
-- Monitore (gelten fuer beide Profile)
--------------------------------------------------------------------------------
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@60",
    position = "0x0",
    scale    = 1,
    vrr      = false,
})

hl.monitor({
    output   = "HDMI-A-1",
    mode     = "highres",
    position = "auto-right",
    scale    = 1,
})

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
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

function bind_described(keys, action, opts)
    if opts and opts.description then
        keybind_actions[opts.description] = action
    end
    return hl.bind(keys, action, opts)
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

-- Bildschirm-Regeln aus dem Bildschirmmanager (dynamic-island, Kachel
-- "Bildschirm"). Steht ganz am Ende, damit diese Regeln die festen
-- Monitore oben UND die Profile ueberschreiben – in Hyprland gewinnt die
-- letzte passende Regel. Fehlt die Datei (noch nie gespeichert), ist das
-- still: dann gelten weiter die Regeln oben.
local monitorsLua = hypr .. "/monitors.lua"
if io.open(monitorsLua) then
    local okMon, errMon = pcall(dofile, monitorsLua)
    if not okMon then
        io.stderr:write("monitors.lua fehlerhaft: " .. tostring(errMon) .. "\n")
    end
end

-- Profiluebergreifendes Idle-Management; nur einmal beim Sessionstart starten.
-- Die Shell dynamic-island ebenfalls beim Sessionstart – AUF DER IGPU (wenn
-- vorhanden): die Env schaltet NVIDIA-EGL fuer qs ab, nur Mesa bleibt, und auf
-- diesem Rechner kann nur die iGPU (AMD, renderD129) ueber Mesa rendern.
-- Ohne das wuerde die Shell die dGPU belegen, die Spiele brauchen.
hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
    hl.exec_cmd("env __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json qs -c dynamic-island")
end)
