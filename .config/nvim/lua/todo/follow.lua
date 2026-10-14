-- Follow a todo: `@src(repo/worktree/path:l1-l2)` opens that file and line; otherwise the
-- item's (effective) `@repo` opens the repo in a new tmux window, picking a worktree first
-- when there is more than one.
local parse = require("todo.parse")
local repos = require("todo.repos")

local M = {}

--- Resolve an @src value to a file path and line.
function M.resolve_src(value)
	local name, rest, l1 = value:match("^([^/]+)/(.-):(%d+)")
	if not name then
		name, rest = value:match("^([^/]+)/(.+)$")
	end
	local repo = name and repos.resolve(name)
	if not repo then
		return nil
	end
	local path = repo.dir .. "/" .. rest
	if repos.is_bare(repo.dir) and not vim.uv.fs_stat(path) then
		-- the worktree is gone: fall back to main/
		local sub = rest:match("^[^/]+/(.+)$")
		if sub then
			path = repo.dir .. "/main/" .. sub
		end
	end
	return path, tonumber(l1) or 1
end

local function open_repo(name)
	local repo = repos.resolve(name)
	if not repo then
		return vim.notify("todo: repo not found: " .. name, vim.log.levels.WARN)
	end
	local function go(dir)
		if vim.env.TMUX then
			vim.system({ "tmux", "new-window", "-c", dir, "-n", name })
		else
			require("snacks").picker.files({ cwd = dir })
		end
	end
	local wts = repos.worktrees(repo.dir)
	if #wts <= 1 then
		return go(wts[1] and wts[1].dir or repo.dir)
	end
	vim.ui.select(wts, {
		prompt = name .. " worktree",
		format_item = function(wt)
			return wt.name
		end,
	}, function(wt)
		if wt then
			go(wt.dir)
		end
	end)
end

--- From the tmux popup: open the file in the origin pane's nvim, or in a new window when
--- that pane runs something else, then close the popup.
function M.to_pane(pane, path, lnum)
	local cmd = vim.system({ "tmux", "display", "-p", "-t", pane, "#{pane_current_command}" }, { text = true }):wait()
	if vim.trim(cmd.stdout or "") == "nvim" then
		local ex = ("edit +%d %s"):format(lnum, vim.fn.fnameescape(path))
		-- <C-\><C-n> rather than Escape: Escape followed by ":" can arrive as <M-:>
		vim.system({ "tmux", "send-keys", "-t", pane, "C-\\", "C-n" }):wait()
		vim.system({ "tmux", "send-keys", "-t", pane, "-l", ":" .. ex }):wait()
		vim.system({ "tmux", "send-keys", "-t", pane, "Enter" }):wait()
	else
		vim.system({ "tmux", "new-window", "-c", vim.fn.fnamemodify(path, ":h"), "nvim", "+" .. lnum, path }):wait()
	end
	vim.cmd("silent! wall | qa")
end

function M.follow()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local parsed = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	local idx = parsed.owner[row]
	if not idx then
		return vim.notify("todo: no item here", vim.log.levels.WARN)
	end
	local item = parsed.items[idx]
	if item.tags.src then
		local path, lnum = M.resolve_src(item.tags.src)
		if not path or not vim.uv.fs_stat(path) then
			return vim.notify("todo: @src not found: " .. item.tags.src, vim.log.levels.WARN)
		end
		local pane = require("todo").in_popup()
		if pane then
			return M.to_pane(pane, path, lnum)
		end
		if require("todo.capture").is_float(vim.api.nvim_get_current_win()) then
			vim.cmd("close")
		end
		vim.cmd.edit(vim.fn.fnameescape(path))
		pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
		vim.cmd("normal! zvzz")
		return
	end
	local repo = item.eff.repo or item.tags.from
	if repo then
		return open_repo(repo)
	end
	vim.notify("todo: nothing to follow (no @src or @repo)", vim.log.levels.WARN)
end

return M
