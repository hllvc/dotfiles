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
    config = function()
      local npairs = require("nvim-autopairs")
      local Rule = require("nvim-autopairs.rule")
      local cond = require("nvim-autopairs.conds")

      -- Setup nvim-autopairs with default options
      npairs.setup({})

      -- Define the brackets you want this behavior for
      local brackets = { { "(", ")" }, { "[", "]" }, { "{", "}" } }

      -- Add rule for space inside brackets
      npairs.add_rules({
        Rule(" ", " ")
          :with_pair(function(opts)
            -- Check if we are inserting a space inside (), [], or {}
            local pair = opts.line:sub(opts.col - 1, opts.col)
            return vim.tbl_contains({
              brackets[1][1] .. brackets[1][2], -- ()
              brackets[2][1] .. brackets[2][2], -- []
              brackets[3][1] .. brackets[3][2], -- {}
            }, pair)
          end)
          :with_move(cond.none())
          :with_cr(cond.none())
          -- Delete both spaces when cursor is between them: ( | )
          :with_del(function(opts)
            local col = vim.api.nvim_win_get_cursor(0)[2]
            local context = opts.line:sub(col - 1, col + 2)
            return vim.tbl_contains({
              brackets[1][1] .. "  " .. brackets[1][2], -- (  )
              brackets[2][1] .. "  " .. brackets[2][2], -- [  ]
              brackets[3][1] .. "  " .. brackets[3][2], -- {  }
            }, context)
          end),
      })

      -- Add rules for moving past closing brackets with spaces
      for _, bracket in pairs(brackets) do
        npairs.add_rules({
          Rule(bracket[1] .. " ", " " .. bracket[2])
            :with_pair(cond.none())
            :with_move(function(opts)
              return opts.char == bracket[2]
            end)
            :with_del(cond.none())
            :use_key(bracket[2]),
        })
      end
    end,
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
  {
    "andymass/vim-matchup",
    event = { "BufReadPost", "BufNewFile" },
    init = function()
      vim.g.matchup_matchparen_offscreen = { method = "popup" }
      vim.g.matchup_surround_enabled = 1
    end,
  },

  -- Better diagnostics list and others
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = {
      keys = {
        h = "fold_close",
        l = "fold_open",
        ["<esc>"] = "close",
      },
      win = {
        wo = {
          winhighlight = "Normal:Normal,NormalNC:Normal,SignColumn:Normal,EndOfBuffer:Normal",
        },
      },
      modes = {
        symbols = {
          win = { size = 0.3 },
        },
        lsp = {
          win = { size = 0.3 },
        },
      },
    },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle focus=true filter.buf=0<cr>", desc = "Document Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle focus=true<cr>", desc = "Workspace Diagnostics (Trouble)" },
      { "<leader>xL", "<cmd>Trouble loclist toggle focus=true<cr>", desc = "Location List (Trouble)" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle focus=true<cr>", desc = "Quickfix List (Trouble)" },
      { "<leader>xs", "<cmd>Trouble symbols toggle focus=true<cr>", desc = "Symbols (Trouble)" },
      { "<leader>xl", "<cmd>Trouble lsp toggle focus=true win.position=right<cr>", desc = "LSP Definitions / references / ... (Trouble)" },
      {
        "[q",
        function()
          if require("trouble").is_open() then
            require("trouble").prev({ skip_groups = true, jump = true })
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
    cmd = "ConformInfo",
    event = "BufWritePre",
    keys = {
      {
        "<leader>F",
        function()
          require("conform").format({ lsp_format = "fallback", timeout_ms = 3000 })
        end,
        mode = { "n", "v" },
        desc = "Format buffer/selection",
      },
      {
        "<leader>cF",
        function()
          require("conform").format({ formatters = { "injected" } })
        end,
        mode = { "n", "v" },
        desc = "Format Injected Langs",
      },
      {
        "<leader>ci",
        "<cmd>ConformInfo<cr>",
        desc = "Conform Info",
      },
      {
        "<leader>cf",
        function()
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false
          )

          local conform = require("conform")

          local fts = {}
          for ft, _ in pairs(conform.formatters_by_ft) do
            if ft ~= "*" and ft ~= "_" then
              table.insert(fts, ft)
            end
          end
          table.sort(fts)

          vim.ui.select(fts, { prompt = "Format as:" }, function(chosen_ft)
            if not chosen_ft then return end

            local buf = vim.api.nvim_get_current_buf()
            local start_line = vim.fn.line("'<")
            local end_line = vim.fn.line("'>")
            local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
            if #lines == 0 then return end

            -- Detect and strip base indentation
            local min_indent = math.huge
            for _, line in ipairs(lines) do
              if line:match("%S") then
                min_indent = math.min(min_indent, #(line:match("^(%s*)")))
              end
            end
            if min_indent == math.huge then min_indent = 0 end

            local stripped = {}
            for _, line in ipairs(lines) do
              table.insert(stripped, line:sub(min_indent + 1))
            end
            local base_indent = lines[1]:sub(1, min_indent)

            local had_trailing_empty = lines[#lines] == ""

            -- Create scratch buffer with target filetype
            local tmp_buf = vim.api.nvim_create_buf(false, true)
            vim.bo[tmp_buf].filetype = chosen_ft
            vim.bo[tmp_buf].buftype = "nofile"
            vim.api.nvim_buf_set_lines(tmp_buf, 0, -1, false, stripped)

            -- Format — filetype drives formatter resolution
            conform.format({ bufnr = tmp_buf, async = false, timeout_ms = 5000 })

            -- Read formatted output
            local new_lines = vim.api.nvim_buf_get_lines(tmp_buf, 0, -1, false)
            vim.api.nvim_buf_delete(tmp_buf, { force = true })

            if not new_lines or #new_lines == 0 then return end

            -- Strip trailing empty line if formatter added one
            if not had_trailing_empty and new_lines[#new_lines] == "" then
              table.remove(new_lines)
            end

            -- Re-add base indentation
            local result = {}
            for _, line in ipairs(new_lines) do
              table.insert(result, line == "" and "" or (base_indent .. line))
            end

            vim.api.nvim_buf_set_lines(buf, start_line - 1, end_line, false, result)
          end)
        end,
        mode = "v",
        desc = "Format selection as...",
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
        json = { "jq", "prettierd", "prettier", stop_after_first = true },
        helm = { "prettierd", "prettier", stop_after_first = true },
        markdown = { "prettierd", "prettier", stop_after_first = true },
        html = { "prettierd", "prettier", stop_after_first = true },
        css = { "prettierd", "prettier", stop_after_first = true },
        xml = { "xmlformatter" },
      },
      format_on_save = { timeout_ms = 3000, lsp_format = "fallback" },
      formatters = {
        injected = { options = { ignore_errors = true } },
      },
    },
  },
}
