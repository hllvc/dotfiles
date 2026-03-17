return {
	{
		"coder/claudecode.nvim",
		dependencies = { "folke/snacks.nvim" },
		event = "VeryLazy",
		keys = {
			{ "<leader>at", "<cmd>ClaudeCode<cr>", mode = "n", desc = "Toggle Claude" },
			{ "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
			{ "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
			{ "<leader>ac", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
			{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
			{ "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add buffer to Claude" },
			{ "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
			{ "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
			-- { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select model" },
		},

		opts = {
			terminal_cmd = "claude --permission-mode default --allow-dangerously-skip-permissions --model haiku --effort low",
			terminal = {
				split_with_percentage = 0.30,
				auto_close = true,
				snacks_win_opts = {
					wo = {
						winhighlight = "Normal:Normal,NormalNC:NormalNC,WinBar:SnacksWinBar,WinBarNC:SnacksWinBarNC",
					},
				},
			},
			diff_opts = {
				keep_terminal_focus = true,
			},
		},

		config = true,
	},
}
