-- Modern Neovim Configuration in Lua
-- NvChad-inspired minimal structure

-- Set leader keys BEFORE loading lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Ensure backup directory exists
local backup_dir = vim.fn.expand("~/.nvim-backups")
if vim.fn.isdirectory(backup_dir) == 0 then
  vim.fn.mkdir(backup_dir, "p")
end

-- Load core configurations
require("options")
require("config")
require("autocmds")
require("mappings")
