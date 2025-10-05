local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local rep = require("luasnip.extras").rep
local fmt = require("luasnip.extras.fmt").fmt

local line_begin = require("luasnip.extras.expand_conditions").line_begin

return {
  s("__f", fmt([[
{}() {{ #{{{
	{}
}}
#}}}: {}
]], {
    i(1, "name"),
    i(0, "body"),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Public bash function with (n)vim folding."
  }),

  s("__pf", fmt([[
_{}() {{ #{{{
	{}
}}
#}}}: _{}
]], {
    i(1, "name"),
    i(0, "body"),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Private bash function with (n)vim folding."
  }),

  s("__ss", fmt([[

#{{{ {}
{}
#}}}: {}

]], {
    i(1, "section_title"),
    i(0, "commands"),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Visual section in bash script with (n)vim folding."
  }),

  s("function", fmt([[
{} () {{
	{}
}}
]], {
    i(1, "function"),
    i(0)
  }), {
    condition = line_begin,
    desc = "function template"
  }),

  s("if", fmt([[
if [[ {} ]]; then
	{}
fi
]], {
    i(1),
    i(0)
  })),

  s("ifel", fmt([[
if [[ {} ]]; then
	{}
else
	{}
fi
]], {
    i(1),
    i(2),
    i(0)
  }))
}