-- Smart snippet loader
local M = {}

-- Configuration: which loader to use
-- Options: "snipmate", "luasnips"
M.loader_type = "snipmate"

function M.load_snipmate()
	require("luasnip.loaders.from_snipmate").load({
		paths = { vim.fn.stdpath("config") .. "/lua/snippets/snipmate" },
	})
end

function M.load_luasnips()
	require("luasnip.loaders.from_lua").load({
		paths = { vim.fn.stdpath("config") .. "/lua/snippets/luasnips" },
	})
end

function M.load()
	local loaders = {
		snipmate = M.load_snipmate,
		luasnips = M.load_luasnips,
	}

	local loader = loaders[M.loader_type]
	if loader then
		loader()
	else
		vim.notify("Unknown snippet loader: " .. M.loader_type, vim.log.levels.WARN)
	end
end

return M
