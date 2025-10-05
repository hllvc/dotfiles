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
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    -- init = function()
    --   vim.g.lualine_laststatus = vim.o.laststatus
    --   if vim.fn.argc(-1) > 0 then
    --     vim.o.statusline = " "
    --   else
    --     vim.o.laststatus = 0
    --   end
    -- end,
    opts = function()
      local lualine_require = require("lualine_require")
      lualine_require.require = require

      -- vim.o.laststatus = vim.g.lualine_laststatus

      local auto_theme_custom = require('lualine.themes.auto')
      auto_theme_custom.normal.c.bg = "#1B1B1B"
      auto_theme_custom.insert.c.bg = "#1B1B1B"
      auto_theme_custom.visual.c.bg = "#1B1B1B"
      auto_theme_custom.replace.c.bg = "#1B1B1B"
      auto_theme_custom.command.c.bg = "#1B1B1B"
      auto_theme_custom.inactive.c.bg = "#1B1B1B"

      return {
        options = {
          -- theme = "gruvbox-material",
          -- theme = "auto",
          theme = auto_theme_custom,
          globalstatus = true,
          disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
          -- section_separators = { left = '', right = '' },
          component_separators = { left = '', right = '' }
        },
        tabline = {},
        winbar = {
          lualine_b = { "branch" },
          lualine_c = {
            {
              "filename",
              path = 1,
            },
            "diff",
            "diagnostics"
          },
          lualine_x = {
            {
              "filetype",
              icon = {
                align = 'right'
              }
            },
          }
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
          lualine_b = {
            {
              "buffers",
              mode = 0,
              show_modified_status = false,
            }
          },
          lualine_c = {},
          lualine_x = {},
          lualine_y = {},
          lualine_z = {}
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
      "rcarriga/nvim-notify",
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
      { "<S-Enter>",   function() require("noice").redirect(vim.fn.getcmdline()) end,                 mode = "c",                 desc = "Redirect Cmdline" },
      { "<leader>snl", function() require("noice").cmd("last") end,                                   desc = "Noice Last Message" },
      { "<leader>snh", function() require("noice").cmd("history") end,                                desc = "Noice History" },
      { "<leader>sna", function() require("noice").cmd("all") end,                                    desc = "Noice All" },
      { "<leader>snd", function() require("noice").cmd("dismiss") end,                                desc = "Dismiss All" },
      { "<c-f>",       function() if not require("noice.lsp").scroll(4) then return "<c-f>" end end,  silent = true,              expr = true,              desc = "Scroll forward",  mode = { "i", "n", "s" } },
      { "<c-b>",       function() if not require("noice.lsp").scroll(-4) then return "<c-b>" end end, silent = true,              expr = true,              desc = "Scroll backward", mode = { "i", "n", "s" } },
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
            { action = "e $MYVIMRC", desc = " Config", icon = " ", key = "c" },
            { action = 'lua require("persistence").load()', desc = " Restore Session", icon = " ", key = "s" },
            { action = "LazyExtras", desc = " Lazy Extras", icon = " ", key = "x" },
            { action = "Lazy", desc = " Lazy", icon = "󰒲 ", key = "l" },
            { action = "qa", desc = " Quit", icon = " ", key = "q" },
          },
          footer = function()
            local stats = require("lazy").stats()
            local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
            return { "⚡ Neovim loaded " .. stats.loaded .. "/" .. stats.count .. " plugins in " .. ms .. "ms" }
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
  { "nvim-lua/plenary.nvim",       lazy = true },
  { "nvim-tree/nvim-web-devicons", lazy = true },
  { "MunifTanjim/nui.nvim",        lazy = true },

  -- Notifications
  {
    "rcarriga/nvim-notify",
    keys = {
      {
        "<leader>un",
        function()
          require("notify").dismiss({ silent = true, pending = true })
        end,
        desc = "Dismiss all Notifications",
      },
    },
    opts = {
      timeout = 1000,
      max_height = function()
        return math.floor(vim.o.lines * 0.25)
      end,
      max_width = function()
        return math.floor(vim.o.columns * 0.4)
      end,
      level = vim.log.levels.WARN, -- Only show WARN and ERROR notifications
    },
    init = function()
      vim.notify = require("notify")
    end,
  },

  -- Which-key
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      plugins = { spelling = true },
      spec = {
        { "g",             group = "goto" },
        { "gs",            group = "surround" },
        { "]",             group = "next" },
        { "[",             group = "prev" },
        { "<leader><tab>", group = "tabs" },
        { "<leader>b",     group = "buffer" },
        { "<leader>c",     group = "code" },
        { "<leader>f",     group = "file/find" },
        { "<leader>g",     group = "git" },
        { "<leader>gd",    group = "diff/conflicts" },
        { "<leader>gh",    group = "hunks" },
        { "<leader>s",     group = "search" },
        { "<leader>u",     group = "ui" },
        { "<leader>w",     group = "windows" },
        { "<leader>x",     group = "diagnostics/quickfix" },
      },
    },
    config = function(_, opts)
      local wk = require("which-key")
      wk.setup(opts)
    end,
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
