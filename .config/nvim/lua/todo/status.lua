-- Status line counts: `todo 4 · inbox 2 · due 1`.
--   todo  open items of the current repo (whole context file outside a repo)
--   inbox untriaged items across both files; warn highlight once the oldest is > 5 days
--   due   own @due today or overdue in the current context
-- Files are parsed from disk, cached by mtime; the lualine callbacks only read `counts`.
local parse = require("todo.parse")
local tags = require("todo.tags")

local M = {}

M.STALE_DAYS = 5

local files = {} -- path -> { mtime, parsed }
local counts = { todo = 0, inbox = 0, due = 0, stale = false, oldest = nil }

local function load(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then
		files[path] = nil
		return nil
	end
	local entry = files[path]
	if entry and entry.mtime == stat.mtime.sec and entry.nsec == stat.mtime.nsec then
		return entry.parsed
	end
	local parsed = parse.parse(vim.fn.readfile(path))
	files[path] = { mtime = stat.mtime.sec, nsec = stat.mtime.nsec, parsed = parsed }
	return parsed
end

function M.invalidate()
	files = {}
	M.refresh()
end

function M.refresh()
	local todo = require("todo")
	local info = todo.where()
	local ctx = info and info.context or "personal"
	local repo = info and info.repo or nil

	local c = { todo = 0, inbox = 0, due = 0, stale = false, oldest = nil }
	for fctx, path in pairs(todo.files) do
		local parsed = load(path)
		for _, item in ipairs(parsed and parsed.items or {}) do
			if item.state == "unchecked" then
				if item.section == "Inbox" then
					if not item.parent then
						c.inbox = c.inbox + 1
						local days = tags.days_until(item.tags.captured)
						if days and (not c.oldest or -days > c.oldest) then
							c.oldest = -days
						end
					end
				elseif fctx == ctx then
					if not repo or item.eff.repo == repo then
						c.todo = c.todo + 1
					end
					local days = tags.days_until(item.tags.due)
					if days and days <= 0 then
						c.due = c.due + 1
					end
				end
			end
		end
	end
	c.stale = c.oldest ~= nil and c.oldest > M.STALE_DAYS
	counts = c
end

function M.counts()
	return counts
end

--- lualine components (see plugins/ui.lua).
function M.lualine()
	return {
		{
			function()
				return "todo " .. counts.todo
			end,
			cond = function()
				return counts.todo > 0 or counts.inbox > 0 or counts.due > 0
			end,
			color = "Comment",
			padding = { left = 1, right = 0 },
		},
		{
			function()
				return " · inbox " .. counts.inbox
			end,
			cond = function()
				return counts.inbox > 0
			end,
			color = function()
				return counts.stale and "DiagnosticWarn" or "Comment"
			end,
			padding = { left = 0, right = 0 },
		},
		{
			function()
				return " · due " .. counts.due
			end,
			cond = function()
				return counts.due > 0
			end,
			color = "DiagnosticError",
			padding = { left = 0, right = 1 },
		},
	}
end

--- Once a day, on startup: tell me when the inbox has been sitting too long.
function M.notify_stale_inbox()
	M.refresh()
	if not counts.stale then
		return
	end
	local todo = require("todo")
	local st = todo.state()
	local today = tags.today()
	if st.notified == today then
		return
	end
	st.notified = today
	todo.save_state()
	vim.notify(
		("Inbox: %d item(s) untriaged, oldest %d days"):format(counts.inbox, counts.oldest),
		vim.log.levels.WARN,
		{ title = "todo" }
	)
end

return M
