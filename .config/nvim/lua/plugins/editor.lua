return {
  -- Surround
  {
    "kylechui/nvim-surround",
    version = "*",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-surround").setup()
    end,
  },

  -- Auto pairs
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },

  -- Commenting
  {
    "numToStr/Comment.nvim",
    keys = {
      { "gcc", mode = "n", desc = "Comment toggle current line" },
      { "gc", mode = { "n", "o" }, desc = "Comment toggle linewise" },
      { "gc", mode = "x", desc = "Comment toggle linewise (visual)" },
      { "gbc", mode = "n", desc = "Comment toggle current block" },
      { "gb", mode = { "n", "o" }, desc = "Comment toggle blockwise" },
      { "gb", mode = "x", desc = "Comment toggle blockwise (visual)" },
    },
    config = function()
      require("Comment").setup({
        pre_hook = function(ctx)
          if vim.bo.filetype == "typescriptreact" or vim.bo.filetype == "javascriptreact" then
            local location = nil
            if ctx.ctype == require("Comment.utils").ctype.block then
              location = require("ts_context_commentstring.utils").get_cursor_location()
            elseif ctx.cmotion == require("Comment.utils").cmotion.v or ctx.cmotion == require("Comment.utils").cmotion.V then
              location = require("ts_context_commentstring.utils").get_visual_start_location()
            end
            return require("ts_context_commentstring.internal").calculate_commentstring({
              key = ctx.ctype == require("Comment.utils").ctype.line and "__default" or "__multiline",
              location = location,
            })
          end
        end,
      })
    end,
  },

  -- Context commentstring
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    lazy = true,
    opts = {
      enable_autocmd = false,
    },
  },

  -- Indent guides
  -- {
  --   "lukas-reineke/indent-blankline.nvim",
  --   event = { "BufReadPost", "BufNewFile" },
  --   opts = {
  --     indent = {
  --       char = "│",
  --       tab_char = "│",
  --     },
  --     scope = { enabled = false },
  --     exclude = {
  --       filetypes = {
  --         "help",
  --         "alpha",
  --         "dashboard",
  --         "Trouble",
  --         "trouble",
  --         "lazy",
  --         "mason",
  --         "notify",
  --         "toggleterm",
  --         "lazyterm",
  --       },
  --     },
  --   },
  --   main = "ibl",
  -- },

  -- Better text objects
  {
    "echasnovski/mini.ai",
    event = "VeryLazy",
    opts = function()
      local ai = require("mini.ai")
      return {
        n_lines = 500,
        custom_textobjects = {
          o = ai.gen_spec.treesitter({
            a = { "@block.outer", "@conditional.outer", "@loop.outer" },
            i = { "@block.inner", "@conditional.inner", "@loop.inner" },
          }, {}),
          f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }, {}),
          c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }, {}),
          t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</.-" },
        },
      }
    end,
  },

  -- Match tags
  -- {
  --   "gregsexton/MatchTag",
  --   ft = "html",
  -- },

  -- Auto close tags
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    opts = {},
  },

  -- Tabular
  {
    "godlygeek/tabular",
    cmd = "Tabularize",
  },

  -- Match up
  -- {
  --   "andymass/vim-matchup",
  --   event = { "BufReadPost", "BufNewFile" },
  --   init = function()
  --     vim.g.matchup_matchparen_offscreen = { method = "popup" }
  --     vim.g.matchup_surround_enabled = 1
  --   end,
  -- },

  -- Last place
  -- {
  --   "farmergreg/vim-lastplace",
  --   event = "BufReadPre",
  -- },

  -- Session management
  -- {
  --   "folke/persistence.nvim",
  --   event = "BufReadPre",
  --   opts = { options = vim.opt.sessionoptions:get() },
  --   keys = {
  --     {
  --       "<leader>qs",
  --       function()
  --         require("persistence").load()
  --       end,
  --       desc = "Restore Session",
  --     },
  --     {
  --       "<leader>ql",
  --       function()
  --         require("persistence").load({ last = true })
  --       end,
  --       desc = "Restore Last Session",
  --     },
  --     {
  --       "<leader>qd",
  --       function()
  --         require("persistence").stop()
  --       end,
  --       desc = "Don't Save Current Session",
  --     },
  --   },
  -- },

  -- Better diagnostics list and others
  {
    "folke/trouble.nvim",
    cmd = { "TroubleToggle", "Trouble" },
    opts = { use_diagnostic_signs = true },
    keys = {
      { "<leader>xx", "<cmd>TroubleToggle document_diagnostics<cr>", desc = "Document Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>TroubleToggle workspace_diagnostics<cr>", desc = "Workspace Diagnostics (Trouble)" },
      { "<leader>xL", "<cmd>TroubleToggle loclist<cr>", desc = "Location List (Trouble)" },
      { "<leader>xQ", "<cmd>TroubleToggle quickfix<cr>", desc = "Quickfix List (Trouble)" },
      {
        "[q",
        function()
          if require("trouble").is_open() then
            require("trouble").previous({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cprev)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "Previous trouble/quickfix item",
      },
      {
        "]q",
        function()
          if require("trouble").is_open() then
            require("trouble").next({ skip_groups = true, jump = true })
          else
            local ok, err = pcall(vim.cmd.cnext)
            if not ok then
              vim.notify(err, vim.log.levels.ERROR)
            end
          end
        end,
        desc = "Next trouble/quickfix item",
      },
    },
  },

  -- Todo comments
  {
    "folke/todo-comments.nvim",
    cmd = { "TodoTrouble", "TodoTelescope" },
    event = { "BufReadPost", "BufNewFile" },
    config = true,
    keys = {
      {
        "]t",
        function()
          require("todo-comments").jump_next()
        end,
        desc = "Next todo comment",
      },
      {
        "[t",
        function()
          require("todo-comments").jump_prev()
        end,
        desc = "Previous todo comment",
      },
      { "<leader>xt", "<cmd>TodoTrouble<cr>", desc = "Todo (Trouble)" },
      { "<leader>xT", "<cmd>TodoTrouble keywords=TODO,FIX,FIXME<cr>", desc = "Todo/Fix/Fixme (Trouble)" },
      { "<leader>st", "<cmd>TodoTelescope<cr>", desc = "Todo" },
      { "<leader>sT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>", desc = "Todo/Fix/Fixme" },
    },
  },

  -- Formatting
  {
    "stevearc/conform.nvim",
    dependencies = { "mason.nvim" },
    lazy = true,
    cmd = "ConformInfo",
    keys = {
      {
        "<leader>cfm",
        function()
          require("conform").format({ formatters = { "injected" } })
        end,
        mode = { "n", "v" },
        desc = "Format Injected Langs",
      },
    },
    init = function()
      vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
    end,
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "isort", "black" },
        javascript = { "prettierd", "prettier", stop_after_first = true },
        typescript = { "prettierd", "prettier", stop_after_first = true },
        javascriptreact = { "prettierd", "prettier", stop_after_first = true },
        typescriptreact = { "prettierd", "prettier", stop_after_first = true },
        json = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "prettierd", "prettier", stop_after_first = true },
        markdown = { "prettierd", "prettier", stop_after_first = true },
        html = { "prettierd", "prettier", stop_after_first = true },
        css = { "prettierd", "prettier", stop_after_first = true },
        xml = { "xmlformatter" },
      },
      format_on_save = { timeout_ms = 500, lsp_fallback = true },
      formatters = {
        injected = { options = { ignore_errors = true } },
      },
    },
  },
}
