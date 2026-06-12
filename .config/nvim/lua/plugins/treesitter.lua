return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		version = false,
		lazy = false,
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter").setup({})

			require("nvim-treesitter").install({
				"bash",
				"css",
				"dockerfile",
				"go",
				"gotmpl",
				"html",
				"javascript",
				"json",
				"lua",
				"markdown",
				"markdown_inline",
				"python",
				"query",
				"rust",
				"terraform",
				"typescript",
				"tsx",
				"vim",
				"vimdoc",
				"yaml",
			})

			-- Indent via treesitter
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("ts_indent", { clear = true }),
				callback = function()
					if pcall(vim.treesitter.get_parser) then
						vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})

			-- Incremental selection using the core treesitter API. A stack of selected node
			-- ranges drives both directions: <C-space> walks UP to a strictly-larger node and
			-- pushes it; <BS> pops back to the previous (smaller) one. (The old version broke
			-- in both directions: grow stalled on the leaf, and shrink recomputed from the
			-- start corner and never actually shrank.)
			local sel_stack = {}

			local function select_range(sr, sc, er, ec)
				-- Drop to normal first so `normal! v` reliably ENTERS visual; when already in a
				-- visual selection (grow/shrink) a bare `v` would toggle it off instead.
				local m = vim.fn.mode()
				if m == "v" or m == "V" or m == "\22" then
					vim.cmd("normal! \27")
				end
				vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
				vim.cmd("normal! v")
				vim.api.nvim_win_set_cursor(0, { er + 1, math.max(ec - 1, 0) })
			end

			-- Smallest node strictly larger than the (0-indexed) range (sr,sc)-(er,ec).
			local function larger_node(sr, sc, er, ec)
				local node = vim.treesitter.get_node({ pos = { sr, sc } })
				while node do
					local nsr, nsc, ner, nec = node:range()
					local starts_le = nsr < sr or (nsr == sr and nsc <= sc)
					local ends_ge = ner > er or (ner == er and nec >= ec)
					local strictly = nsr ~= sr or nsc ~= sc or ner ~= er or nec ~= ec
					if starts_le and ends_ge and strictly then
						return node
					end
					node = node:parent()
				end
				return nil
			end

			vim.keymap.set({ "n", "x" }, "<C-space>", function()
				local node
				if vim.fn.mode() == "n" or #sel_stack == 0 then
					sel_stack = {}
					node = vim.treesitter.get_node()
				else
					-- Grow from the current node range on the stack (not the visual selection,
					-- which is one column short of the node, so it would re-pick the leaf).
					local cur = sel_stack[#sel_stack]
					node = larger_node(cur[1], cur[2], cur[3], cur[4])
				end
				if not node then
					return
				end
				local sr, sc, er, ec = node:range()
				sel_stack[#sel_stack + 1] = { sr, sc, er, ec }
				select_range(sr, sc, er, ec)
			end, { desc = "Increment selection" })

			vim.keymap.set("x", "<BS>", function()
				-- Pop the current level and re-select the previous (smaller) one.
				if #sel_stack <= 1 then
					return
				end
				table.remove(sel_stack)
				local prev = sel_stack[#sel_stack]
				select_range(prev[1], prev[2], prev[3], prev[4])
			end, { desc = "Decrement selection" })
		end,
	},

	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		config = function()
			local ts_textobjects = require("nvim-treesitter-textobjects")
			ts_textobjects.setup({
				select = { lookahead = true },
				move = { set_jumps = true },
			})

			local select = require("nvim-treesitter-textobjects.select")
			local move = require("nvim-treesitter-textobjects.move")

			-- Select textobjects
			for lhs, query in pairs({
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",
				["aa"] = "@parameter.outer",
				["ia"] = "@parameter.inner",
			}) do
				vim.keymap.set({ "x", "o" }, lhs, function()
					select.select_textobject(query)
				end, { desc = "Select " .. query })
			end

			-- Move: next start
			for lhs, query in pairs({
				["]m"] = "@function.outer",
				["]]"] = "@class.outer",
			}) do
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					move.goto_next_start(query)
				end, { desc = "Next " .. query .. " start" })
			end

			-- Move: next end
			for lhs, query in pairs({
				["]M"] = "@function.outer",
				["]["] = "@class.outer",
			}) do
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					move.goto_next_end(query)
				end, { desc = "Next " .. query .. " end" })
			end

			-- Move: previous start
			for lhs, query in pairs({
				["[m"] = "@function.outer",
				["[["] = "@class.outer",
			}) do
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					move.goto_previous_start(query)
				end, { desc = "Prev " .. query .. " start" })
			end

			-- Move: previous end
			for lhs, query in pairs({
				["[M"] = "@function.outer",
				["[]"] = "@class.outer",
			}) do
				vim.keymap.set({ "n", "x", "o" }, lhs, function()
					move.goto_previous_end(query)
				end, { desc = "Prev " .. query .. " end" })
			end
		end,
	},
}
