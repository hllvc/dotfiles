-- Modern Neovim Configuration in Lua
-- NvChad-inspired minimal structure

-- The exact Neovim release this config is written against. Realign it with the
-- installed binary on every config change (see CLAUDE.md); the check at the
-- bottom of this file warns when the two drift apart.
vim.g.nvim_target_version = "0.12.5"

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

-- Drift check: the running Neovim outpacing the target above is the cue to re-read
-- that release's `:help news`, close whatever gaps it opened, then bump the target.
-- Scheduled so it costs nothing on the startup path. Silence with
-- `vim.g.nvim_version_check = false`.
vim.schedule(function()
	if vim.g.nvim_version_check == false then
		return
	end
	local v = vim.version()
	local running = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	if running ~= vim.g.nvim_target_version then
		vim.notify(
			string.format(
				"Neovim %s != config target %s - realign the config, then bump vim.g.nvim_target_version",
				running,
				vim.g.nvim_target_version
			),
			vim.log.levels.WARN
		)
	end
end)
