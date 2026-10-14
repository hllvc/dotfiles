return {
	-- Todo files: checkmate renders and edits the checkboxes and @tag(value) metadata of
	-- ~/.todo/{work,personal}.todo.md; lua/todo/ adds views, capture, triage and routing.
	{
		"bngarren/checkmate.nvim",
		version = "~0.12.0",
		ft = "markdown",
		init = function()
			require("todo").setup()
		end,
		opts = function()
			return {
				files = { vim.fn.expand("~/.todo") .. "/*.todo.md" },
				ui = { picker = "snacks" },
				-- Replaces checkmate's <leader>T defaults. Toggle (<CR>), scope, triage and the
				-- rest are buffer maps from lua/todo/init.lua.
				keys = {
					["<leader>tn"] = { rhs = "<cmd>Checkmate create<CR>", desc = "Todo: new", modes = { "n", "v" } },
					["<leader>tr"] = {
						rhs = "<cmd>Checkmate remove<CR>",
						desc = "Todo: remove marker",
						modes = { "n", "v" },
					},
					["<leader>ta"] = {
						rhs = "<cmd>Checkmate archive<CR>",
						desc = "Todo: archive completed",
						modes = { "n" },
					},
					["<leader>tv"] = {
						rhs = "<cmd>Checkmate metadata select_value<CR>",
						desc = "Todo: change tag value",
						modes = { "n" },
					},
				},
				metadata = require("todo.tags").checkmate_metadata(),
				-- Completed trees move under `## Archive` at the end of the file.
				archive = { heading = { title = "Archive", level = 2 }, newest_first = true },
			}
		end,
	},
}
