-- Neovim-Palette aus dem aktuellen Schema.
--
-- Vorlage:  ~/.config/dynamic-island/templates/nvim.lua   <- diese Datei
-- Erzeugt:  ~/.local/state/dynamic-island/theme/nvim.lua  <- nicht bearbeiten
-- Geladen:  ~/.config/nvim/lua/plugins/colorscheme.lua (catppuccin
--           color_overrides); laufende nvim-Instanzen beobachten die Datei
--           und faerben sich beim Themenwechsel sofort um.
--
-- Das Schema bringt die catppuccin-Namen schon mit, dazu die Material-Rollen
-- fuer Akzente (Cursorzeile, Statuszeile, Rahmen).

return {
  mode = "{{ mode }}",
  palette = {
    rosewater = "#{{ rosewater.hex }}",
    flamingo = "#{{ flamingo.hex }}",
    pink = "#{{ pink.hex }}",
    mauve = "#{{ mauve.hex }}",
    red = "#{{ red.hex }}",
    maroon = "#{{ maroon.hex }}",
    peach = "#{{ peach.hex }}",
    yellow = "#{{ yellow.hex }}",
    green = "#{{ green.hex }}",
    teal = "#{{ teal.hex }}",
    sky = "#{{ sky.hex }}",
    sapphire = "#{{ sapphire.hex }}",
    blue = "#{{ blue.hex }}",
    lavender = "#{{ lavender.hex }}",
    text = "#{{ text.hex }}",
    subtext1 = "#{{ subtext1.hex }}",
    subtext0 = "#{{ subtext0.hex }}",
    overlay2 = "#{{ overlay2.hex }}",
    overlay1 = "#{{ overlay1.hex }}",
    overlay0 = "#{{ overlay0.hex }}",
    surface2 = "#{{ surface2.hex }}",
    surface1 = "#{{ surface1.hex }}",
    surface0 = "#{{ surface0.hex }}",
    base = "#{{ base.hex }}",
    mantle = "#{{ mantle.hex }}",
    crust = "#{{ crust.hex }}",
  },
  accent = {
    primary = "#{{ primary.hex }}",
    onPrimary = "#{{ onPrimary.hex }}",
    primaryContainer = "#{{ primaryContainer.hex }}",
    onPrimaryContainer = "#{{ onPrimaryContainer.hex }}",
    secondary = "#{{ secondary.hex }}",
    secondaryContainer = "#{{ secondaryContainer.hex }}",
    onSecondaryContainer = "#{{ onSecondaryContainer.hex }}",
    tertiary = "#{{ tertiary.hex }}",
    outline = "#{{ outline.hex }}",
    outlineVariant = "#{{ outlineVariant.hex }}",
    surfaceContainer = "#{{ surfaceContainer.hex }}",
    surfaceContainerHigh = "#{{ surfaceContainerHigh.hex }}",
  },
}
