-- Format-on-save scoped to the lines you actually touched.
--
-- Reformatting a whole file that has never been formatted (or was formatted by
-- some other tool) turns a one-line change into a PR where 90% of the diff is
-- noise. When this mode is on, save-time formatting is kept to the git hunks in
-- the buffer; everything you did not touch is left alone.
--
-- Each hunk is handed to conform as a range, and only to formatters that can
-- target a range natively (stylua, ruff_format, prettier). Everything else
-- formats the whole buffer as before.
--
-- Both restrictions are there because the alternatives lose content. Formatting
-- once and reverting the regions outside the hunks is cheaper, but a formatter's
-- diff routinely splits one logical change into a delete beside the edit and an
-- insert anchored far away, and judging those by position drops the half holding
-- the new text. Handing a range to a formatter that cannot honour it makes
-- conform diff a whole-file reformat and apply whichever regions overlap, which
-- fails the same way: isort reordering imports turned an 8-line file into 6.
--
-- On by default. <leader>uf toggles it, <leader>F still formats the whole
-- buffer on demand.

local M = {}

local FORMAT_OPTS = { timeout_ms = 1000, lsp_format = "fallback", async = false }

-- Past this many hunks, format the span from the first to the last in one go.
-- A save that touches this many places is a rewrite, not a tweak, and the run
-- per hunk stops being worth it.
local MAX_HUNKS = 8

---@return boolean
function M.changed_only()
	return vim.g.format_changed_only ~= false
end

function M.toggle()
	vim.g.format_changed_only = not M.changed_only()
	vim.notify("Format on save: " .. (M.changed_only() and "changed lines only" or "whole buffer"), vim.log.levels.INFO)
end

---Line ranges of the buffer's git hunks, bottom-up.
---@param bufnr integer
---@return integer[][]|nil ranges nil when git has no view of the buffer (not a
---  repo, gitsigns not attached) and the caller should format the whole thing
local function hunk_ranges(bufnr)
	local ok, gitsigns = pcall(require, "gitsigns")
	if not ok then
		return nil
	end

	-- nil when gitsigns is not attached to this buffer, {} when it is attached
	-- and the buffer matches the index. Those mean opposite things: the first
	-- is "I don't know", the second is "nothing changed".
	local hunks = gitsigns.get_hunks(bufnr)
	if hunks == nil then
		return nil
	end

	local last = vim.api.nvim_buf_line_count(bufnr)
	local ranges = {}
	for _, hunk in ipairs(hunks) do
		-- Pure deletions have no lines left to format.
		if hunk.added.count > 0 then
			local start = math.min(hunk.added.start, last)
			table.insert(ranges, { start, math.min(start + hunk.added.count - 1, last) })
		end
	end

	if #ranges > MAX_HUNKS then
		ranges = { { ranges[1][1], ranges[#ranges][2] } }
	end

	-- Bottom-up: formatting a range can add or drop lines, which would shift
	-- every range below it. Ranges above it keep their line numbers.
	local reversed = {}
	for i = #ranges, 1, -1 do
		table.insert(reversed, ranges[i])
	end
	return reversed
end

-- prettier advertises range support but only honours it for the js/ts family.
-- Everywhere else it either ignores the range and reformats the whole document
-- (json) or hands back the input untouched (markdown, html, css, yaml), which
-- would silently leave your new lines unformatted. These take the whole-buffer
-- path instead. Measured against prettier 3.x -- recheck if that changes.
local NO_RANGE_FILETYPES = {
	css = true,
	helm = true,
	html = true,
	json = true,
	markdown = true,
	yaml = true,
}

---Formatters for this buffer that can restrict themselves to a range.
---@param bufnr integer
---@return string[]|nil names nil when none of them can
local function range_formatters(bufnr)
	if NO_RANGE_FILETYPES[vim.bo[bufnr].filetype] then
		return nil
	end

	local conform = require("conform")
	local names = {}
	for _, formatter in ipairs(conform.list_formatters_to_run(bufnr)) do
		local config = conform.get_formatter_config(formatter.name, bufnr)
		if config and config.range_args then
			table.insert(names, formatter.name)
		end
	end
	if vim.tbl_isempty(names) then
		return nil
	end
	return names
end

---Format only the changed lines of `bufnr`.
---@param bufnr integer
---@return boolean handled false when the caller should format the whole buffer
function M.format_changed(bufnr)
	local ranges = hunk_ranges(bufnr)
	if ranges == nil then
		return false
	end
	-- Buffer matches the index, or the only change was a deletion. Nothing to
	-- format, and nothing to hand back to the caller either: a save must not
	-- reformat a file just because git has no hunks in it.
	if vim.tbl_isempty(ranges) then
		return true
	end

	local formatters = range_formatters(bufnr)
	if formatters == nil then
		return false
	end

	local conform = require("conform")
	for _, range in ipairs(ranges) do
		-- The end column has to be the real end of the line. Formatters with
		-- native range support (stylua, ruff, prettier) get the range as byte
		-- offsets and conform does not clamp them, so a column of 0 would hand
		-- them an empty range and they would format nothing.
		local last_line = vim.api.nvim_buf_get_lines(bufnr, range[2] - 1, range[2], false)[1] or ""
		conform.format(vim.tbl_extend("force", FORMAT_OPTS, {
			bufnr = bufnr,
			formatters = formatters,
			range = { start = { range[1], 0 }, ["end"] = { range[2], #last_line } },
		}))
	end
	return true
end

return M
