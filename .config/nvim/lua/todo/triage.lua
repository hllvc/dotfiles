-- Triage: pick a repo (default @from) and a priority for the item(s) under the cursor or in
-- the selection, drop @from, and move them under `## Todos` next to items of the same repo.
-- A repo from the other context sends them to the other file instead.
local parse = require("todo.parse")
local repos = require("todo.repos")

local M = {}

local NONE = "(none)"

local function select(items, prompt, cb)
	vim.ui.select(items, { prompt = prompt }, function(choice)
		if choice ~= nil then
			cb(choice)
		end
	end)
end

--- Outermost items touched by the cursor line or the selection.
local function targets(buf)
	local mode = vim.fn.mode()
	local l1, l2 = vim.fn.line("."), vim.fn.line(".")
	if mode == "v" or mode == "V" or mode == "\22" then
		l1 = vim.fn.line("v")
		if l1 > l2 then
			l1, l2 = l2, l1
		end
		vim.cmd("normal! \27")
	end
	local parsed = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	local picked = {}
	for row = l1, l2 do
		local idx = parsed.owner[row]
		if idx and not vim.tbl_contains(picked, idx) then
			picked[#picked + 1] = idx
		end
	end
	return parse.outermost(parsed, picked), parsed
end

--- Row after which to insert an item of `repo` under `## Todos` (0-based insert index).
local function insert_row(parsed, lines, repo)
	local todos = parsed.sections.Todos
	if not todos then
		return nil
	end
	local after
	for _, item in ipairs(parsed.items) do
		if item.section == "Todos" and not item.parent and repo and item.eff.repo == repo then
			after = item.last
		end
	end
	if after then
		return after
	end
	local row = todos.last
	while row > todos.row and lines[row]:match("^%s*$") do
		row = row - 1
	end
	return row
end

local function apply(buf, indices, parsed, repo, priority)
	local ctx = vim.b[buf].todo
	-- tag the first lines
	for _, idx in ipairs(indices) do
		local item = parsed.items[idx]
		local line = vim.api.nvim_buf_get_lines(buf, item.row - 1, item.row, false)[1]
		line = parse.set_tag(parse.set_tag(line, "from", nil), "captured", nil)
		line = parse.set_tag(line, "repo", repo)
		if priority then
			line = parse.set_tag(line, "priority", priority)
		end
		vim.api.nvim_buf_set_lines(buf, item.row - 1, item.row, false, { line })
	end

	local target_ctx = ctx
	if repo then
		local found = repos.resolve(repo)
		target_ctx = found and found.context or ctx
	end

	-- take the subtrees out (bottom-up keeps earlier rows valid)
	local blocks = {}
	for i = #indices, 1, -1 do
		local item = parsed.items[indices[i]]
		local lines = vim.api.nvim_buf_get_lines(buf, item.row - 1, item.last, false)
		vim.api.nvim_buf_set_lines(buf, item.row - 1, item.last, false, {})
		for j = #lines, 1, -1 do
			table.insert(blocks, 1, lines[j])
		end
	end

	local todo = require("todo")
	if target_ctx ~= ctx then
		require("todo.store").append(todo.files[target_ctx], "Todos", vim.tbl_map(parse.to_markdown, blocks))
		require("todo.store").write_buf(buf)
		vim.notify(("todo: triaged %d item(s) to %s"):format(#indices, target_ctx))
		return
	end

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local reparsed = parse.parse(lines)
	local row = insert_row(reparsed, lines, repo)
	if not row then
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "## Todos" })
		row = vim.api.nvim_buf_line_count(buf)
	end
	vim.api.nvim_buf_set_lines(buf, row, row, false, blocks)
	vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
	require("todo.store").write_buf(buf)
	vim.notify(("todo: triaged %d item(s)"):format(#indices))
end

function M.triage()
	local buf = vim.api.nvim_get_current_buf()
	local indices, parsed = targets(buf)
	if #indices == 0 then
		return vim.notify("todo: no item here", vim.log.levels.WARN)
	end
	local first = parsed.items[indices[1]]

	local names, seen = {}, {}
	local function add(name)
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	add(first.tags.from)
	add(first.tags.repo)
	add(require("todo").origin_repo())
	for _, repo in ipairs(repos.list(vim.b[buf].todo)) do
		add(repo.name)
	end
	for _, repo in ipairs(repos.list(require("todo").other(vim.b[buf].todo))) do
		add(repo.name)
	end
	table.insert(names, 1 + (first.tags.from and 1 or 0), NONE)

	select(names, "Repo", function(repo)
		repo = repo ~= NONE and repo or nil
		local priorities = vim.list_extend({ NONE }, require("todo.tags").PRIORITIES)
		select(priorities, "Priority", function(priority)
			priority = priority ~= NONE and priority or nil
			apply(buf, indices, parsed, repo, priority)
		end)
	end)
end

return M
