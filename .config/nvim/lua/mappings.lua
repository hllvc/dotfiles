-- Keymaps
local keymap = vim.keymap

-- Leader keys are now set in init.lua before lazy loads

-- Basic mappings
-- Disable space in normal mode to prevent cursor movement (space is leader key)
keymap.set("n", " ", "<Nop>", { noremap = true, silent = true })
keymap.set("i", "jk", "<Esc>", { noremap = true, silent = true, desc = "Exit insert mode" })
keymap.set("i", "JK", "<Esc>", { noremap = true, silent = true, desc = "Exit insert mode" })
keymap.set("s", "jk", "<Esc>", { noremap = true, silent = true, desc = "Exit select mode" })
keymap.set("s", "JK", "<Esc>", { noremap = true, silent = true, desc = "Exit select mode" })
keymap.set("n", "<leader><leader>", ":w<CR>", { noremap = true, silent = true, desc = "Save file" })

-- Window navigation with Alt+hjkl handled by vim-tmux-navigator plugin

-- Move windows with leader+alt+hjkl
keymap.set("n", "<leader><A-h>", "<C-w><S-h>", { noremap = true, silent = true, desc = "Move window left" })
keymap.set("n", "<leader><A-j>", "<C-w><S-j>", { noremap = true, silent = true, desc = "Move window down" })
keymap.set("n", "<leader><A-k>", "<C-w><S-k>", { noremap = true, silent = true, desc = "Move window up" })
keymap.set("n", "<leader><A-l>", "<C-w><S-l>", { noremap = true, silent = true, desc = "Move window right" })

-- Keep visual selection while indenting
keymap.set("x", "<", "<gv", { noremap = true, silent = true, desc = "Indent left and reselect" })
keymap.set("x", ">", ">gv", { noremap = true, silent = true, desc = "Indent right and reselect" })

-- Select what was pasted
keymap.set("n", "<Leader>p", "V`]", { noremap = true, silent = true, desc = "Select pasted text" })

-- Next buffer
keymap.set("n", "L", ":bnext<CR>", { noremap = true, silent = true, desc = "Next buffer" })
keymap.set("n", "H", ":bprevious<CR>", { noremap = true, silent = true, desc = "Previous buffer" })

-- Switch between current and last buffer
keymap.set("n", "<leader>l", "<C-^>", { noremap = true, silent = true, desc = "Last buffer" })

-- Close current buffer
keymap.set("n", "<Leader>bx", ":bdelete<CR>", { noremap = true, silent = true, desc = "Delete buffer" })

-- Enable . command in visual mode
keymap.set("x", ".", ":normal .<CR>", { noremap = true, silent = true, desc = "Repeat in visual mode" })

-- Scroll the viewport faster
keymap.set("n", "<C-e>", "3<C-e>", { noremap = true, silent = true, desc = "Scroll down 3 lines" })
keymap.set("n", "<C-y>", "3<C-y>", { noremap = true, silent = true, desc = "Scroll up 3 lines" })

-- Text objects for inner-line (il) and around-line (al)
keymap.set("x", "il", ":<C-u>normal! g_v^<CR>", { silent = true, desc = "Inner line" })
keymap.set("o", "il", ":<C-u>normal! g_v^<CR>", { silent = true, desc = "Inner line" })
keymap.set("x", "al", ":<C-u>normal! $v0<CR>", { silent = true, desc = "Around line" })
keymap.set("o", "al", ":<C-u>normal! $v0<CR>", { silent = true, desc = "Around line" })

-- Wrap functions with custom fold markers
local function wrap_functions_in_custom_fold()
	vim.cmd([[%s/\(\(\w.*\)() {\)\( #{{{\)\?\(\_.\{-}}\)\n\(#}}}.*\n\)\?/\1 #{{{\4\r#}}}: \2\r/g]])
end

keymap.set("n", "<leader>wf", wrap_functions_in_custom_fold, { noremap = true, silent = true, desc = "Wrap functions in fold markers" })

-- Write with sudo
keymap.set("c", "w!!", "w !sudo tee % >/dev/null", { noremap = true, desc = "Write with sudo" })

-- Execute current .js file in Scriptable iOS app
local function exec_scriptable()
	local script = vim.fn.expand("%:t"):gsub("%.js$", "")
	vim.fn.system("open scriptable:///run/" .. script)
end

keymap.set("n", "<leader>E", exec_scriptable, { noremap = true, silent = true, desc = "Run in Scriptable" })

-- Open visual selection in a new tmux nvim session
local ft_to_ext = {
  javascript = "js",
  typescript = "ts",
  typescriptreact = "tsx",
  javascriptreact = "jsx",
  python = "py",
  rust = "rs",
  ruby = "rb",
  markdown = "md",
  bash = "sh",
  cpp = "cpp",
  json = "json",
  yaml = "yml",
}

local function open_selection_in_tmux(mode)
  if not vim.env.TMUX then
    vim.notify("Not inside tmux", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false
  )

  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then return end

  local vmode = vim.fn.visualmode()
  if vmode == "v" then
    local start_col = vim.fn.col("'<")
    local end_col = vim.fn.col("'>")
    if #lines == 1 then
      lines[1] = lines[1]:sub(start_col, end_col)
    else
      lines[1] = lines[1]:sub(start_col)
      lines[#lines] = lines[#lines]:sub(1, end_col)
    end
  end

  local ft = vim.bo.filetype
  local fts = vim.fn.getcompletion("", "filetype")
  -- Move current filetype to top
  for i, v in ipairs(fts) do
    if v == ft then
      table.remove(fts, i)
      table.insert(fts, 1, ft)
      break
    end
  end

  vim.ui.select(fts, { prompt = "Filetype:" }, function(chosen_ft)
    if not chosen_ft then return end
    local ext = ft_to_ext[chosen_ft] or chosen_ft
    local tmpfile = vim.fn.tempname() .. "." .. ext
    vim.fn.writefile(lines, tmpfile)

    local cmd
    if mode == "popup" then
      cmd = string.format("tmux popup -E -w80%% -h80%% nvim %s", vim.fn.shellescape(tmpfile))
    elseif mode == "vsplit" then
      cmd = string.format("tmux split-window -h nvim %s", vim.fn.shellescape(tmpfile))
    else
      cmd = string.format("tmux split-window -v nvim %s", vim.fn.shellescape(tmpfile))
    end
    vim.fn.system(cmd)
  end)
end

keymap.set("v", "<leader>op", function() open_selection_in_tmux("popup") end,
  { noremap = true, silent = true, desc = "Open selection in tmux popup" })
keymap.set("v", "<leader>os", function() open_selection_in_tmux("hsplit") end,
  { noremap = true, silent = true, desc = "Open selection in tmux h-split" })
keymap.set("v", "<leader>ov", function() open_selection_in_tmux("vsplit") end,
  { noremap = true, silent = true, desc = "Open selection in tmux v-split" })

-- Undotree toggle
keymap.set("n", "<M-u>", ":UndotreeToggle<CR>", { noremap = true, silent = true, desc = "Toggle undotree" })

-- Comment boxes using 'boxes' command
keymap.set("v", "<leader>bs", ":!boxes -d shell<CR>", { noremap = true, silent = true, desc = "Box (shell style)" })
keymap.set("n", "<leader>bs", ":. !boxes -d shell<CR>", { noremap = true, silent = true, desc = "Box (shell style)" })
keymap.set("v", "<leader>bt", ":!boxes -d jstone<CR>", { noremap = true, silent = true, desc = "Box (jstone style)" })
keymap.set("n", "<leader>bt", ":. !boxes -d jstone<CR>", { noremap = true, silent = true, desc = "Box (jstone style)" })

-- Toggle inline diagnostics (virtual text)
keymap.set("n", "<leader>ud", function()
  local current = vim.diagnostic.config().virtual_text
  vim.diagnostic.config({ virtual_text = not current and {
    spacing = 4,
    source = "if_many",
    prefix = "●",
  } or false })
end, { noremap = true, silent = true, desc = "Toggle inline diagnostics" })

-- Toggle diagnostics underline highlights
keymap.set("n", "<leader>uu", function()
  local current = vim.diagnostic.config().underline
  vim.diagnostic.config({ underline = not current })
end, { noremap = true, silent = true, desc = "Toggle diagnostics underline" })

-- Toggle diagnostics hover popup
keymap.set("n", "<leader>uh", function()
  vim.g.diagnostics_hover = not vim.g.diagnostics_hover
end, { noremap = true, silent = true, desc = "Toggle diagnostics hover" })

-- LSP keymaps are now handled in lsp.lua
-- Telescope keymaps will be handled in telescope.lua

-- Manual formatting with conform is now handled in editor.lua
