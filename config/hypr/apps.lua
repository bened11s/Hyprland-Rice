-- apps.lua — die erste installierte App aus einer Liste nehmen.
--
--   local pick = require("apps")
--   terminal = pick({ "kitty", "alacritty", "foot" })
--
-- Damit SUPER + Q & Co. auch auf einem Rechner etwas oeffnen, auf dem nicht
-- genau meine Apps installiert sind. Gesucht wird nur im PATH (ohne
-- Prozessstart, also billig bei jedem Reload). Ist keine da, bleibt der
-- erste Eintrag stehen – dann sieht man in `hyprctl binds`, was fehlt.

local function installed(cmd)
    local bin = cmd:match("^%S+")
    if not bin then return false end
    local candidates = {}
    if bin:find("/", 1, true) then
        candidates[1] = bin
    else
        for dir in (os.getenv("PATH") or ""):gmatch("[^:]+") do
            candidates[#candidates + 1] = dir .. "/" .. bin
        end
    end
    for _, path in ipairs(candidates) do
        local f = io.open(path)
        if f then
            f:close()
            return true
        end
    end
    return false
end

return function(list)
    for _, cmd in ipairs(list) do
        if installed(cmd) then return cmd end
    end
    return list[1]
end
