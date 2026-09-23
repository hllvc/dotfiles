return {
	{
		"folke/flash.nvim",
		vscode = true,
		opts = {
			-- No forward/wrap overrides: with forward=true + wrap=false, `s` only ever
			-- labelled matches below the cursor. Defaults label both directions.
			--
			-- No `incremental` either: top-level search opts are inherited by every
			-- mode, and it made jumps snap back to the first match (state.lua
			-- update_target).
			search = {
				multi_window = false,
			},
			-- f/F/t/T/;/, stay stock Vim. flash's char mode (clever-f repeat, match
			-- highlighting) is off by choice -- plain f is more predictable.
			modes = {
				char = { enabled = false },
			},
		},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
			{
				"S",
				mode = { "n", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "Flash Treesitter",
			},
			{
				"r",
				mode = "o",
				function()
					require("flash").remote()
				end,
				desc = "Remote Flash",
			},
			{
				"R",
				mode = { "o", "x" },
				function()
					require("flash").treesitter_search()
				end,
				desc = "Treesitter Search",
			},
			{
				"<c-s>",
				mode = { "c" },
				function()
					require("flash").toggle()
				end,
				desc = "Toggle Flash Search",
			},
		},
	},
}
