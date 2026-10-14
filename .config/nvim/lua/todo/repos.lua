-- Repo discovery under ~/.repos/<org>/<repo>. Repos use either a plain checkout or the
-- bare+worktree layout (<repo>/.bare plus one directory per branch).
local M = {}

-- realpath: buffer names and cwd come back resolved when ~/.repos is a symlink
M.root = vim.uv.fs_realpath(vim.fn.expand("~/.repos")) or vim.fn.expand("~/.repos")

-- Orgs that belong to the work context; every other org is personal.
local WORK_ORGS = { stackguardian = true }

local uv = vim.uv

function M.context_of_org(org)
	return WORK_ORGS[org] and "work" or "personal"
end

local function is_dir(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

function M.is_bare(dir)
	return is_dir(dir .. "/.bare")
end

local function subdirs(dir)
	local out = {}
	local handle = uv.fs_scandir(dir)
	while handle do
		local name, kind = uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if kind == "directory" and not name:match("^%.") then
			out[#out + 1] = name
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

function M.orgs()
	return subdirs(M.root)
end

--- Repos of one context, or of every context when `context` is nil.
---@return { name: string, org: string, context: string }[]
function M.list(context)
	local out = {}
	for _, org in ipairs(M.orgs()) do
		local ctx = M.context_of_org(org)
		if not context or ctx == context then
			for _, name in ipairs(subdirs(M.root .. "/" .. org)) do
				out[#out + 1] = { name = name, org = org, context = ctx }
			end
		end
	end
	return out
end

--- Find a repo by name across all orgs. Warns once per name when it is ambiguous.
local warned = {}
function M.resolve(name)
	if not name or name == "" then
		return nil
	end
	local found = {}
	for _, org in ipairs(M.orgs()) do
		local dir = M.root .. "/" .. org .. "/" .. name
		if is_dir(dir) then
			found[#found + 1] = { name = name, org = org, dir = dir, context = M.context_of_org(org) }
		end
	end
	if #found > 1 and not warned[name] then
		warned[name] = true
		vim.notify(("todo: repo %q exists in several orgs, using %s"):format(name, found[1].org), vim.log.levels.WARN)
	end
	return found[1]
end

--- Break a path under ~/.repos into org/repo/worktree/relative path.
---@return { org: string, repo: string, dir: string, context: string, worktree: string?, wt_dir: string, rel: string }?
function M.from_path(path)
	if not path or path == "" then
		return nil
	end
	path = vim.fs.normalize(path)
	local prefix = M.root .. "/"
	if path:sub(1, #prefix) ~= prefix then
		return nil
	end
	local org, repo, tail = path:sub(#prefix + 1):match("^([^/]+)/([^/]+)/?(.*)$")
	if not org then
		return nil
	end
	local dir = M.root .. "/" .. org .. "/" .. repo
	if not is_dir(dir) then
		return nil
	end
	local info = { org = org, repo = repo, dir = dir, context = M.context_of_org(org), wt_dir = dir, rel = tail }
	if M.is_bare(dir) then
		local wt, rel = tail:match("^([^/]+)/?(.*)$")
		if wt and wt ~= ".bare" then
			info.worktree, info.wt_dir, info.rel = wt, dir .. "/" .. wt, rel
		end
	end
	return info
end

--- Worktree directories of a repo (the repo dir itself for plain checkouts).
---@return { name: string, dir: string }[]
function M.worktrees(dir)
	if not M.is_bare(dir) then
		return { { name = vim.fn.fnamemodify(dir, ":t"), dir = dir } }
	end
	local out = {}
	local res = vim.system({ "git", "-C", dir .. "/.bare", "worktree", "list", "--porcelain" }, { text = true }):wait()
	local current
	for line in (res.stdout or ""):gmatch("[^\n]+") do
		local wt = line:match("^worktree (.+)$")
		if wt then
			current = wt
		elseif line == "bare" then
			current = nil
		elseif line:match("^HEAD ") and current and is_dir(current) then
			out[#out + 1] = { name = vim.fn.fnamemodify(current, ":t"), dir = current }
			current = nil
		end
	end
	return out
end

return M
