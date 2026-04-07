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
				callback = function()
					if pcall(vim.treesitter.get_parser) then
						vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})

			-- Incremental selection using core treesitter API
			local function get_visual_range()
				local _, sr, sc, _ = unpack(vim.fn.getpos("v"))
				local _, er, ec, _ = unpack(vim.fn.getpos("."))
				if sr > er or (sr == er and sc > ec) then
					sr, sc, er, ec = er, ec, sr, sc
				end
				return sr - 1, sc - 1, er - 1, ec - 1
			end

			vim.keymap.set({ "n", "x" }, "<C-space>", function()
				local node
				if vim.fn.mode() == "n" then
					node = vim.treesitter.get_node()
					if not node then
						return
					end
				else
					local sr, sc, er, ec = get_visual_range()
					node = vim.treesitter.get_node({ pos = { sr, sc } })
					if not node then
						return
					end
					-- Find the smallest node that fully contains the current selection
					while node do
						local nsr, nsc, ner, nec = node:range()
						if nsr < sr or (nsr == sr and nsc <= sc and (ner > er or (ner == er and nec > ec))) then
							break
						end
						if
							nsr <= sr
							and nsc <= sc
							and ner >= er
							and nec >= ec
							and (nsr < sr or nsc < sc or ner > er or nec > ec)
						then
							break
						end
						node = node:parent()
					end
					if not node then
						return
					end
				end
				local sr, sc, er, ec = node:range()
				vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
				vim.cmd("normal! v")
				vim.api.nvim_win_set_cursor(0, { er + 1, math.max(ec - 1, 0) })
			end, { desc = "Increment selection" })

			vim.keymap.set("x", "<BS>", function()
				local sr, sc, _, _ = get_visual_range()
				local node = vim.treesitter.get_node({ pos = { sr, sc } })
				if not node then
					return
				end
				local parent = node:parent()
				if not parent then
					vim.cmd("normal! \27") -- escape to normal mode
					return
				end
				local psr, psc, per, pec = parent:range()
				-- If parent is same range, keep going up
				local nsr, nsc, ner, nec = node:range()
				while parent and psr == nsr and psc == nsc and ner == per and nec == pec do
					parent = parent:parent()
					if parent then
						psr, psc, per, pec = parent:range()
					end
				end
				if not parent then
					vim.cmd("normal! \27")
					return
				end
				-- Select the child node (shrink)
				vim.api.nvim_win_set_cursor(0, { nsr + 1, nsc })
				vim.cmd("normal! v")
				vim.api.nvim_win_set_cursor(0, { ner + 1, math.max(nec - 1, 0) })
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
