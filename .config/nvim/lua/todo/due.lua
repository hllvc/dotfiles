-- `@due(2026-09-28)` shown as `@due(tomorrow)`: the date is concealed and a relative label
-- drawn inline in its place. The cursor line shows the raw date for editing.
local parse = require("todo.parse")
local tags = require("todo.tags")

local M = {}

local ns = vim.api.nvim_create_namespace("todo_due")
local last_row = {} -- buf -> cursor row the last render skipped

local WEEKDAYS = { "sun", "mon", "tue", "wed", "thu", "fri", "sat" }

--- Label and highlight for a day difference.
function M.label(days)
	if days < 0 then
		return ("%dd overdue"):format(-days), "DiagnosticError"
	elseif days == 0 then
		return "today", "DiagnosticWarn"
	elseif days == 1 then
		return "tomorrow", "Special"
	elseif days < 7 then
		return WEEKDAYS[os.date("*t", os.time() + days * 86400).wday], "Special"
	elseif days <= 60 then
		return ("in %dd"):format(days), "Comment"
	end
end

function M.render(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local cursor_row
	local win = vim.fn.bufwinid(buf)
	if win ~= -1 and vim.api.nvim_get_current_buf() == buf then
		cursor_row = vim.api.nvim_win_get_cursor(0)[1]
	end
	last_row[buf] = cursor_row
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if row ~= cursor_row and line:find("@due(", 1, true) and parse.todo_line(line) then
			local s, e = parse.tag_range(line, "due")
			local days = s and tags.days_until(line:sub(s, e))
			local label, hl
			if days then
				label, hl = M.label(days)
			end
			if label then
				vim.api.nvim_buf_set_extmark(buf, ns, row - 1, s - 1, {
					end_col = e,
					conceal = "",
					virt_text = { { label, hl } },
					virt_text_pos = "inline",
				})
			end
		end
	end
end

function M.cursor_moved(buf)
	local row = vim.api.nvim_win_get_cursor(0)[1]
	if last_row[buf] ~= row then
		M.render(buf)
	end
end

return M
