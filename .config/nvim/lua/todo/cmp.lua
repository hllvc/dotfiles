-- nvim-cmp source for todo tags, in todo files and the capture prompt:
--   `@`       tag names (checkmate metadata + the @work / @personal routing tags)
--   `@tag(`   that tag's values (tags.choices, the same list checkmate's value picker uses)
local tags = require("todo.tags")

local M = {}

local NAMES = { "priority", "due", "repo", "started", "done", "src", "from", "captured" }

function M.new()
	local kinds = require("cmp").lsp.CompletionItemKind
	local source = {}

	function source:is_available()
		return vim.b.todo ~= nil or vim.b.todo_capture == true
	end

	function source:get_debug_name()
		return "todo_tags"
	end

	function source:get_trigger_characters()
		return { "@", "(" }
	end

	-- dates, repo names and @src paths: `-`, `/`, `.`, `:` belong to the word
	function source:get_keyword_pattern()
		return [=[[[:alnum:]_./:-]\+]=]
	end

	function source:complete(params, callback)
		local before = params.context.cursor_before_line

		local tag = before:match("@([%a][%w_%-]*)%(([^()]*)$")
		if tag then
			local out = {}
			if tag == "due" then
				for _, k in ipairs(tags.due_keywords()) do
					out[#out + 1] = {
						label = k.word,
						filterText = k.word .. " " .. k.date,
						insertText = k.date .. ")",
						labelDetails = { description = k.date },
						kind = kinds.Constant,
					}
				end
			else
				for i, value in ipairs(tags.choices(tag)) do
					out[#out + 1] = {
						label = value,
						insertText = value .. ")",
						sortText = ("%03d"):format(i),
						kind = tag == "repo" and kinds.Folder or kinds.EnumMember,
					}
				end
			end
			return callback(out)
		end

		if before:match("@[%w_%-]*$") then
			local out = {}
			for _, name in ipairs(NAMES) do
				out[#out + 1] = {
					label = name,
					insertText = name .. "(",
					kind = kinds.Property,
					data = { reopen = true },
				}
			end
			for name in pairs(require("todo.parse").ROUTING) do
				out[#out + 1] = {
					label = name,
					insertText = name,
					labelDetails = { description = "move to " .. name .. " file" },
					kind = kinds.Keyword,
				}
			end
			return callback(out)
		end

		callback()
	end

	-- after `@priority(` is inserted, open the value list straight away
	function source:execute(item, callback)
		if item.data and item.data.reopen then
			vim.schedule(function()
				require("cmp").complete()
			end)
		end
		callback(item)
	end

	return source
end

return M
