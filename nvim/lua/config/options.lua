-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

opt.winborder = "rounded" -- Rahmen um LSP-Hover, Diagnosen & Co.
opt.scrolloff = 8
opt.fillchars:append({ eob = " ", diff = "╱", fold = " " })
opt.cursorlineopt = "both"
opt.pumheight = 12
opt.smoothscroll = true
-- Cursor im Einfuegemodus als Strich, sonst Block (blinkt leicht)
opt.guicursor = "n-v-c-sm:block-blinkwait300-blinkon200-blinkoff150,i-ci-ve:ver25,r-cr-o:hor20"
