-- monitors.lua - Bildschirme dieses Rechners (git-ignoriert).
-- Geschrieben von Dynamic Island (Einstellungen > Monitore); von Hand
-- bearbeiten geht weiter, die Seite liest die Datei beim Oeffnen neu.
-- Felder und Erklaerung: monitors.example.lua
--
-- workspaces = erster Workspace - 1 (0 -> 1-10, 10 -> 11-20, ...).

return {
    {
        output     = "desc:Chimei Innolux Corporation 0x150D",
        mode       = "1920x1080@60.01",
        position   = "103x805",
        scale      = 1,
        transform  = 0,
        vrr        = -1,
        workspaces = 0,
    },
    {
        output     = "desc:ASUSTek COMPUTER INC VG249Q3R T4LMDW011881",
        mode       = "1920x1080@180.06",
        position   = "2023x425",
        scale      = 1,
        transform  = 0,
        vrr        = -1,
        workspaces = 10,
    },
    {
        output     = "desc:Samsung Electric Company C24F390 H4ZT603261",
        mode       = "1920x1080@60.00",
        position   = "3943x425",
        scale      = 1,
        transform  = 0,
        vrr        = -1,
        workspaces = 20,
    },
    {
        output     = "desc:HP Inc. HP Z24n G2 6CM84211Q0",
        mode       = "1920x1200@59.95",
        position   = "103x-395",
        scale      = 1,
        transform  = 0,
        vrr        = -1,
        workspaces = 30,
    },
}
