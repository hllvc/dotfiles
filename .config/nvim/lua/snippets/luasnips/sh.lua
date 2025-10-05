local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local rep = require("luasnip.extras").rep
local fmt = require("luasnip.extras.fmt").fmt

local line_begin = require("luasnip.extras.expand_conditions").line_begin

return {
  s("__vf", fmt([[
{}() {{ #{{{
	{}
}}
#}}}: {}
]], {
    i(1, "name"),
    i(0),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Public bash function with (n)vim folding."
  }),

  s("__vpf", fmt([[
_{}() {{ #{{{
	{}
}}
#}}}: _{}
]], {
    i(1, "name"),
    i(0),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Private bash function with (n)vim folding."
  }),

  s("__vs", fmt([[

#{{{ {}
{}
#}}}: {}

]], {
    i(1, "section_title"),
    i(0),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Visual section in bash script with (n)vim folding."
  }),

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
    i(2, "body"),
    rep(1)
  }), {
    condition = line_begin,
    desc = "Private bash function with (n)vim folding."
  }),

  s("__s", fmt([[

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
  })
}
