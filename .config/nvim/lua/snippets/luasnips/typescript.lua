local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  s("__todo", fmt([[// TODO({}): {}]], {
    f(function()
      return vim.fn.system("git config user.email"):gsub("\n", "")
    end),
    i(0)
  }), {
    condition = function()
      return true -- Auto-trigger equivalent
    end
  })
}
