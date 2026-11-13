-- monitors.example.lua — Vorlage fuer ~/.config/hypr/monitors.lua
--
-- monitors.lua beschreibt die Bildschirme DIESES Rechners und ist darum
-- git-ignoriert. install.sh legt sie aus den angeschlossenen Monitoren an
-- (Hyprland muss laufen); neu erzeugen mit:  ./install.sh --monitors
-- Von Hand: diese Datei nach monitors.lua kopieren und anpassen.
-- Namen der Ausgaenge:  hyprctl monitors
--
-- Jeder Eintrag sind die Felder von hl.monitor() (output, mode, position,
-- scale, vrr, transform, ...) plus:
--   workspaces = 0   dieser Monitor hat die Workspaces 1-10
--   workspaces = 10  dieser Monitor hat 11-20 (SUPER+1 springt hier nach 11)
--
-- Was nicht hier steht, bekommt "preferred / auto / auto" und Workspaces 1-10.
-- Fehlt die Datei ganz, verteilt monitor-setup.lua die Gruppen von links
-- nach rechts automatisch.

return {
    {
        output     = "HDMI-A-1",
        mode       = "2560x1440@60",
        position   = "0x0",
        scale      = 1,
        vrr        = false,
        workspaces = 0,   -- links: 1-10
    },
    {
        output     = "DP-2",
        mode       = "2560x1440@180",
        position   = "2560x0",
        scale      = 1,
        workspaces = 10,  -- rechts: 11-20
    },
    {
        output   = "eDP-1",   -- Laptop-Display
        mode     = "preferred",
        position = "auto",
        scale    = 1.25,
    },
}
