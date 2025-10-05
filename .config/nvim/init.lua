-- Modern Neovim Configuration in Lua
-- NvChad-inspired minimal structure

-- Set leader keys BEFORE loading lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load core configurations
require("options")
require("config")
require("autocmds")
require("mappings")
