-- Keymaps
local keymap = vim.keymap
local opts = { noremap = true, silent = true }

-- Leader keys are now set in init.lua before lazy loads

-- Basic mappings
-- Disable space in normal mode to prevent cursor movement (space is leader key)
keymap.set("n", " ", "<Nop>", opts)
keymap.set("i", "jk", "<Esc>", opts)
keymap.set("i", "JK", "<Esc>", opts)
keymap.set("n", "<leader><leader>", ":w<CR>", opts)

-- Git conflict resolution (3-way merge)
-- keymap.set("n", "<leader>h", ":diffget //2<CR>", opts) -- choose left (HEAD/current branch)
-- keymap.set("n", "<leader>l", ":diffget //3<CR>", opts) -- choose right (incoming branch)
-- keymap.set("n", "<leader>g", ":Gvdiffsplit!<CR>", opts) -- open 3-way diff view
-- keymap.set("n", "<leader>gw", ":Gwrite<CR>", opts) -- stage current file

-- Window navigation with Alt+hjkl handled by vim-tmux-navigator plugin

-- Move windows with leader+alt+hjkl
keymap.set("n", "<leader><A-h>", "<C-w><S-h>", opts)
keymap.set("n", "<leader><A-j>", "<C-w><S-j>", opts)
keymap.set("n", "<leader><A-k>", "<C-w><S-k>", opts)
keymap.set("n", "<leader><A-l>", "<C-w><S-l>", opts)

-- Keep visual selection while indenting
keymap.set("v", "<", "<gv", opts)
keymap.set("v", ">", ">gv", opts)

-- Select what was pasted
keymap.set("n", "<Leader>p", "V`]", opts)

-- Next buffer
keymap.set("n", "L", ":bnext<CR>", opts)
keymap.set("n", "H", ":bprevious<CR>", opts)

-- Switch between current and last buffer
keymap.set("n", "<leader>l", "<C-^>", opts)

-- Close current buffer
keymap.set("n", "<Leader>bx", ":bdelete<CR>", opts)

-- Enable . command in visual mode
keymap.set("v", ".", ":normal .<CR>", opts)

-- Scroll the viewport faster
keymap.set("n", "<C-e>", "3<C-e>", opts)
keymap.set("n", "<C-y>", "3<C-y>", opts)

-- Text objects for inner-line (il) and around-line (al)
keymap.set("x", "il", ":<C-u>normal! g_v^<CR>", { silent = true })
keymap.set("o", "il", ":<C-u>normal! g_v^<CR>", { silent = true })
keymap.set("v", "al", ":<C-u>normal! $v0<CR>", { silent = true })
keymap.set("o", "al", ":<C-u>normal! $v0<CR>", { silent = true })

-- Wrap functions with custom fold markers
local function wrap_functions_in_custom_fold()
	vim.cmd([[%s/\(\(\w.*\)() {\)\( #{{{\)\?\(\_.\{-}}\)\n\(#}}}.*\n\)\?/\1 #{{{\4\r#}}}: \2\r/g]])
end

keymap.set("n", "<leader>wf", wrap_functions_in_custom_fold, opts)

-- Write with sudo
keymap.set("c", "w!!", "w !sudo tee % >/dev/null", { noremap = true })

-- Execute current .js file in Scriptable iOS app
local function exec_scriptable()
	local script = vim.fn.expand("%:t"):gsub("%.js$", "")
	vim.fn.system("open scriptable:///run/" .. script)
end

keymap.set("n", "<leader>E", exec_scriptable, opts)

-- Undotree toggle
keymap.set("n", "<M-u>", ":UndotreeToggle<CR>", opts)

-- Comment boxes using 'boxes' command
keymap.set("v", "<leader>bs", ":!boxes -d shell<CR>", opts) -- shell-style box
keymap.set("n", "<leader>bs", ":. !boxes -d shell<CR>", opts)
keymap.set("v", "<leader>bt", ":!boxes -d jstone<CR>", opts) -- jstone-style box
keymap.set("n", "<leader>bt", ":. !boxes -d jstone<CR>", opts)

-- LSP keymaps are now handled in lsp.lua
-- Telescope keymaps will be handled in telescope.lua

-- Manual formatting with conform
keymap.set({ "n", "v" }, "<leader>cf", function()
	require("conform").format({ lsp_fallback = true })
end, { desc = "Format buffer", noremap = true, silent = true })
