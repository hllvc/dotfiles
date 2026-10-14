-- Line parser for todo files. Works on buffer lines (checkmate's unicode markers) and on
-- the Markdown on disk alike, so the view, status line, picker and routing share one model.
local M = {}

-- Markdown and checkmate's default display markers.
M.markers = {
	["[ ]"] = "unchecked",
	["[x]"] = "checked",
	["[X]"] = "checked",
	["□"] = "unchecked",
	["✔"] = "checked",
}

M.ROUTING = { work = true, personal = true }

-- Tags passed down to children that don't set their own.
local INHERITED = { "repo", "priority", "due" }

local function indent_of(line)
	return #line:match("^%s*")
end

--- Parse a todo line: indent, marker, state, text after the marker. Nil for anything else.
function M.todo_line(line)
	local indent, rest = line:match("^(%s*)[-*+] (.*)$")
	if not indent then
		return nil
	end
	for marker, state in pairs(M.markers) do
		if rest:sub(1, #marker) == marker then
			local after = rest:sub(#marker + 1)
			if after == "" or after:match("^%s") then
				return { indent = #indent, marker = marker, state = state, text = vim.trim(after) }
			end
		end
	end
	return nil
end

--- `@tag(value)` pairs of one line, plus bare routing tags (`@work`, `@personal`).
function M.tags(line)
	local tags, routing = {}, {}
	for name, value in line:gmatch("@([%a][%w_%-]*)(%b())") do
		if tags[name] == nil then
			tags[name] = value:sub(2, -2)
		end
	end
	for start, name, stop in line:gmatch("()@(%a+)()") do
		local prev = start > 1 and line:sub(start - 1, start - 1) or " "
		if M.ROUTING[name] and line:sub(stop, stop) ~= "(" and not prev:match("[%w_]") then
			routing[name] = true
		end
	end
	return tags, routing
end

--- Byte range (1-based, inclusive) of a tag's value on a line, or nil.
function M.tag_range(line, name)
	local s, e = line:find("@" .. vim.pesc(name) .. "%b()")
	if not s then
		return nil
	end
	return s + #name + 2, e - 1, s, e
end

---@class todo.Item
---@field row integer 1-based line of the item
---@field last integer 1-based last line of its subtree (notes and children)
---@field indent integer
---@field state "checked"|"unchecked"
---@field text string
---@field tags table<string, string>
---@field routing table<string, boolean>
---@field eff table<string, string> tags after inheritance
---@field parent integer? index of the parent item
---@field section string? name of the `##` heading it sits under

--- Parse whole-file lines.
---@return { items: todo.Item[], owner: table<integer, integer>, sections: table<string, { row: integer, last: integer }>, headings: table<integer, boolean> }
function M.parse(lines)
	local items, owner, sections, headings = {}, {}, {}, {}
	local stack = {} -- open items (indices), innermost last
	local section
	local n = #lines

	local function close_until(indent)
		while #stack > 0 and items[stack[#stack]].indent >= indent do
			table.remove(stack)
		end
	end

	for row = 1, n do
		local line = lines[row]
		local heading = line:match("^#+%s+(.-)%s*$")
		if heading then
			stack = {}
			if section then
				sections[section].last = row - 1
			end
			section = heading
			sections[heading] = { row = row, last = n }
			headings[row] = true
		elseif line:match("^%s*$") then
			-- blank: resolved after the pass (belongs to the item only if more of it follows)
		else
			local todo = M.todo_line(line)
			local indent = indent_of(line)
			if todo then
				close_until(todo.indent)
				local tags, routing = M.tags(line)
				local item = {
					row = row,
					last = row,
					indent = todo.indent,
					state = todo.state,
					text = todo.text,
					tags = tags,
					routing = routing,
					eff = {},
					parent = stack[#stack],
					section = section,
				}
				items[#items + 1] = item
				stack[#stack + 1] = #items
				owner[row] = #items
			else
				-- notes and plain list items belong to the innermost open item that is less indented
				close_until(indent)
				if #stack > 0 then
					owner[row] = stack[#stack]
				else
					stack = {}
				end
			end
			for _, idx in ipairs(stack) do
				items[idx].last = row
			end
		end
	end

	-- a blank line inside a subtree (followed by more of it) belongs to that subtree
	for row = 1, n do
		if owner[row] == nil and not headings[row] and lines[row]:match("^%s*$") then
			local next_row = row + 1
			while next_row <= n and lines[next_row]:match("^%s*$") do
				next_row = next_row + 1
			end
			local nxt = owner[next_row]
			if nxt then
				local idx = nxt
				while idx do
					local item = items[idx]
					if item.row < row and item.last >= next_row then
						owner[row] = idx
						break
					end
					idx = item.parent
				end
			end
		end
	end

	for _, item in ipairs(items) do
		local parent = item.parent and items[item.parent]
		for _, name in ipairs(INHERITED) do
			item.eff[name] = item.tags[name] or (parent and parent.eff[name]) or nil
		end
	end

	return { items = items, owner = owner, sections = sections, headings = headings }
end

--- Index of the innermost item that owns `row`, or nil.
function M.item_at(parsed, row)
	return parsed.owner[row]
end

--- Items whose ancestors are not in `set`: the outermost ones of a selection.
function M.outermost(parsed, indices)
	local set = {}
	for _, idx in ipairs(indices) do
		set[idx] = true
	end
	local out = {}
	for _, idx in ipairs(indices) do
		local parent, covered = parsed.items[idx].parent, false
		while parent do
			if set[parent] then
				covered = true
				break
			end
			parent = parsed.items[parent].parent
		end
		if not covered then
			out[#out + 1] = idx
		end
	end
	table.sort(out, function(a, b)
		return parsed.items[a].row < parsed.items[b].row
	end)
	return out
end

--- Markdown for disk: checkmate's display markers back to `[ ]` / `[x]`.
function M.to_markdown(line)
	return (line:gsub("^(%s*[-*+] )□", "%1[ ]"):gsub("^(%s*[-*+] )✔", "%1[x]"))
end

--- Display markers for a checkmate buffer.
function M.to_unicode(line)
	return (line:gsub("^(%s*[-*+] )%[ %]", "%1□"):gsub("^(%s*[-*+] )%[[xX]%]", "%1✔"))
end

--- Strip bare routing tags from a line.
function M.strip_routing(line)
	for name in pairs(M.ROUTING) do
		line = line:gsub("%s*@" .. name .. "%f[^%w_%-(]", "")
	end
	return line
end

--- Set, replace or (value == nil) remove a `@tag(value)` on a line.
function M.set_tag(line, name, value)
	local _, _, s, e = M.tag_range(line, name)
	if s then
		if value == nil then
			local before, after = line:sub(1, s - 1):gsub("%s+$", ""), line:sub(e + 1)
			return before .. after
		end
		return line:sub(1, s - 1) .. "@" .. name .. "(" .. value .. ")" .. line:sub(e + 1)
	end
	if value == nil then
		return line
	end
	return line:gsub("%s*$", "") .. " @" .. name .. "(" .. value .. ")"
end

return M
