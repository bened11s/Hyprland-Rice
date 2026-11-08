-- catppuccin, eingefaerbt mit dem dynamic-island-Schema.
--
-- Die Palette kommt aus ~/.local/state/dynamic-island/theme/nvim.lua (Vorlage:
-- ~/.config/dynamic-island/templates/nvim.lua). Fehlt die Datei, bleibt es beim
-- normalen catppuccin mocha. Laufende Instanzen beobachten das Theme-Verzeichnis
-- und faerben sich beim Wallpaper-/Themenwechsel sofort um.
--
-- Hintergrund ist transparent (kitty background_opacity scheint durch), Floats
-- behalten eine eigene Flaeche - kitty zeichnet explizite Hintergruende deckend,
-- so bleiben Popups ueber dem Wallpaper lesbar. <leader>uo schaltet um.

local theme_dir = vim.fn.expand("~/.local/state/dynamic-island/theme")
local theme_file = theme_dir .. "/nvim.lua"

local transparent = true
local base_opts -- von LazyVim zusammengefuehrte opts, Grundlage fuer jedes Neuladen

local function load_theme()
  local ok, theme = pcall(dofile, theme_file)
  if ok and type(theme) == "table" and type(theme.palette) == "table" then
    return theme
  end
end

-- Alles, was vom Schema abhaengt. Bewusst nur Tabellen (keine Funktionen),
-- damit catppuccins Cache-Hash nur bei echten Farbwechseln neu kompiliert.
local function theme_opts(theme)
  local opts = { transparent_background = transparent }
  if not theme then
    return opts
  end

  local p, a = theme.palette, theme.accent or {}
  opts.flavour = theme.mode == "light" and "latte" or "mocha"
  opts.color_overrides = { all = p }
  opts.custom_highlights = {
    CursorLineNr = { fg = a.primary, bold = true },
    LineNr = { fg = p.overlay0 },
    Visual = { bg = a.secondaryContainer, fg = a.onSecondaryContainer },
    WinSeparator = { fg = a.outlineVariant },
    FloatBorder = { fg = a.primary, bg = p.mantle },
    FloatTitle = { fg = a.onPrimary, bg = a.primary, bold = true },
    BlinkCmpMenuSelection = { bg = a.primaryContainer, fg = a.onPrimaryContainer, bold = true },
    SnacksIndentScope = { fg = a.primary },
    SnacksDashboardHeader = { fg = a.primary, bold = true },
    SnacksDashboardIcon = { fg = a.tertiary },
    SnacksDashboardKey = { fg = a.secondary, bold = true },
    SnacksDashboardDesc = { fg = p.text },
    SnacksDashboardTitle = { fg = a.primary, bold = true },
    SnacksDashboardFooter = { fg = p.overlay1, italic = true },
    SnacksDashboardSpecial = { fg = a.tertiary },
    TreesitterContextBottom = { underline = true, sp = a.outlineVariant },
  }
  return opts
end

local function apply()
  if not base_opts then
    return
  end
  local theme = load_theme()
  local opts = vim.tbl_deep_extend("force", vim.deepcopy(base_opts), theme_opts(theme))
  require("catppuccin").setup(opts)
  if theme then
    vim.o.background = theme.mode == "light" and "light" or "dark"
  end
  if (vim.g.colors_name or ""):find("^catppuccin") then
    vim.cmd.colorscheme("catppuccin")
  end
end

local function watch()
  local fs = vim.uv.new_fs_event()
  local timer = vim.uv.new_timer()
  if not fs or not timer or not vim.uv.fs_stat(theme_dir) then
    return
  end
  -- atomic_write legt erst eine Temp-Datei an und benennt sie dann um ->
  -- mehrere Events pro Wechsel, daher kurz entprellen.
  fs:start(theme_dir, {}, function(err, fname)
    if err or fname ~= "nvim.lua" then
      return
    end
    timer:stop()
    timer:start(150, 0, vim.schedule_wrap(apply))
  end)
end

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      float = { transparent = false, solid = false },
      term_colors = true,
      styles = {
        comments = { "italic" },
        conditionals = { "italic" },
        keywords = { "bold" },
        functions = { "bold" },
        types = { "italic" },
      },
      integrations = {
        blink_cmp = { enabled = true, style = "bordered" },
        render_markdown = true,
        snacks = { enabled = true, indent_scope_color = "lavender" },
        mini = { enabled = true, indentscope_color = "lavender" },
      },
    },
    config = function(_, opts)
      base_opts = opts
      apply()
      watch()

      -- Snacks steht beim Laden des Colorschemes noch nicht sicher bereit
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          Snacks.toggle({
            name = "Transparenz",
            get = function()
              return transparent
            end,
            set = function(state)
              transparent = state
              apply()
            end,
          }):map("<leader>uo")
        end,
      })

      vim.api.nvim_create_user_command("IslandTheme", apply, { desc = "dynamic-island-Palette neu laden" })
    end,
  },

  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
}
