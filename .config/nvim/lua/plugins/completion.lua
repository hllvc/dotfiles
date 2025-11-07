return {
  -- Auto completion
  {
    "hrsh7th/nvim-cmp",
    version = false, -- last release is way too old
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-calc",
      "saadparwaiz1/cmp_luasnip",
      "hrsh7th/cmp-nvim-lsp-signature-help",
    },
    opts = function()
      vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
      local cmp = require("cmp")
      local defaults = require("cmp.config.default")()
      return {
        completion = {
          completeopt = "menu,menuone,noinsert",
        },
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = {
          -- TAB: Clean fallback behavior (no conflicts with UltiSnips/Copilot)
          ["<Tab>"] = cmp.mapping(function(fallback)
            local copilot = require("copilot.suggestion")
            if copilot.is_visible() then
              copilot.accept()
            else
              fallback() -- Let normal TAB behavior work
            end
          end, { "i", "s" }),

          -- Navigation: Keep your preferred Ctrl+j/k pattern
          ["<C-j>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              cmp.complete()  -- Trigger completion when not visible
            end
          end, { "i", "s" }),

          ["<C-k>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end, { "i", "s" }),

          -- Smart C-l: expand snippet, confirm cmp, or handle Copilot
          ["<C-l>"] = cmp.mapping(function(fallback)
            local luasnip = require('luasnip')
            local copilot = require("copilot.suggestion")
            if cmp.visible() then
              cmp.confirm({ select = true })
            elseif luasnip.expandable() then
              luasnip.expand()
            else
              copilot.next() -- Trigger suggestion if none visible
            end
          end, { "i", "s" }),
          -- Smart C-h: dismiss both Copilot and cmp
          ["<C-h>"] = cmp.mapping(function(fallback)
            local copilot = require("copilot.suggestion")
            if copilot.is_visible() then
              copilot.dismiss()
            end
            if cmp.visible() then
              cmp.abort()
            end
          end, { "i", "s" }),

          -- C-n/p for LuaSnip navigation
          ["<C-n>"] = cmp.mapping(function(fallback)
            local luasnip = require('luasnip')
            if luasnip.jumpable(1) then
              luasnip.jump(1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<C-p>"] = cmp.mapping(function(fallback)
            local luasnip = require('luasnip')
            if luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),

          -- Scroll docs
          ["<C-u>"] = cmp.mapping.scroll_docs(-4),
          ["<C-d>"] = cmp.mapping.scroll_docs(4),
        },
        sources = cmp.config.sources({
          { name = "lazydev", group_index = 0 },
          { name = "nvim_lsp", priority = 1000 },
          { name = "nvim_lsp_signature_help", priority = 900 },
          { name = "path", priority = 700 },
          { name = "calc", priority = 600 },
          { name = "luasnip", priority = 500 },
        }, {
          { name = "buffer", priority = 400 },
        }),
        formatting = {
          format = function(_, item)
            local icons = {
              Array = " ",
              Boolean = " ",
              Class = " ",
              Color = " ",
              Constant = " ",
              Constructor = " ",
              Enum = " ",
              EnumMember = " ",
              Event = " ",
              Field = " ",
              File = " ",
              Folder = " ",
              Function = " ",
              Interface = " ",
              Key = " ",
              Keyword = " ",
              Method = " ",
              Module = " ",
              Namespace = " ",
              Null = " ",
              Number = " ",
              Object = " ",
              Operator = " ",
              Package = " ",
              Property = " ",
              Reference = " ",
              Snippet = " ",
              String = " ",
              Struct = " ",
              Text = " ",
              TypeParameter = " ",
              Unit = " ",
              Value = " ",
              Variable = " ",
            }
            if icons[item.kind] then
              item.kind = icons[item.kind] .. item.kind
            end
            return item
          end,
        },
        experimental = {
          ghost_text = {
            hl_group = "CmpGhostText",
          },
        },
        sorting = defaults.sorting,
      }
    end,
    config = function(_, opts)
      for _, source in ipairs(opts.sources) do
        source.group_index = source.group_index or 1
      end
      require("cmp").setup(opts)
    end,
  },

  -- LuaSnip (primary snippet engine)
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    build = "make install_jsregexp",
    event = "InsertEnter",
    config = function()
      local luasnip = require('luasnip')

      -- Load snippets from lua/snippets/
      require('snippets').load()

      -- Configure LuaSnip
      luasnip.config.setup({
        -- Update as you type
        update_events = "TextChanged,TextChangedI",
        -- Delete unvisited nodes on leaving
        delete_check_events = "TextChanged",
      })
    end,
  },
}
