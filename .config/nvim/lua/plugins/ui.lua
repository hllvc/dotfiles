return {
	-- Better vim.ui - using native input to avoid modal behavior
	{
		"stevearc/dressing.nvim",
		lazy = true,
		init = function()
			vim.ui.select = function(...)
				require("lazy").load({ plugins = { "dressing.nvim" } })
				return vim.ui.select(...)
			end
			vim.ui.input = function(...)
				require("lazy").load({ plugins = { "dressing.nvim" } })
				return vim.ui.input(...)
			end
		end,
	},

	-- Statusline
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = function()
			local lualine_require = require("lualine_require")
			lualine_require.require = require

			local auto_theme_custom = require("lualine.themes.auto")
			auto_theme_custom.normal.c.bg = "#1B1B1B"
			auto_theme_custom.insert.c.bg = "#1B1B1B"
			auto_theme_custom.visual.c.bg = "#1B1B1B"
			auto_theme_custom.replace.c.bg = "#1B1B1B"
			auto_theme_custom.command.c.bg = "#1B1B1B"
			auto_theme_custom.inactive.c.bg = "#1B1B1B"
			auto_theme_custom.terminal = auto_theme_custom.terminal or {}
			auto_theme_custom.terminal.c = auto_theme_custom.terminal.c or {}
			auto_theme_custom.terminal.c.bg = "#1B1B1B"

			return {
				options = {
					-- theme = "gruvbox-material",
					-- theme = "auto",
					theme = auto_theme_custom,
					globalstatus = true,
					disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
					component_separators = { left = "", right = "" },
				},
				winbar = {
					lualine_c = {
						{
							"buffers",
							mode = 0,
							show_filename_only = false,
							show_modified_status = false,
						},
					},
					lualine_x = {
						{
							"filetype",
							icon = {
								align = "right",
							},
						},
					},
				},
				inactive_winbar = {
					lualine_c = {
						{ "filename", path = 0, newfile_status = false },
					},
					lualine_x = {
						{ "location", padding = { left = 0, right = 1 } },
					},
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch" },
					lualine_c = {
						"diff",
						"diagnostics",
					},
					lualine_x = {},
					lualine_y = {},
					lualine_z = {},
				},
				inactive_sections = {},
				extensions = { "lazy" },
			}
		end,
	},

	-- Noice
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = {
			"MunifTanjim/nui.nvim",
		},
		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			routes = {
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "%d+L, %d+B" },
							{ find = "; after #%d+" },
							{ find = "; before #%d+" },
							{ find = "search hit BOTTOM" },
							{ find = "search hit TOP" },
							{ find = "Pattern not found" },
							{ find = "%d+ lines yanked" },
							{ find = "%d+ more lines" },
							{ find = "%d+ fewer lines" },
							{ find = '".+" %d+L, %d+B' },
							{ find = "%d+ lines indented" },
						},
					},
					view = "mini",
				},
				{
					filter = {
						event = "notify",
						find = "No information available",
					},
					opts = { skip = true },
				},
				{
					filter = {
						event = "msg_show",
						find = "^[/?].*",
					},
					view = "mini",
				},
			},
			presets = {
				bottom_search = true,
				command_palette = true,
				long_message_to_split = true,
				inc_rename = true,
			},
		},
		keys = {
			{
				"<S-Enter>",
				function()
					require("noice").redirect(vim.fn.getcmdline())
				end,
				mode = "c",
				desc = "Redirect Cmdline",
			},
			{
				"<leader>snl",
				function()
					require("noice").cmd("last")
				end,
				desc = "Noice Last Message",
			},
			{
				"<leader>snh",
				function()
					require("noice").cmd("history")
				end,
				desc = "Noice History",
			},
			{
				"<leader>sna",
				function()
					require("noice").cmd("all")
				end,
				desc = "Noice All",
			},
			{
				"<leader>snd",
				function()
					require("noice").cmd("dismiss")
				end,
				desc = "Dismiss All",
			},
			{
				"<c-f>",
				function()
					if not require("noice.lsp").scroll(4) then
						return "<c-f>"
					end
				end,
				silent = true,
				expr = true,
				desc = "Scroll forward",
				mode = { "i", "n", "s" },
			},
			{
				"<c-b>",
				function()
					if not require("noice.lsp").scroll(-4) then
						return "<c-b>"
					end
				end,
				silent = true,
				expr = true,
				desc = "Scroll backward",
				mode = { "i", "n", "s" },
			},
		},
	},

	-- Dashboard
	{
		"nvimdev/dashboard-nvim",
		event = "VimEnter",
		cond = function()
			return vim.fn.argc(-1) == 0
		end,
		opts = function()
			local logo = [[
           ██╗      █████╗ ███████╗██╗   ██╗██╗   ██╗██╗███╗   ███╗          Z
           ██║     ██╔══██╗╚══███╔╝╚██╗ ██╔╝██║   ██║██║████╗ ████║      Z
           ██║     ███████║  ███╔╝  ╚████╔╝ ██║   ██║██║██╔████╔██║   z
           ██║     ██╔══██║ ███╔╝    ╚██╔╝  ╚██╗ ██╔╝██║██║╚██╔╝██║ z
           ███████╗██║  ██║███████╗   ██║    ╚████╔╝ ██║██║ ╚═╝ ██║
           ╚══════╝╚═╝  ╚═╝╚══════╝   ╚═╝     ╚═══╝  ╚═╝╚═╝     ╚═╝
      ]]

			logo = string.rep("\n", 8) .. logo .. "\n\n"

			local opts = {
				theme = "doom",
				hide = {
					statusline = false,
				},
				config = {
					header = vim.split(logo, "\n"),
					center = {
						{ action = "Telescope find_files", desc = " Find file", icon = " ", key = "f" },
						{ action = "ene | startinsert", desc = " New file", icon = " ", key = "n" },
						{ action = "Telescope oldfiles", desc = " Recent files", icon = " ", key = "r" },
						{ action = "Telescope live_grep", desc = " Find text", icon = " ", key = "g" },
						{ action = "Lazy", desc = " Lazy", icon = "󰒲 ", key = "l" },
						{ action = "qa", desc = " Quit", icon = " ", key = "q" },
					},
					footer = function()
						local stats = require("lazy").stats()
						local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
						return {
							"⚡ Neovim loaded " .. stats.loaded .. "/" .. stats.count .. " plugins in " .. ms .. "ms",
						}
					end,
				},
			}

			for _, button in ipairs(opts.config.center) do
				button.desc = button.desc .. string.rep(" ", 43 - #button.desc)
				button.key_format = "  %s"
			end

			if vim.o.filetype == "lazy" then
				vim.cmd.close()
				vim.api.nvim_create_autocmd("User", {
					pattern = "DashboardLoaded",
					callback = function()
						require("lazy").show()
					end,
				})
			end

			return opts
		end,
	},

	-- Core UI dependencies
	{ "nvim-lua/plenary.nvim", lazy = true },
	{ "nvim-tree/nvim-web-devicons", lazy = true },
	{ "MunifTanjim/nui.nvim", lazy = true },

	-- Which-key
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "helix",
			plugins = { spelling = true },
			win = {
				no_overlap = true,
			},
			spec = {
				{ "g", group = "goto" },
				{ "gs", group = "surround" },
				{ "[", group = "prev" },
				{ "]", group = "next" },
				{ "<leader>a", group = "ai" },
				{ "<leader>b", group = "buffer" },
				{ "<leader>B", group = "box" },
				{ "<leader>c", group = "code" },
				{ "<leader>d", group = "debug" },
				{ "<leader>f", group = "file/find" },
				{ "<leader>sn", group = "noice" },
				{ "<leader>u", group = "ui" },
				{ "<leader>v", group = "venv" },
				{ "<leader>w", group = "workspace" },
				{ "<leader>x", group = "diagnostics/quickfix" },
			},
		},
	},

	-- Measure startuptime
	{
		"dstein64/vim-startuptime",
		cmd = "StartupTime",
		config = function()
			vim.g.startuptime_tries = 10
		end,
	},
}
