-- GitHub Actions workflow helpers the language servers don't cover.
--
-- Completion (an nvim-cmp source, registered in plugins/completion.lua):
--   uses: owner/repo@|         the action's tags: major tags (v4) first, then releases
--   branches: / branches-ignore:, ref:   the repo's branches (local + remote, deduped)
--   tags: / tags-ignore:, ref:           the repo's tags
--   paths: / paths-ignore:     repo-relative directories and files
--   working-directory:         repo-relative directories
--
-- Annotation: `uses:` lines pinned behind the action's latest release get an
-- end-of-line note (`← v5 available`). A major pin (@v4) is compared against the
-- latest major, a full pin (@v4.1.0) against the latest release.
--
-- Action tags come from `git ls-remote` (one request, every tag, no API rate
-- limit), falling back to `gh api` for private repos that https can't read. They
-- are fetched in the background and cached for the session; a failed fetch is
-- retried after RETRY_SECONDS. Local refs and files come straight from git.

local M = {}

local RETRY_SECONDS = 300
local FILES_TTL_SECONDS = 30
local MAX_FILES = 5000
local MAX_VERSIONS = 30

local WORKFLOW_DIRS = { "/.github/workflows", "/.forgejo/workflows", "/.gitea/workflows" }

---@param bufnr integer
---@return boolean
function M.is_workflow(bufnr)
	local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
	for _, suffix in ipairs(WORKFLOW_DIRS) do
		if vim.endswith(dir, suffix) then
			return true
		end
	end
	return false
end

local function run(cmd, opts, cb)
	opts = vim.tbl_extend("force", { text = true, timeout = 10000 }, opts or {})
	-- vim.system throws when the executable is missing; report that as a failure.
	local ok = pcall(vim.system, cmd, opts, function(res)
		vim.schedule(function()
			cb(res)
		end)
	end)
	if not ok then
		cb({ code = -1, stdout = "", stderr = "" })
	end
end

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------

---`v4` -> {4, major_only}, `v4.1.2` / `4.1` -> {4, 1, 2}, `v5.0.0-beta.1` -> pre.
---@param tag string
---@return table|nil
local function parse(tag)
	local major, rest = tag:match("^v?(%d+)(.*)$")
	if not major then
		return nil
	end
	if rest == "" then
		return { tonumber(major), 0, 0, major_only = true }
	end
	local minor, patch, pre = rest:match("^%.(%d+)%.?(%d*)(.*)$")
	if not minor or (pre ~= "" and not pre:match("^[-+]")) then
		return nil
	end
	return { tonumber(major), tonumber(minor), tonumber(patch) or 0, pre = pre ~= "" and pre or nil }
end

local function newer(a, b)
	for i = 1, 3 do
		if a[i] ~= b[i] then
			return a[i] > b[i]
		end
	end
	return false
end

---Tags split into what completion and the annotation need, newest first.
---@param tags string[]
local function classify(tags)
	local majors, releases, pre, other = {}, {}, {}, {}
	for _, tag in ipairs(tags) do
		local v = parse(tag)
		if not v then
			other[#other + 1] = { tag = tag }
		elseif v.major_only then
			majors[#majors + 1] = { tag = tag, v = v }
		elseif v.pre then
			pre[#pre + 1] = { tag = tag, v = v }
		else
			releases[#releases + 1] = { tag = tag, v = v }
		end
	end
	local function by_version(a, b)
		return newer(a.v, b.v)
	end
	table.sort(majors, by_version)
	table.sort(releases, by_version)
	table.sort(pre, by_version)
	table.sort(other, function(a, b)
		return a.tag > b.tag
	end)
	return { majors = majors, releases = releases, pre = pre, other = other }
end

-- ["owner/repo"] = { tags = string[]|nil, ok = bool, at = os.time(), waiting = fn[]|nil }
local action_tags = {}

---@param repo string owner/repo
---@param cb fun(tags: string[])
local function fetch_tags(repo, cb)
	local entry = action_tags[repo]
	if entry and entry.tags and (entry.ok or os.time() - entry.at < RETRY_SECONDS) then
		return cb(entry.tags)
	end
	if entry and entry.waiting then
		table.insert(entry.waiting, cb)
		return
	end

	entry = { waiting = { cb } }
	action_tags[repo] = entry
	local function finish(tags, ok)
		entry.tags, entry.ok, entry.at = tags, ok, os.time()
		local waiting = entry.waiting
		entry.waiting = nil
		for _, fn in ipairs(waiting) do
			fn(tags)
		end
	end

	run({ "git", "ls-remote", "--tags", "--refs", "https://github.com/" .. repo }, {
		env = { GIT_TERMINAL_PROMPT = "0" },
	}, function(res)
		local tags = {}
		if res.code == 0 then
			for name in res.stdout:gmatch("refs/tags/([^\n]+)") do
				tags[#tags + 1] = name
			end
		end
		if #tags > 0 then
			return finish(tags, true)
		end
		run({ "gh", "api", "repos/" .. repo .. "/tags?per_page=100", "--jq", ".[].name" }, {}, function(api)
			if api.code ~= 0 then
				return finish({}, false)
			end
			finish(vim.split(vim.trim(api.stdout), "\n", { trimempty = true }), true)
		end)
	end)
end

---------------------------------------------------------------------------
-- Local repo data
---------------------------------------------------------------------------

---@param root string
---@param cb fun(branches: string[])
local function local_branches(root, cb)
	run({ "git", "-C", root, "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes" }, {}, function(res)
		local seen, out = {}, {}
		for ref in (res.code == 0 and res.stdout or ""):gmatch("[^\n]+") do
			local name = ref:match("^refs/heads/(.+)$") or ref:match("^refs/remotes/[^/]+/(.+)$")
			if name and name ~= "HEAD" and not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
		cb(out)
	end)
end

---@param root string
---@param cb fun(tags: string[])
local function local_tags(root, cb)
	run({ "git", "-C", root, "tag", "--sort=-v:refname" }, {}, function(res)
		cb(res.code == 0 and vim.split(res.stdout, "\n", { trimempty = true }) or {})
	end)
end

-- [root] = { dirs = string[], files = string[], at = os.time() }
local repo_files = {}

---@param root string
---@param cb fun(entry: { dirs: string[], files: string[] })
local function tracked_paths(root, cb)
	local cached = repo_files[root]
	if cached and os.time() - cached.at < FILES_TTL_SECONDS then
		return cb(cached)
	end
	run({ "git", "-C", root, "ls-files" }, {}, function(res)
		local dirs, files, seen = {}, {}, {}
		for file in (res.code == 0 and res.stdout or ""):gmatch("[^\n]+") do
			if #files < MAX_FILES then
				files[#files + 1] = file
			end
			local dir = vim.fs.dirname(file)
			while dir ~= "." and dir ~= "" and not seen[dir] do
				seen[dir] = true
				dirs[#dirs + 1] = dir
				dir = vim.fs.dirname(dir)
			end
		end
		table.sort(dirs)
		repo_files[root] = { dirs = dirs, files = files, at = os.time() }
		cb(repo_files[root])
	end)
end

---------------------------------------------------------------------------
-- Completion
---------------------------------------------------------------------------

-- Keys whose values this source completes, mapped to what it offers.
local KEYS = {
	branches = "branches",
	["branches-ignore"] = "branches",
	tags = "tags",
	["tags-ignore"] = "tags",
	ref = "refs",
	paths = "paths",
	["paths-ignore"] = "paths",
	["working-directory"] = "dirs",
}

local USES = "uses:%s*[\"']?([%w_.-]+/[%w_.-]+)[^@%s\"']*@"

---The YAML key the cursor is completing a value for: `key: val|` / `key: [a, b|`
---on the cursor line, or the parent key of a `- item|` block list.
---@return string|nil
local function value_key(bufnr, row, before)
	local inline = before:match("^%s*%-?%s*([%w_-]+):%s")
	if inline then
		return inline
	end
	local item_indent = before:match("^(%s*)%-%s+[\"']?[^%s:\"']*$")
	if not item_indent then
		return nil
	end
	for r = row - 1, math.max(0, row - 200), -1 do
		local line = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1] or ""
		if line:match("%S") and not line:match("^%s*#") then
			local indent = #line:match("^%s*")
			-- Sibling items of the same list, possibly at the key's own indent.
			if not (indent == #item_indent and line:match("^%s*%-")) then
				if indent <= #item_indent then
					return line:match("^%s*%-?%s*([%w_-]+):%s*$")
				end
			end
		end
	end
	return nil
end

local function items(labels, kind, first_detail)
	local out = {}
	for i, label in ipairs(labels) do
		out[i] = {
			label = label,
			kind = kind,
			sortText = string.format("%05d", i),
			labelDetails = i == 1 and first_detail and { description = first_detail } or nil,
		}
	end
	return out
end

---@param tags string[]
local function version_items(tags, kind)
	local c = classify(tags)
	local labels, details = {}, {}
	local function add(list, limit, detail)
		for i, t in ipairs(list) do
			if limit and i > limit then
				break
			end
			labels[#labels + 1] = t.tag
			details[#labels] = detail
		end
	end
	add(c.majors, nil, "major")
	add(c.releases, MAX_VERSIONS, "release")
	add(c.pre, 10, "pre-release")
	add(c.other, 20, nil)
	local out = items(labels, kind)
	for i, item in ipairs(out) do
		item.labelDetails = details[i] and { description = details[i] } or nil
	end
	if out[1] then
		out[1].labelDetails = { description = "latest " .. (details[1] or "") }
	end
	return out
end

function M.cmp_source()
	local kinds = require("cmp").lsp.CompletionItemKind
	local source = {}

	function source:is_available()
		return M.is_workflow(vim.api.nvim_get_current_buf())
	end

	function source:get_debug_name()
		return "gha"
	end

	function source:get_trigger_characters()
		return { "@", "/" }
	end

	-- `.`, `-`, `/`, `*` belong to the word being completed: v4.1.0, feat/x, src/**.
	-- `@` does not, so after `uses: owner/repo@` only the ref is replaced.
	function source:get_keyword_pattern()
		return [=[[[:alnum:]_./*-]\+]=]
	end

	function source:complete(params, callback)
		local ctx = params.context
		local bufnr, before = ctx.bufnr, ctx.cursor_before_line
		if before:match("^%s*#") then
			return callback()
		end

		local repo = before:match(USES .. "[^%s\"']*$")
		if repo then
			return fetch_tags(repo, function(tags)
				callback(version_items(tags, kinds.Constant))
			end)
		end

		local want = KEYS[value_key(bufnr, ctx.cursor.row - 1, before) or ""]
		local root = want and vim.fs.root(bufnr, ".git")
		if not root then
			return callback()
		end

		if want == "branches" then
			local_branches(root, function(branches)
				callback(items(branches, kinds.Reference))
			end)
		elseif want == "tags" then
			local_tags(root, function(tags)
				callback(items(tags, kinds.Constant))
			end)
		elseif want == "refs" then
			local_branches(root, function(branches)
				local_tags(root, function(tags)
					callback(vim.list_extend(items(branches, kinds.Reference), items(tags, kinds.Constant)))
				end)
			end)
		else
			tracked_paths(root, function(entry)
				if want == "dirs" then
					return callback(items(entry.dirs, kinds.Folder))
				end
				local dirs = vim.tbl_map(function(d)
					return d .. "/"
				end, entry.dirs)
				callback(vim.list_extend(items(dirs, kinds.Folder), items(entry.files, kinds.File)))
			end)
		end
	end

	return source
end

---------------------------------------------------------------------------
-- Outdated pins
---------------------------------------------------------------------------

local ns = vim.api.nvim_create_namespace("gha_versions")

-- Bumped on every pass, so a slow fetch from an older pass can't draw stale marks.
local generation = {}

---The note for a pin, or nil when it is current (or not a version at all).
local function newer_note(tags, ref)
	local pin = parse(ref)
	if not pin or pin.pre then
		return nil
	end
	local c = classify(tags)
	local latest = c.releases[1] or c.majors[1]
	if not latest then
		return nil
	end
	if pin.major_only then
		if latest.v[1] <= pin[1] then
			return nil
		end
		-- Name the floating major tag when the action publishes one.
		for _, m in ipairs(c.majors) do
			if m.v[1] == latest.v[1] then
				return m.tag
			end
		end
		return latest.tag
	end
	return newer(latest.v, pin) and latest.tag or nil
end

---Rewrite every pin that has a newer release to the version its note names (the
---latest major for @v4-style pins, the latest release for full ones). Works off the
---tags already fetched for the notes, so it never waits on the network, and runs
---as a single change: one `u` undoes the lot.
---@param bufnr? integer
function M.bump(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local bumped = {}
	for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		if not line:match("^%s*#") then
			local _, finish, repo, ref = line:find(USES .. "([%w_.-]+)")
			local entry = repo and action_tags[repo]
			local note = entry and entry.tags and newer_note(entry.tags, ref)
			if note then
				vim.api.nvim_buf_set_text(bufnr, row - 1, finish - #ref, row - 1, finish, { note })
				bumped[#bumped + 1] = string.format("%s %s → %s", repo, ref, note)
			end
		end
	end
	if #bumped == 0 then
		vim.notify("No action pins behind their latest release", vim.log.levels.INFO)
	else
		vim.notify("Bumped " .. #bumped .. " pin(s):\n" .. table.concat(bumped, "\n"), vim.log.levels.INFO)
	end
	M.annotate(bufnr)
end

---Annotate every `uses: owner/repo@ref` in a workflow that has a newer release.
---@param bufnr integer
function M.annotate(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not M.is_workflow(bufnr) then
		return
	end
	generation[bufnr] = (generation[bufnr] or 0) + 1
	local gen = generation[bufnr]
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	-- Set on every pass rather than once: a colorscheme switch clears custom groups.
	vim.api.nvim_set_hl(0, "GhaNewerVersion", { link = "DiagnosticHint", default = true })

	local pins = {} -- repo -> { { row, ref } }
	for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		if not line:match("^%s*#") then
			local repo, ref = line:match(USES .. "([%w_.-]+)")
			if repo then
				pins[repo] = pins[repo] or {}
				table.insert(pins[repo], { row - 1, ref })
			end
		end
	end

	for repo, list in pairs(pins) do
		fetch_tags(repo, function(tags)
			if generation[bufnr] ~= gen or not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			for _, pin in ipairs(list) do
				local note = newer_note(tags, pin[2])
				if note then
					pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, pin[1], 0, {
						virt_text = { { "← " .. note .. " available", "GhaNewerVersion" } },
						virt_text_pos = "eol",
					})
				end
			end
		end)
	end
end

return M
