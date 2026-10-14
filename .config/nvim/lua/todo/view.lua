-- Tag-driven views through folding: lines outside the current view are folded away.
-- Scope "repo" keeps items whose effective @repo is the repo you came from; "all" keeps
-- everything. Checked items stay visible until archived (<leader>ta). The inbox float
-- shows only the Inbox section.
local parse = require("todo.parse")

local M = {}

local cache = {} -- win -> hidden rows (set); foldexpr runs with that window current
local inbox_only = {} -- win -> true

--- Hidden rows of the current window.
function M.hidden()
	return cache[vim.api.nvim_get_current_win()] or {}
end

function M.set_inbox_only(win, on)
	inbox_only[win] = on or nil
end

vim.api.nvim_create_autocmd("WinClosed", {
	group = vim.api.nvim_create_augroup("todo_view", { clear = true }),
	callback = function(ev)
		local win = tonumber(ev.match)
		if win then
			cache[win], inbox_only[win] = nil, nil
		end
	end,
})

--- The repo the repo-scope filters on, or nil when there is none.
function M.scope_repo()
	local todo = require("todo")
	if todo.state().scope ~= "repo" then
		return nil
	end
	return todo.origin_repo()
end

local function compute(buf, win)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local parsed = parse.parse(lines)
	local todo = require("todo")
	local repo = M.scope_repo()
	local only_inbox = win and inbox_only[win]

	local visible = {}
	for idx, item in ipairs(parsed.items) do
		local keep
		if item.section == "Inbox" then
			keep = true
		elseif only_inbox then
			keep = false
		else
			keep = repo == nil or item.eff.repo == repo
		end
		if keep then
			-- ancestors stay visible for context
			local i = idx
			while i and not visible[i] do
				visible[i] = true
				i = parsed.items[i].parent
			end
		end
	end

	local hidden = {}
	local n = #lines
	for row = 1, n do
		local owner = parsed.owner[row]
		if owner then
			hidden[row] = not visible[owner] or nil
		elseif only_inbox and not parsed.headings[row] then
			local inbox = parsed.sections.Inbox
			hidden[row] = not (inbox and row >= inbox.row and row <= inbox.last) or nil
		end
	end
	if only_inbox then
		for row in pairs(parsed.headings) do
			local inbox = parsed.sections.Inbox
			if not inbox or row ~= inbox.row then
				hidden[row] = true
			end
		end
	end
	-- blank lines between hidden lines join the fold, so each gap is one summary line
	for row = 1, n do
		if not hidden[row] and not parsed.owner[row] and lines[row]:match("^%s*$") then
			local prev, nxt = row - 1, row + 1
			while prev >= 1 and lines[prev]:match("^%s*$") do
				prev = prev - 1
			end
			while nxt <= n and lines[nxt]:match("^%s*$") do
				nxt = nxt + 1
			end
			if prev >= 1 and hidden[prev] and (nxt > n or hidden[nxt]) then
				hidden[row] = true
			end
		end
	end
	return hidden
end

function M.foldexpr(lnum)
	local hidden = cache[vim.api.nvim_get_current_win()]
	if not hidden or not hidden[lnum] then
		return "0"
	end
	return hidden[lnum - 1] and "1" or ">1"
end

function M.foldtext()
	local count = vim.v.foldend - vim.v.foldstart + 1
	return ("  ··· %d hidden"):format(count)
end

local function update_folds(win)
	vim.api.nvim_win_call(win, function()
		-- re-setting foldexpr makes nvim re-evaluate every line
		vim.wo.foldexpr = vim.wo.foldexpr
		vim.cmd("silent! normal! zx")
	end)
end

--- Window-local options for a todo buffer shown in `win`.
function M.apply(buf, win)
	local opts = {
		foldmethod = "expr",
		foldexpr = "v:lua.require'todo.view'.foldexpr(v:lnum)",
		foldtext = "v:lua.require'todo.view'.foldtext()",
		foldlevel = 0,
		foldminlines = 0,
		foldenable = true,
		conceallevel = 2,
		concealcursor = "",
	}
	for name, value in pairs(opts) do
		vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
	end
	M.refresh(buf)
end

--- Recompute the view of `buf` and refresh its folds in every window showing it.
function M.refresh(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		cache[win] = compute(buf, win)
		update_folds(win)
	end
end

local function refresh_all()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].todo then
			M.refresh(buf)
		end
	end
	require("todo.status").refresh()
end

function M.cycle_scope()
	local todo = require("todo")
	local st = todo.state()
	st.scope = st.scope == "repo" and "all" or "repo"
	todo.save_state()
	refresh_all()
	local repo = todo.origin_repo()
	if st.scope == "repo" and repo then
		vim.notify("todo: showing " .. repo)
	elseif st.scope == "repo" then
		vim.notify("todo: not in a repo, showing everything")
	else
		vim.notify("todo: showing everything")
	end
end

return M
