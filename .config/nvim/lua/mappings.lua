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

-- Exit terminal mode with double Esc
keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { noremap = true, silent = true, desc = "Exit terminal mode" })

-- Window navigation with Alt+hjkl handled by vim-tmux-navigator plugin

-- Move windows with leader+alt+hjkl
keymap.set("n", "<leader><A-h>", "<C-w><S-h>", { noremap = true, silent = true, desc = "Move window left" })
keymap.set("n", "<leader><A-j>", "<C-w><S-j>", { noremap = true, silent = true, desc = "Move window down" })
keymap.set("n", "<leader><A-k>", "<C-w><S-k>", { noremap = true, silent = true, desc = "Move window up" })
keymap.set("n", "<leader><A-l>", "<C-w><S-l>", { noremap = true, silent = true, desc = "Move window right" })

-- Toggle split orientation (vertical <-> horizontal), ignoring terminal windows
local function toggle_split_orientation()
	local editor_wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype ~= "terminal" then
			table.insert(editor_wins, win)
		end
	end

	if #editor_wins < 2 then
		vim.notify("Need at least 2 editor windows to toggle orientation", vim.log.levels.INFO)
		return
	end

	-- Detect layout: if all editor windows share the same column → stacked (hsplit) → switch to vsplit
	local all_same_col = true
	local first_col = vim.api.nvim_win_get_position(editor_wins[1])[2]
	for i = 2, #editor_wins do
		if vim.api.nvim_win_get_position(editor_wins[i])[2] ~= first_col then
			all_same_col = false
			break
		end
	end
	local split_cmd = all_same_col and "vsplit" or "split"

	-- Collect buffers in order
	local bufs = {}
	for _, win in ipairs(editor_wins) do
		table.insert(bufs, vim.api.nvim_win_get_buf(win))
	end

	-- Close all editor windows except the first, then re-split
	vim.api.nvim_set_current_win(editor_wins[1])
	for i = #editor_wins, 2, -1 do
		vim.api.nvim_win_close(editor_wins[i], false)
	end
	vim.api.nvim_win_set_buf(editor_wins[1], bufs[1])

	for i = 2, #bufs do
		vim.cmd(split_cmd)
		vim.api.nvim_win_set_buf(0, bufs[i])
	end
end

keymap.set(
	"n",
	"<leader>ws",
	toggle_split_orientation,
	{ noremap = true, silent = true, desc = "Toggle split orientation" }
)

-- Resize vertical splits
keymap.set(
	{ "n", "t" },
	"<C-Left>",
	"<cmd>vertical resize -3<CR>",
	{ noremap = true, silent = true, desc = "Shrink split width" }
)
keymap.set(
	{ "n", "t" },
	"<C-Right>",
	"<cmd>vertical resize +3<CR>",
	{ noremap = true, silent = true, desc = "Grow split width" }
)

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
local function wrap_functions_in_custom_fold(range)
	vim.cmd(range .. [[s/\(\(\w.*\)() {\)\( #{{{\)\?\(\_.\{-}}\)\n\(#}}}.*\n\)\?/\1 #{{{\4\r#}}}: \2\r/g]])
end

keymap.set("n", "<leader>wf", function()
	wrap_functions_in_custom_fold("%")
end, { noremap = true, silent = true, desc = "Wrap functions in fold markers" })

keymap.set("v", "<leader>wf", function()
	wrap_functions_in_custom_fold("'<,'>")
end, { noremap = true, silent = true, desc = "Wrap functions in fold markers" })

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

	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	if #lines == 0 then
		return
	end

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
		if not chosen_ft then
			return
		end
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

keymap.set("v", "<leader>op", function()
	open_selection_in_tmux("popup")
end, { noremap = true, silent = true, desc = "Open selection in tmux popup" })
keymap.set("v", "<leader>os", function()
	open_selection_in_tmux("hsplit")
end, { noremap = true, silent = true, desc = "Open selection in tmux h-split" })
keymap.set("v", "<leader>ov", function()
	open_selection_in_tmux("vsplit")
end, { noremap = true, silent = true, desc = "Open selection in tmux v-split" })

-- Undotree toggle
keymap.set("n", "<M-u>", ":UndotreeToggle<CR>", { noremap = true, silent = true, desc = "Toggle undotree" })

-- Comment boxes using 'boxes' command
keymap.set("v", "<leader>Bs", ":!boxes -d shell<CR>", { noremap = true, silent = true, desc = "Box (shell style)" })
keymap.set("n", "<leader>Bs", ":. !boxes -d shell<CR>", { noremap = true, silent = true, desc = "Box (shell style)" })
keymap.set("v", "<leader>Bt", ":!boxes -d jstone<CR>", { noremap = true, silent = true, desc = "Box (jstone style)" })
keymap.set("n", "<leader>Bt", ":. !boxes -d jstone<CR>", { noremap = true, silent = true, desc = "Box (jstone style)" })

-- Toggle inline diagnostics (virtual text)
keymap.set("n", "<leader>ud", function()
	local current = vim.diagnostic.config().virtual_text
	vim.diagnostic.config({
		virtual_text = not current and {
			spacing = 4,
			source = "if_many",
			prefix = "●",
		} or false,
	})
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

-- Insert inline ignore comment for diagnostic
keymap.set("n", "<leader>ui", function()
	local line = vim.api.nvim_win_get_cursor(0)[1] - 1
	local diagnostics = vim.diagnostic.get(0, { lnum = line })
	if #diagnostics == 0 then
		vim.notify("No diagnostics on this line", vim.log.levels.INFO)
		return
	end

	local function insert_ignore(diag)
		local source = (diag.source or ""):lower()
		local code = tostring(diag.code or "")
		local cur_line = vim.api.nvim_win_get_cursor(0)[1]
		local indent = vim.api.nvim_get_current_line():match("^(%s*)")

		-- above: insert a new line above with matching indentation
		-- eol: append comment to end of current line
		local comment, placement

		if source == "shellcheck" then
			comment = "# shellcheck disable=" .. code
			placement = "above"
		elseif source == "yamllint" then
			comment = "# yamllint disable-line rule:" .. code
			placement = "above"
		elseif source == "ruff" then
			comment = "# noqa: " .. code
			placement = "eol"
		elseif source == "pyright" then
			comment = "# type: ignore[" .. code .. "]"
			placement = "eol"
		elseif source == "eslint" then
			comment = "// eslint-disable-next-line " .. code
			placement = "above"
		elseif source == "lua_ls" or source == "lua diagnostics" then
			comment = "---@diagnostic disable-next-line: " .. code
			placement = "above"
		elseif source == "tflint" then
			comment = "# tflint-ignore: " .. code
			placement = "above"
		elseif source == "tfsec" then
			comment = "# tfsec:ignore:" .. code
			placement = "above"
		elseif source == "terraform_validate" then
			vim.notify("No inline ignore syntax for terraform_validate", vim.log.levels.WARN)
			return
		else
			vim.notify("Unknown source: " .. (diag.source or "nil") .. " (code: " .. code .. ")", vim.log.levels.WARN)
			return
		end

		if placement == "above" then
			vim.api.nvim_buf_set_lines(0, cur_line - 1, cur_line - 1, false, { indent .. comment })
		elseif placement == "eol" then
			local cur_text = vim.api.nvim_get_current_line()
			if cur_text:find(comment, 1, true) then
				vim.notify("Ignore comment already present", vim.log.levels.INFO)
				return
			end
			vim.api.nvim_set_current_line(cur_text .. "  " .. comment)
		end
	end

	if #diagnostics == 1 then
		insert_ignore(diagnostics[1])
	else
		vim.ui.select(diagnostics, {
			prompt = "Select diagnostic to ignore:",
			format_item = function(d)
				return (d.source or "?") .. " [" .. (d.code or "") .. "]: " .. d.message
			end,
		}, function(choice)
			if choice then
				insert_ignore(choice)
			end
		end)
	end
end, { noremap = true, silent = true, desc = "Insert inline ignore comment" })

-- Visual search and replace (old text prefilled from selection)
keymap.set("x", "<leader>r", function()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.fn.getregion(start_pos, end_pos, { type = vim.fn.visualmode() })
	local text = table.concat(lines, "\\n")
	-- Escape special regex characters for use in substitute pattern
	text = vim.fn.escape(text, "\\/.*~$^[]")
	local left = vim.api.nvim_replace_termcodes("<Left><Left>", true, false, true)
	vim.api.nvim_feedkeys(":%s/" .. text .. "//g" .. left, "n", false)
end, { noremap = true, silent = true, desc = "Replace visual selection" })

-- Quickfix/Location list clearing
keymap.set("n", "<leader>xcq", "<cmd>cexpr []<cr>", { noremap = true, silent = true, desc = "Clear Quickfix List" })
keymap.set("n", "<leader>xcl", "<cmd>lexpr []<cr>", { noremap = true, silent = true, desc = "Clear Location List" })

-- LSP keymaps are now handled in lsp.lua
-- Telescope keymaps will be handled in telescope.lua

-- Manual formatting with conform is now handled in editor.lua
