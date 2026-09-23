return {
	{
		"folke/flash.nvim",
		vscode = true,
		opts = {
			-- No forward/wrap overrides: with forward=true + wrap=false, `s` only ever
			-- labelled matches below the cursor. Defaults label both directions.
			--
			-- No `incremental` either. Top-level search opts are inherited by every
			-- mode, and in char mode (f/t/;/,) incremental makes each state update
			-- move the cursor back to the first match after where the search began
			-- (state.lua update_target) -- so f, ; and , jumped and snapped straight
			-- back, and repeats never advanced.
			search = {
				multi_window = false,
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
			-- Stubs so the first f/F/t/T/;/, loads flash. Its char mode (clever-f
			-- repeat, match highlighting) is installed by flash's own setup(), which
			-- with only the keys above never ran until s/S/r/R had been pressed --
			-- so f/t behaved like stock Vim for the first part of every session.
			{ "f", mode = { "n", "x", "o" } },
			{ "F", mode = { "n", "x", "o" } },
			{ "t", mode = { "n", "x", "o" } },
			{ "T", mode = { "n", "x", "o" } },
			{ ";", mode = { "n", "x", "o" } },
			{ ",", mode = { "n", "x", "o" } },
		},
	},
}
