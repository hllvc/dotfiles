-- Routing between the work and personal files. After a write, items tagged `@work` /
-- `@personal`, or with an `@repo` from the other context, move to the other file into the
-- same section; the routing tag is stripped. Tagged with their own context, they only
-- lose the tag.
local parse = require("todo.parse")
local repos = require("todo.repos")

local M = {}

local function repo_context(name)
	local repo = name and repos.resolve(name)
	return repo and repo.context or nil
end

--- Remove the subtrees of `indices` (outermost items) from `buf`, returning their lines
--- as Markdown, grouped with their section.
function M.take(buf, parsed, indices)
	local taken = {}
	for i = #indices, 1, -1 do
		local item = parsed.items[indices[i]]
		local lines = vim.api.nvim_buf_get_lines(buf, item.row - 1, item.last, false)
		vim.api.nvim_buf_set_lines(buf, item.row - 1, item.last, false, {})
		table.insert(taken, 1, { section = item.section or "Todos", lines = vim.tbl_map(parse.to_markdown, lines) })
	end
	return taken
end

function M.route(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].todo then
		return
	end
	local ctx = vim.b[buf].todo
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local parsed = parse.parse(lines)

	local moving, strip = {}, {}
	for idx, item in ipairs(parsed.items) do
		local target
		if item.routing.work or item.routing.personal then
			target = item.routing.work and "work" or "personal"
			strip[#strip + 1] = item.row
		elseif item.tags.repo then
			target = repo_context(item.tags.repo)
		end
		if target and target ~= ctx then
			moving[#moving + 1] = idx
		end
	end
	if #moving == 0 and #strip == 0 then
		return
	end

	for _, row in ipairs(strip) do
		local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
		vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { parse.strip_routing(line) })
	end

	local outer = parse.outermost(parsed, moving)
	local taken = M.take(buf, parsed, outer)
	local todo = require("todo")
	local other = todo.files[todo.other(ctx)]
	for _, group in ipairs(taken) do
		require("todo.store").append(other, group.section, group.lines)
	end
	require("todo.store").write_buf(buf)
	if #taken > 0 then
		vim.notify(("todo: moved %d item(s) to %s"):format(#taken, todo.other(ctx)))
	end
end

return M
