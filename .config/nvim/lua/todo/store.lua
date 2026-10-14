-- Safe edits of a todo file that may or may not be open, possibly in another nvim.
-- Never edits a hidden buffer that could be stale: when no window shows the file it is
-- edited on disk (Markdown), and a loaded copy is refreshed with :checktime afterwards.
local parse = require("todo.parse")

local M = {}

M.SKELETON = { "## Inbox", "", "## Todos", "" }

function M.ensure(path)
	if vim.uv.fs_stat(path) then
		return
	end
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(M.SKELETON, path)
end

local function loaded_buf(path)
	local buf = vim.fn.bufnr(path)
	if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
		return buf
	end
end

--- Write a checkmate buffer through its own BufWriteCmd (unicode -> Markdown).
function M.write_buf(buf)
	if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent! write")
		end)
	end
end

--- Row after which new lines go at the end of `section`: its last non-blank line.
local function section_end(lines, section)
	local parsed = parse.parse(lines)
	local sec = parsed.sections[section]
	if not sec then
		return nil
	end
	local row = sec.last
	while row > sec.row and lines[row]:match("^%s*$") do
		row = row - 1
	end
	return row
end

--- Append Markdown lines to the end of `section` in the file at `path`.
---@param lines string[] Markdown (`- [ ]`) lines
function M.append(path, section, lines)
	M.ensure(path)
	local buf = loaded_buf(path)
	local shown = buf and #vim.fn.win_findbuf(buf) > 0

	if buf and (shown or vim.bo[buf].modified) then
		if not vim.bo[buf].modified then
			vim.cmd("checktime " .. buf)
		end
		local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local row = section_end(current, section)
		if not row then
			current[#current + 1] = ""
			current[#current + 1] = "## " .. section
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "## " .. section })
			row = #current
		end
		vim.api.nvim_buf_set_lines(buf, row, row, false, vim.tbl_map(parse.to_unicode, lines))
		M.write_buf(buf)
		return
	end

	local current = vim.fn.readfile(path)
	local row = section_end(current, section)
	if not row then
		vim.list_extend(current, { "", "## " .. section })
		row = #current
	end
	for i, line in ipairs(lines) do
		table.insert(current, row + i, parse.to_markdown(line))
	end
	vim.fn.writefile(current, path)
	if buf then
		vim.cmd("checktime " .. buf)
	end
	require("todo.status").invalidate()
end

return M
