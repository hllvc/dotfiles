local function claude_telescope(builtin, opts)
	return function()
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")
		opts = vim.tbl_deep_extend("force", opts or {}, {
			attach_mappings = function(prompt_bufnr, map)
				local add_to_claude = function()
					local picker = action_state.get_current_picker(prompt_bufnr)
					local selections = picker:get_multi_selection()
					if #selections == 0 then
						selections = { action_state.get_selected_entry() }
					end
					actions.close(prompt_bufnr)
					local claudecode = require("claudecode")
					for _, entry in ipairs(selections) do
						if entry.path then
							claudecode.send_at_mention(entry.path)
						end
					end
				end
				map("i", "<cr>", add_to_claude)
				map("n", "<cr>", add_to_claude)
				return true
			end,
		})
		require("telescope.builtin")[builtin](opts)
	end
end

return {
	{
		"coder/claudecode.nvim",
		-- event = "VeryLazy",
		keys = {
			{ "<C-,>", "<cmd>ClaudeCode<cr>", mode = "t", desc = "Toggle Claude" },
			{ "<C-,>", "<cmd>ClaudeCodeFocus<cr>", mode = "n", desc = "Focus Claude" },
			{ "<C-,>", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
			{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
			{ "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
			{ "<leader>ac", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
			{ "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
			{ "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
			{ "<leader>af", claude_telescope("find_files"), desc = "Claude: Add Files" },
			{ "<leader>ag", claude_telescope("live_grep"), desc = "Claude: Add Grep" },
			{ "<leader>ab", claude_telescope("buffers"), desc = "Claude: Add Buffers" },
			{ "<leader>aG", claude_telescope("git_files"), desc = "Claude: Add Git Files" },
		},

		opts = {
			terminal_cmd = "claude --permission-mode default --allow-dangerously-skip-permissions --model default --effort medium",

			-- Terminal Configuration
			terminal = {
				provider = "native",
				split_width_percentage = 0.40,
				auto_close = true,
			},

			-- Diff Integration
			diff_opts = {
				keep_terminal_focus = true,
			},
		},

		config = true,
	},
}
