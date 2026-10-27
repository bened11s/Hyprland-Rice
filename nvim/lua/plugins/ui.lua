-- Optik: Dashboard, Statuszeile, Rahmen um Popups.

local header = [[
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝]]

local function subtitle()
  local v = vim.version()
  local host = vim.uv.os_gethostname():gsub("%..*", "")
  return ("── %s@%s · nvim %d.%d.%d ──"):format(vim.env.USER or "user", host, v.major, v.minor, v.patch)
end

return {
  -- Startseite: links Logo + Aktionen, rechts (bei genug Breite) Dateien,
  -- Projekte und Git-Status
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.header = header .. "\n\n" .. subtitle()
      opts.dashboard.sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 1 },
        { pane = 2, padding = 6 },
        { pane = 2, icon = " ", title = "Zuletzt geöffnet", section = "recent_files", indent = 2, padding = 1 },
        { pane = 2, icon = " ", title = "Projekte", section = "projects", indent = 2, padding = 1 },
        {
          pane = 2,
          icon = " ",
          title = "Git",
          section = "terminal",
          enabled = function()
            return Snacks.git.get_root() ~= nil
          end,
          cmd = "git status --short --branch --renames",
          height = 5,
          padding = 1,
          ttl = 5 * 60,
          indent = 3,
        },
        { section = "startup" },
      }

      opts.indent = vim.tbl_deep_extend("force", opts.indent or {}, {
        indent = { char = "│" },
        scope = { char = "│", underline = false },
      })
      opts.notifier = vim.tbl_deep_extend("force", opts.notifier or {}, { style = "fancy" })
    end,
  },

  -- Statuszeile in "Blasen": abgerundete Enden, keine Trennstriche
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options.component_separators = { left = "", right = "" }
      opts.options.section_separators = { left = "", right = "" }
      opts.sections.lualine_a = { { "mode", separator = { left = "", right = "" }, padding = { left = 0, right = 1 } } }
      opts.sections.lualine_z = {
        {
          function()
            return " " .. os.date("%H:%M")
          end,
          separator = { left = "", right = "" },
          padding = { left = 1, right = 0 },
        },
      }
    end,
  },

  -- Tabs oben: schlicht, aktiver Puffer unterstrichen
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        separator_style = "thin",
        indicator = { style = "underline" },
        show_buffer_close_icons = false,
        hover = { enabled = true, delay = 120, reveal = { "close" } },
      },
    },
  },

  -- Kommandozeile/Hover mit Rahmen
  {
    "folke/noice.nvim",
    opts = {
      presets = { lsp_doc_border = true },
    },
  },

  -- Vervollstaendigung mit Rahmen und Doku daneben
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        menu = { border = "rounded", scrollbar = false },
        documentation = { window = { border = "rounded" } },
      },
      signature = { window = { border = "rounded" } },
    },
  },

  { "folke/which-key.nvim", opts = { preset = "modern", win = { border = "rounded" } } },
  { "mason-org/mason.nvim", opts = { ui = { border = "rounded" } } },
}
