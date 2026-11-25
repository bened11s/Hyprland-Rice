-- monitor-setup.lua — Monitore dieses Rechners laden und anwenden.
--
-- Welche Bildschirme ein Rechner hat, steht NICHT im Repo, sondern in der
-- lokalen Datei ~/.config/hypr/monitors.lua (git-ignoriert, Vorlage:
-- monitors.example.lua). install.sh legt sie aus `hyprctl monitors` an,
-- erneut mit `./install.sh --monitors`.
--
-- Fehlt die Datei oder ist sie kaputt, laeuft alles trotzdem: jeder Monitor
-- bekommt seine bevorzugte Aufloesung, und die Workspace-Gruppen (1-10,
-- 11-20, ...) werden von links nach rechts automatisch vergeben.
--
-- Benutzt von hyprland.lua (apply), den Profilen simple/shell2
-- (bind_workspaces, offset) und hyprland/functions.lua (offset).

local M = {
    file = os.getenv("HOME") .. "/.config/hypr/monitors.lua",
    list = {},        -- Eintraege aus monitors.lua
    offsets = {},     -- Ausgang -> erster Workspace - 1 (0, 10, 20, ...)
    configured = false,
    error = nil,      -- Fehlertext, wenn monitors.lua nicht ladbar war
}

local exists = io.open(M.file)
if exists then
    exists:close()
    local ok, list = pcall(dofile, M.file)
    if ok and type(list) == "table" then
        M.list, M.configured = list, true
    else
        M.error = ok and "monitors.lua liefert keine Tabelle" or tostring(list)
    end
end

for _, m in ipairs(M.list) do
    if type(m) == "table" and m.output and m.workspaces then
        M.offsets[m.output] = m.workspaces
    end
end

-- Monitor-Regeln setzen. Die leere Regel zuerst: sie greift fuer alles, was
-- nicht namentlich in monitors.lua steht (fremder Rechner, Beamer, Laptop).
function M.apply()
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
    for _, m in ipairs(M.list) do
        if type(m) == "table" and m.output then
            local spec = {}
            for k, v in pairs(m) do
                if k ~= "workspaces" then spec[k] = v end
            end
            hl.monitor(spec)
        end
    end
end

-- Jede 10er-Gruppe fest an ihren Monitor binden (nur fuer eingetragene
-- Monitore; ohne monitors.lua entsteht ein Workspace dort, wo man ihn oeffnet).
function M.bind_workspaces()
    for output, offset in pairs(M.offsets) do
        for i = 1, 10 do
            hl.workspace_rule({
                workspace = tostring(offset + i),
                monitor = output,
                default = (i == 1),
            })
        end
    end
end

-- Automatische Gruppe: Position von links nach rechts (bei gleicher Spalte
-- von oben nach unten). Gespiegelte Monitore zaehlen nicht mit.
local function auto_offset(name)
    local mons = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        if not m.is_mirror then mons[#mons + 1] = m end
    end
    local function pos(m)
        local p = type(m.position) == "table" and m.position or {}
        return p.x or 0, p.y or 0
    end
    table.sort(mons, function(a, b)
        local ax, ay = pos(a)
        local bx, by = pos(b)
        if ax ~= bx then return ax < bx end
        return ay < by
    end)
    for i, m in ipairs(mons) do
        if m.name == name then return (i - 1) * 10 end
    end
    return 0
end

-- Beschreibung zu einem Ausgangsnamen ("HDMI-A-1" -> "ASUSTek ..."). Noetig,
-- weil monitors.lua mit "desc:..." arbeitet, Aufrufer aber auch nur den
-- Namen kennen koennen.
local function description_of(name)
    for _, m in ipairs(hl.get_monitors() or {}) do
        if m.name == name then return m.description end
    end
    return nil
end

-- Eintrag in M.offsets finden. monitors.lua schreibt Monitore als
-- "desc:<Beschreibung>" (stabil ueber Steckplaetze), Hyprlands Lua-Objekt
-- liefert dagegen .name ("HDMI-A-1") und .description ("ASUSTek ...").
-- Beides muss treffen, sonst landet jeder Monitor bei 1-10.
local function lookup_offset(name, desc)
    if name and M.offsets[name] then return M.offsets[name] end
    if desc then
        if M.offsets["desc:" .. desc] then return M.offsets["desc:" .. desc] end
        -- Kleinschreibung/Leerzeichen am Rand sind harmlos verschieden.
        local want = desc:lower():gsub("^%s+", ""):gsub("%s+$", "")
        for output, offset in pairs(M.offsets) do
            local have = output:lower()
            if have:sub(1, 5) == "desc:" then have = have:sub(6) end
            have = have:gsub("^%s+", ""):gsub("%s+$", "")
            if have == want then return offset end
        end
    end
    return nil
end

-- Workspace-Versatz eines Monitors (Name oder Monitor-Tabelle) bzw. des
-- fokussierten (nil)
function M.offset(name)
    local desc
    if type(name) == "table" then
        desc, name = name.description, name.name
    elseif not name then
        local mon = hl.get_active_monitor()
        if mon then
            name, desc = mon.name, mon.description
        end
    end

    local offset = lookup_offset(name, desc)
    if offset then return offset end
    -- Nur der Name bekannt (monitors.lua nutzt "desc:..."): Beschreibung holen
    if name and not desc then
        offset = lookup_offset(nil, description_of(name))
        if offset then return offset end
    end
    -- Mit monitors.lua gilt nur, was dort steht; ein nicht eingetragener
    -- Monitor nimmt 1-10. Ohne Datei wird automatisch vergeben.
    if M.configured then return 0 end
    return auto_offset(name)
end

return M
