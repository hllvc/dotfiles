-- Personal todo workflow on top of checkmate.nvim: two files (work, personal) under
-- ~/.todo, tag-driven views, capture, triage and routing. See KEYMAPS.md "Todos".
local repos = require("todo.repos")

local M = {}

M.dir = vim.fn.expand("~/.todo")
M.files = {
	work = M.dir .. "/work.todo.md",
	personal = M.dir .. "/personal.todo.md",
}

-- Persisted view state: scope ("repo" | "all"), last inbox notify date.
local STATE_FILE = vim.fn.stdpath("state") .. "/todo.json"
local state

function M.state()
	if not state then
		local ok, data = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(STATE_FILE), "\n"))
		end)
		state = vim.tbl_extend("force", { scope = "repo" }, ok and data or {})
	end
	return state
end

function M.save_state()
	pcall(vim.fn.writefile, { vim.json.encode(M.state()) }, STATE_FILE)
end

--- Context of a todo file path ("work" | "personal"), or nil.
function M.file_context(path)
	path = vim.fs.normalize(path or "")
	for ctx, file in pairs(M.files) do
		if path == file then
			return ctx
		end
	end
end

function M.other(ctx)
	return ctx == "work" and "personal" or "work"
end

-- Where the user was before entering a todo buffer: drives repo scope, @from and @src.
local origin = {}

local function is_file_buf(buf)
	return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" and not vim.b[buf].todo
end

function M.record_origin(buf, win)
	buf = buf or vim.api.nvim_get_current_buf()
	if not is_file_buf(buf) then
		return
	end
	local path = vim.api.nvim_buf_get_name(buf)
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win or 0)
	origin = { path = path, info = repos.from_path(path), lnum = ok and cursor[1] or 1 }
end

--- Repo info for "where I am": the current file buffer, else the recorded origin, else cwd.
function M.where()
	local buf = vim.api.nvim_get_current_buf()
	if is_file_buf(buf) then
		return repos.from_path(vim.api.nvim_buf_get_name(buf))
	end
	if vim.b[buf].todo and origin.path then
		return origin.info
	end
	return repos.from_path(vim.fn.getcwd() .. "/")
end

function M.context()
	local info = M.where()
	return info and info.context or "personal"
end

function M.origin_repo()
	local info = M.where()
	return info and info.repo or nil
end

--- `@src` value for a position: repo/worktree/path:l1[-l2].
function M.src_value(path, l1, l2)
	local info = repos.from_path(path)
	if not info or info.rel == "" then
		return nil
	end
	local lines = l2 and l2 ~= l1 and ("%d-%d"):format(l1, l2) or tostring(l1)
	local wt = info.worktree and (info.worktree .. "/") or ""
	return ("%s/%s%s:%s"):format(info.repo, wt, info.rel, lines)
end

function M.origin_src()
	local buf = vim.api.nvim_get_current_buf()
	if is_file_buf(buf) then
		return M.src_value(vim.api.nvim_buf_get_name(buf), vim.api.nvim_win_get_cursor(0)[1])
	end
	if origin.path then
		return M.src_value(origin.path, origin.lnum)
	end
end

--- Running in the tmux todo popup (~/.shell/scripts/tmux/todo-popup.sh): the origin pane id.
function M.in_popup()
	local pane = vim.env.TODO_POPUP
	return pane ~= nil and pane ~= "" and pane or nil
end

--- Open the todo file of `ctx` (default: current context; inside a todo file, the other one).
function M.open(ctx)
	local cur = vim.b.todo
	if not ctx then
		ctx = cur and M.other(cur) or M.context()
	end
	M.record_origin()
	local path = M.files[ctx]
	require("todo.store").ensure(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
end

--- Toggle item(s) under the cursor or in the selection, stamping or removing @done.
local function toggle_one()
	local cm = require("checkmate")
	local todo = cm.get_todo()
	if not todo then
		return cm.toggle()
	end
	if todo.is_checked() then
		if todo.get_metadata("done") then
			cm.remove_metadata("done") -- on_remove unchecks
		else
			cm.toggle()
		end
	else
		cm.add_metadata("done") -- on_add checks (smart toggle propagates)
	end
end

function M.toggle()
	local mode = vim.fn.mode()
	if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
		return toggle_one()
	end
	local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
	if l1 > l2 then
		l1, l2 = l2, l1
	end
	vim.cmd("normal! \27")
	local parse = require("todo.parse")
	local win = vim.api.nvim_get_current_win()
	-- bottom-up, so earlier rows stay put while later items change
	for row = l2, l1, -1 do
		local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
		if line and parse.todo_line(line) then
			vim.api.nvim_win_set_cursor(win, { row, 0 })
			toggle_one()
		end
	end
end

--- Jump to the next (dir = 1) or previous (dir = -1) open, visible item.
function M.jump(dir)
	local buf = vim.api.nvim_get_current_buf()
	local parsed = require("todo.parse").parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	local hidden = require("todo.view").hidden()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local best
	for _, item in ipairs(parsed.items) do
		if item.state == "unchecked" and not hidden[item.row] then
			if dir > 0 and item.row > row and (not best or item.row < best) then
				best = item.row
			elseif dir < 0 and item.row < row and (not best or item.row > best) then
				best = item.row
			end
		end
	end
	if best then
		vim.cmd("normal! m'")
		vim.api.nvim_win_set_cursor(0, { best, 0 })
		vim.cmd("normal! ^")
	end
end

local PRIORITY_RANK = { critical = 1, high = 2, medium = 3, low = 4 }

--- Picker over the open items of the current view: overdue first, then priority, then file order.
function M.pick()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local parsed = require("todo.parse").parse(lines)
	local hidden = require("todo.view").hidden()
	local tags = require("todo.tags")
	local list = {}
	for _, item in ipairs(parsed.items) do
		if item.state == "unchecked" and not hidden[item.row] then
			local days = tags.days_until(item.eff.due)
			list[#list + 1] = {
				item = item,
				overdue = days ~= nil and days <= 0,
				rank = PRIORITY_RANK[item.eff.priority or ""] or 9,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.overdue ~= b.overdue then
			return a.overdue
		end
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.item.row < b.item.row
	end)
	vim.ui.select(list, {
		prompt = "Todos",
		format_item = function(entry)
			local item = entry.item
			local text = item.text:gsub("%s*@[%a][%w_%-]*%b()", "")
			local meta = {}
			if item.eff.priority then
				meta[#meta + 1] = item.eff.priority
			end
			if item.eff.repo then
				meta[#meta + 1] = item.eff.repo
			end
			if item.eff.due then
				meta[#meta + 1] = "due " .. item.eff.due
			end
			return #meta > 0 and ("%s  [%s]"):format(text, table.concat(meta, " · ")) or text
		end,
	}, function(entry)
		if entry then
			vim.api.nvim_win_set_cursor(0, { entry.item.row, 0 })
			vim.cmd("normal! zv^")
		end
	end)
end

-- Debounced auto-write: a todo buffer is never left modified, so another nvim instance
-- never saves a stale copy over it (FocusLost writes all modified buffers).
local timers = {}
local function schedule_write(buf)
	if timers[buf] then
		timers[buf]:stop()
	else
		timers[buf] = vim.uv.new_timer()
	end
	timers[buf]:start(
		400,
		0,
		vim.schedule_wrap(function()
			if vim.api.nvim_buf_is_valid(buf) and vim.fn.mode() ~= "i" then
				require("todo.store").write_buf(buf)
			end
		end)
	)
end

--- Buffer-local setup for a todo file (checkmate has no attach event).
function M.attach(buf)
	local ctx = M.file_context(vim.api.nvim_buf_get_name(buf))
	if not ctx or vim.b[buf].todo then
		return
	end
	vim.b[buf].todo = ctx

	local function map(mode, lhs, rhs, desc, opts)
		vim.keymap.set(
			mode,
			lhs,
			rhs,
			vim.tbl_extend("force", { buffer = buf, silent = true, desc = desc }, opts or {})
		)
	end
	map({ "n", "x" }, "<CR>", M.toggle, "Todo: toggle")
	map("n", "<S-CR>", function()
		require("todo.follow").follow()
	end, "Todo: follow @src / @repo")
	map("n", "<leader>tt", function()
		require("todo.view").cycle_scope()
	end, "Todo: scope repo / all")
	map({ "n", "x" }, "<leader>tm", function()
		require("todo.triage").triage()
	end, "Todo: triage")
	map("n", "<leader>tf", M.pick, "Todo: pick")
	map("n", "]t", function()
		M.jump(1)
	end, "Todo: next open")
	map("n", "[t", function()
		M.jump(-1)
	end, "Todo: previous open")
	map("n", "q", function()
		if M.in_popup() then
			return "<cmd>silent! wall | qa<CR>"
		end
		return require("todo.capture").is_float(vim.api.nvim_get_current_win()) and "<cmd>close<CR>" or "q"
	end, "Todo: close inbox float / popup", { expr = true })
	if M.in_popup() then
		map("n", "<M-t>", "<cmd>silent! wall | qa<CR>", "Todo: close popup")
	end

	local group = vim.api.nvim_create_augroup("todo_buf_" .. buf, { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
		group = group,
		buffer = buf,
		callback = function()
			schedule_write(buf)
			require("todo.view").refresh(buf)
			require("todo.due").render(buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		buffer = buf,
		callback = function()
			require("todo.status").invalidate()
			vim.defer_fn(function()
				require("todo.route").route(buf)
			end, 20)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		buffer = buf,
		callback = function()
			if not vim.bo[buf].modified then
				vim.cmd("silent! checktime " .. buf)
			end
		end,
	})
	-- Reloaded from disk (another instance wrote it): checkmate only converts on attach and
	-- on its own writes, so redo the unicode markers and the view here.
	vim.api.nvim_create_autocmd("FileChangedShellPost", {
		group = group,
		buffer = buf,
		callback = function()
			vim.schedule(function()
				local ok, parser = pcall(require, "checkmate.parser")
				if ok and parser.convert_markdown_to_unicode then
					pcall(parser.convert_markdown_to_unicode, buf)
					vim.bo[buf].modified = false
				end
				require("todo.view").refresh(buf)
				require("todo.due").render(buf)
				require("todo.status").invalidate()
			end)
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = buf,
		callback = function()
			require("todo.due").cursor_moved(buf)
		end,
	})
end

--- Window-local view setup whenever a todo buffer is shown.
function M.win_enter(buf, win)
	require("todo.view").apply(buf, win)
	require("todo.due").render(buf)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("todo", { clear = true })
	local pattern = { M.files.work, M.files.personal }

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
		group = group,
		pattern = pattern,
		callback = function(ev)
			M.attach(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		pattern = pattern,
		callback = function(ev)
			M.attach(ev.buf)
			M.win_enter(ev.buf, vim.api.nvim_get_current_win())
		end,
	})
	vim.api.nvim_create_autocmd("BufLeave", {
		group = group,
		callback = function(ev)
			M.record_origin(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "FocusGained" }, {
		group = group,
		callback = function()
			require("todo.status").refresh()
		end,
	})
	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		once = true,
		callback = function()
			vim.defer_fn(function()
				require("todo.status").notify_stale_inbox()
			end, 1500)
		end,
	})

	local map = vim.keymap.set
	map("n", "<leader>to", function()
		M.open()
	end, { desc = "Todo: open (other file inside one)" })
	map("n", "<leader>ti", function()
		require("todo.capture").prompt()
	end, { desc = "Todo: capture to inbox" })
	map("x", "<leader>ti", function()
		require("todo.capture").prompt({ visual = true })
	end, { desc = "Todo: capture with @src" })
	map("n", "<leader>tI", function()
		require("todo.capture").float()
	end, { desc = "Todo: inbox float" })
end

return M
