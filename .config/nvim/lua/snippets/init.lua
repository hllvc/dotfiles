-- Smart snippet loader for multiple formats
-- Supports UltiSnips, LuaSnip Lua format, and SnipMate format
local M = {}

-- Configuration: which loader to use
-- Options: "snipmate", "luasnips", "ultisnips"
M.loader_type = "snipmate"  -- Default to SnipMate format

function M.load_snipmate()
  -- Load snippets using SnipMate-like loader
  require("luasnip.loaders.from_snipmate").load({
    paths = { vim.fn.stdpath("config") .. "/lua/snippets/snipmate" }
  })
end

function M.load_luasnips()
  -- Load Lua format snippets
  require("snippets.luasnips").load()
end

function M.load_ultisnips()
  -- Potential future support for loading original UltiSnips files
  -- This would require additional conversion logic
  print("UltiSnips loader not yet implemented - use snipmate or luasnips")
end

function M.load()
  local loaders = {
    snipmate = M.load_snipmate,
    luasnips = M.load_luasnips,
    ultisnips = M.load_ultisnips
  }

  local loader = loaders[M.loader_type]
  if loader then
    loader()
  else
    print("Unknown loader type: " .. M.loader_type)
    print("Available loaders: snipmate, luasnips, ultisnips")
  end
end

-- Function to switch loader type
function M.set_loader(loader_type)
  M.loader_type = loader_type
  print("Snippet loader set to: " .. loader_type)
end

return M
