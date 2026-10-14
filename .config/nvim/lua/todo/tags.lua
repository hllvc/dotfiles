-- Tag definitions: one source for checkmate's metadata config and the completion source.
local M = {}

M.DATE = "%Y-%m-%d"
M.STAMP = "%Y-%m-%d %H:%M"

M.PRIORITIES = { "critical", "high", "medium", "low" }

function M.today()
	return os.date(M.DATE)
end

function M.now()
	return os.date(M.STAMP)
end

local function noon(t)
	local d = os.date("*t", t)
	return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

local function offset(days)
	return os.date(M.DATE, noon(os.time()) + days * 86400)
end

--- Relative date keywords offered for `@due(`.
---@return { word: string, date: string }[]
function M.due_keywords()
	local out = {
		{ word = "today", date = offset(0) },
		{ word = "tomorrow", date = offset(1) },
	}
	local wday = os.date("*t").wday -- 1 = Sunday
	local names = { "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday" }
	for i = 2, 7 do
		local target = (wday - 1 + i) % 7 + 1
		out[#out + 1] = { word = names[target], date = offset(i) }
	end
	out[#out + 1] = { word = "next week", date = offset(7) }
	out[#out + 1] = { word = "in 2 weeks", date = offset(14) }
	out[#out + 1] = { word = "next month", date = offset(30) }
	return out
end

--- Parse an ISO date value; returns the day difference to today, or nil for free text.
function M.days_until(value)
	local y, m, d = (value or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)")
	if not y then
		return nil
	end
	local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
	return math.floor((t - noon(os.time())) / 86400 + 0.5)
end

--- Values for a tag, for completion and checkmate's value picker.
---@return string[]
function M.choices(name)
	if name == "priority" then
		return vim.deepcopy(M.PRIORITIES)
	elseif name == "repo" then
		local todo = require("todo")
		local ctx = vim.b.todo or todo.context()
		local current = todo.origin_repo()
		local out = current and { current } or {}
		for _, repo in ipairs(require("todo.repos").list(ctx)) do
			if repo.name ~= current then
				out[#out + 1] = repo.name
			end
		end
		return out
	elseif name == "due" then
		return vim.tbl_map(function(k)
			return k.date
		end, M.due_keywords())
	elseif name == "src" then
		local src = require("todo").origin_src()
		return src and { src } or {}
	elseif name == "started" or name == "done" or name == "captured" then
		return { M.now() }
	end
	return {}
end

local function style(link)
	return { link = link }
end

local PRIORITY_HL = {
	critical = "DiagnosticError",
	high = "DiagnosticWarn",
	medium = "DiagnosticInfo",
	low = "DiagnosticHint",
}

--- checkmate `metadata` table.
function M.checkmate_metadata()
	local function choices(name)
		return function()
			return M.choices(name)
		end
	end
	return {
		priority = {
			style = function(context)
				return style(PRIORITY_HL[context.value:lower()] or "Comment")
			end,
			get_value = function()
				return "medium"
			end,
			choices = choices("priority"),
			key = "<leader>tp",
			sort_order = 10,
			jump_to_on_insert = "value",
			select_on_insert = true,
		},
		due = {
			style = style("Special"),
			get_value = M.today,
			choices = choices("due"),
			sort_order = 15,
			jump_to_on_insert = "value",
			select_on_insert = true,
		},
		repo = {
			style = style("Identifier"),
			choices = choices("repo"),
			get_value = function()
				return require("todo").origin_repo() or ""
			end,
			sort_order = 5,
			jump_to_on_insert = "value",
			select_on_insert = true,
		},
		started = {
			style = style("Comment"),
			get_value = M.now,
			key = "<leader>ts",
			sort_order = 20,
		},
		done = {
			style = style("Comment"),
			get_value = M.now,
			key = "<leader>td",
			on_add = function(todo)
				require("checkmate").set_todo_state(todo, "checked")
			end,
			on_remove = function(todo)
				require("checkmate").set_todo_state(todo, "unchecked")
			end,
			sort_order = 30,
		},
		from = { style = style("Comment"), sort_order = 40 },
		captured = { style = style("Comment"), get_value = M.now, sort_order = 41 },
		src = { style = style("Comment"), choices = choices("src"), sort_order = 42 },
	}
end

return M
