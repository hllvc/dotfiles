-- LuaSnip Lua format snippet loader
-- This module loads all Lua-format snippet files
local M = {}

function M.load()
  local ls = require("luasnip")

  -- Load snippets for each filetype (only the ones we have)
  local filetypes = {
    "sh",
    "tex",
    "typescript",
    "zsh"
  }

  for _, ft in ipairs(filetypes) do
    local ok, snippets = pcall(require, "snippets.luasnips." .. ft)
    if ok and snippets then
      ls.add_snippets(ft, snippets)
    end
  end
end

return M