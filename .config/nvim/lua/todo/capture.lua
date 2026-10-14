-- Inbox capture: a one-line prompt (with tag completion) and a floating inbox window.
local parse = require("todo.parse")
local tags = require("todo.tags")

local M = {}

local floats = {}

function M.is_float(win)
	return floats[win] == true
end

--- Build the inbox line for `text` and pick its file (routing tags override the context).
local function build(text, ctx, meta)
	local _, routing = parse.tags(text)
	if routing.work then
		ctx = "work"
	elseif routing.personal then
		ctx = "personal"
	end
	local line = "- [ ] " .. vim.trim(parse.strip_routing(text))
	if meta.from then
		line = parse.set_tag(line, "from", meta.from)
	end
	line = parse.set_tag(line, "captured", tags.now())
	if meta.src then
		line = parse.set_tag(line, "src", meta.src)
	end
	return line, ctx
end

--- One-line capture prompt. `opts.visual` attaches @src of the selected lines.
function M.prompt(opts)
	opts = opts or {}
	local todo = require("todo")
	local info = todo.where()
	local meta = { from = info and info.repo or nil }
	local buf = vim.api.nvim_get_current_buf()
	if opts.visual then
		local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
		if l1 > l2 then
			l1, l2 = l2, l1
		end
		vim.cmd("normal! \27")
		meta.src = todo.src_value(vim.api.nvim_buf_get_name(buf), l1, l2)
	end
	-- remember where we are, so `@src(` completion in the prompt offers this position
	todo.record_origin(buf)
	local ctx = info and info.context or "personal"

	local pbuf = vim.api.nvim_create_buf(false, true)
	vim.bo[pbuf].bufhidden = "wipe"
	vim.b[pbuf].todo_capture = true
	local width = math.min(80, math.floor(vim.o.columns * 0.6))
	local title = (" Inbox · %s%s "):format(ctx, meta.src and " · @src" or "")
	local win = vim.api.nvim_open_win(pbuf, true, {
		relative = "editor",
		row = math.floor(vim.o.lines * 0.3),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = 1,
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
	})
	vim.wo[win].winhighlight = "NormalFloat:Normal"

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		vim.cmd("stopinsert")
	end
	local function submit()
		local text = vim.trim(vim.api.nvim_buf_get_lines(pbuf, 0, 1, false)[1] or "")
		close()
		if text == "" then
			return
		end
		local line, target = build(text, ctx, meta)
		require("todo.store").append(todo.files[target], "Inbox", { line })
		vim.notify(("todo: captured to %s inbox"):format(target))
	end
	local mopts = { buffer = pbuf, nowait = true }
	vim.keymap.set("i", "<CR>", function()
		local ok, cmp = pcall(require, "cmp")
		if ok and cmp.visible() then
			return cmp.confirm({ select = true })
		end
		submit()
	end, mopts)
	vim.keymap.set("n", "<CR>", submit, mopts)
	vim.keymap.set("n", "<Esc>", close, mopts)
	vim.keymap.set("n", "q", close, mopts)
	vim.api.nvim_create_autocmd("WinLeave", { buffer = pbuf, once = true, callback = close })
	vim.cmd("startinsert")
end

--- The inbox of the current context's file in a float, showing only the Inbox section.
function M.float()
	local todo = require("todo")
	todo.record_origin()
	local path = todo.files[vim.b.todo or todo.context()]
	require("todo.store").ensure(path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	local width = math.min(100, math.floor(vim.o.columns * 0.7))
	local height = math.min(20, math.floor(vim.o.lines * 0.5))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		border = "rounded",
		title = (" Inbox · %s "):format(todo.file_context(path)),
		title_pos = "center",
	})
	floats[win] = true
	require("todo.view").set_inbox_only(win, true)
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			floats[win] = nil
			require("todo.store").write_buf(buf)
		end,
	})
	-- BufWinEnter already applied the view; re-apply now that the window is inbox-only
	require("todo").attach(buf)
	require("todo").win_enter(buf, win)
	-- land on the end of the Inbox section, ready to add
	local parsed = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	local inbox = parsed.sections.Inbox
	if inbox then
		local row = inbox.last
		while row > inbox.row and vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]:match("^%s*$") do
			row = row - 1
		end
		vim.api.nvim_win_set_cursor(win, { row, 0 })
	end
end

return M
