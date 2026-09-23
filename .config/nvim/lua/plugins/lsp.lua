-- gh_actions_ls only talks to GitHub when it is handed a token and the repo a
-- workflow belongs to. Without them it skips everything remote: `with:` inputs of the
-- action a step uses, `secrets.`/`vars.` names, environments, self-hosted runner
-- labels. The token is the `gh` CLI's own; the repo comes from `gh api` against the
-- checkout's remote. Both are looked up once per session (per repo), and a failed
-- lookup just leaves the server offline.
--
-- The lookup runs in the background, from root_dir: on_dir() is only called once it
-- is done, so the server starts with the answers in hand while the buffer draws and
-- highlights straight away. Doing it with :wait() in before_init froze the UI on
-- first open for the length of a keychain read plus a round trip to api.github.com.
local gh = { token = nil, repos = {}, pending = {} }

local function gh_run(cmd, opts, cb)
	opts = vim.tbl_extend("force", { text = true, timeout = 5000 }, opts or {})
	vim.system(cmd, opts, function(res)
		vim.schedule(function()
			cb(res)
		end)
	end)
end

---Fill gh.token and gh.repos for the repo holding `root`, then call `done`.
---@param root string
---@param done fun()
local function gh_actions_prefetch(root, done)
	if vim.fn.executable("gh") == 0 then
		gh.token = false
	end
	local top = vim.fs.root(root, ".git")
	if gh.token == false or (gh.token and (not top or gh.repos[top] ~= nil)) then
		return done()
	end

	-- Several workflows opened at once share one lookup.
	local key = top or root
	if gh.pending[key] then
		table.insert(gh.pending[key], done)
		return
	end
	gh.pending[key] = { done }
	local function flush()
		local waiting = gh.pending[key]
		gh.pending[key] = nil
		for _, cb in ipairs(waiting) do
			cb()
		end
	end

	local function fetch_repo()
		if not gh.token or not top or gh.repos[top] ~= nil then
			return flush()
		end
		gh_run({
			"gh",
			"api",
			"repos/{owner}/{repo}",
			"--jq",
			'{id: .id, owner: .owner.login, name: .name, organizationOwned: (.owner.type == "Organization")}',
		}, { cwd = top }, function(res)
			local ok, repo = pcall(vim.json.decode, res.stdout or "")
			if res.code == 0 and ok and type(repo) == "table" then
				repo.workspaceUri = vim.uri_from_fname(top)
				gh.repos[top] = repo
			else
				gh.repos[top] = false
			end
			flush()
		end)
	end

	if gh.token == nil then
		gh_run({ "gh", "auth", "token" }, {}, function(res)
			gh.token = res.code == 0 and vim.trim(res.stdout) or false
			fetch_repo()
		end)
	else
		fetch_repo()
	end
end

---Init options from whatever gh_actions_prefetch found. Never blocks.
---@param root string|nil
---@return table
local function gh_actions_context(root)
	if not gh.token then
		return {}
	end
	local top = root and vim.fs.root(root, ".git")
	local repo = top and gh.repos[top]
	return { sessionToken = gh.token, repos = repo and { repo } or nil }
end

return {
	-- Mason
	{
		"mason-org/mason.nvim",
		cmd = "Mason",
		keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
		build = ":MasonUpdate",
		opts = {
			ensure_installed = {
				"stylua",
				"prettier",
				"prettierd",
				"yamllint",
				"actionlint",
				"zizmor",
				"jq",
				"xmlformatter",
				"shfmt",
				"shellcheck",
				"ruff",
				"tflint",
			},
		},
		config = function(_, opts)
			require("mason").setup(opts)
			local mr = require("mason-registry")
			mr:on("package:install:success", function()
				vim.defer_fn(function()
					require("lazy.core.handler.event").trigger({
						event = "FileType",
						buf = vim.api.nvim_get_current_buf(),
					})
				end, 100)
			end)
			local function ensure_installed()
				for _, tool in ipairs(opts.ensure_installed) do
					local p = mr.get_package(tool)
					if not p:is_installed() then
						p:install()
					end
				end
			end
			vim.defer_fn(function()
				if mr.refresh then
					mr.refresh(ensure_installed)
				else
					ensure_installed()
				end
			end, 2000)
		end,
	},

	-- Standalone linting
	{
		"mfussenegger/nvim-lint",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local lint = require("lint")
			lint.linters_by_ft = {
				sh = { "shellcheck" },
				bash = { "shellcheck" },
				yaml = { "yamllint" },
				python = { "ruff" },
				-- terraformls (below) already reports validation diagnostics, and
				-- terraform_validate shells out to `terraform validate` on every read and
				-- write -- which errors outright in any directory that was never init'd.
				-- tfsec is EOL upstream (folded into Trivy). tflint is the one that earns
				-- its spawn. Note `tf` is not a filetype: Neovim detects *.tf as terraform.
				terraform = { "tflint" },
			}

			-- GitHub Actions workflows are plain `yaml` (no filetype of their own), so they
			-- are picked out by path, the same way gh_actions_ls decides where to attach.
			-- actionlint adds what neither LSP does: shellcheck over `run:` blocks,
			-- runner labels, `needs:` graphs, action inputs.
			--
			-- yamllint's defaults are noise on workflows: `on:` trips truthy on every file,
			-- and long `run:`/`${{ }}` lines trip line-length. A project's own .yamllint
			-- still wins; the relaxed config only stands in when there is none.
			lint.linters.yamllint_gha = vim.tbl_extend("force", lint.linters.yamllint, {
				args = {
					"--format",
					"parsable",
					"-d",
					"{extends: default, rules: {truthy: {check-keys: false}, document-start: disable, line-length: disable}}",
					"-",
				},
			})
			-- zizmor audits workflow security (template injection, dangerous triggers,
			-- credential persistence, permissions). It reads the file from disk rather than
			-- stdin: on stdin zizmor 1.30 ignores --config and its own zizmor.yml discovery.
			-- Its default wants every `uses:` hash-pinned; linters/zizmor.yml relaxes that to
			-- tags so `@v4` passes, again only when the repo has no zizmor.yml of its own.
			-- With the `gh` token (the same background lookup gh_actions_ls uses) it also
			-- runs the online audits: known-vulnerable actions, impostor commits, stale
			-- refs. Without one those skip themselves and the offline audits still run.
			--
			-- The stock parser reads a file location's path from `Local.given_path`, which
			-- zizmor 1.30 renamed to `verbatim_path`; every file-based run dies indexing nil.
			-- Map the new name onto the old one before handing the output over.
			local zizmor_parser = lint.linters.zizmor.parser
			local zizmor = vim.tbl_extend("force", lint.linters.zizmor, {
				stdin = false,
				parser = function(output, bufnr, ...)
					local ok, decoded = pcall(vim.json.decode, output)
					if ok and type(decoded) == "table" then
						for _, diag in ipairs(decoded) do
							for _, loc in ipairs(diag.locations or {}) do
								local key = loc.symbolic and loc.symbolic.key
								if key and key.Local and not key.Local.given_path then
									key.Local.given_path = key.Local.verbatim_path
								end
							end
						end
						output = vim.json.encode(decoded)
					end
					return zizmor_parser(output, bufnr, ...)
				end,
			})
			lint.linters.zizmor = vim.tbl_extend("force", zizmor, { args = { "--format", "json-v1" } })
			lint.linters.zizmor_gha = vim.tbl_extend("force", zizmor, {
				args = {
					"--format",
					"json-v1",
					"--config",
					vim.fs.joinpath(vim.fn.stdpath("config"), "linters", "zizmor.yml"),
				},
			})

			local function is_gha_workflow(bufnr)
				return vim.endswith(vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)), "/.github/workflows")
			end
			local function has_config(bufnr, names)
				return vim.fs.root(bufnr, names) ~= nil
			end

			-- No InsertLeave: it fired on every <Esc> and spawned the linters on the
			-- interactive path (terraform used to run three of them per <Esc>).
			vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
				group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
				callback = function(ev)
					if vim.bo[ev.buf].filetype == "yaml" and is_gha_workflow(ev.buf) then
						local yamllint = has_config(ev.buf, { ".yamllint", ".yamllint.yaml", ".yamllint.yml" })
								and "yamllint"
							or "yamllint_gha"
						local zizmor = has_config(ev.buf, { "zizmor.yml", "zizmor.yaml" }) and "zizmor" or "zizmor_gha"
						-- Skip whatever Mason has not installed yet (fresh machine, install still
						-- running): try_lint raises ENOENT on every read otherwise.
						local function installed(name)
							return vim.fn.executable(lint.linters[name].cmd) == 1
						end
						lint.try_lint(vim.tbl_filter(installed, { "actionlint", yamllint }))

						-- zizmor waits for the token so even the first run gets the online
						-- audits; the lookup is cached, so after the first file this is
						-- immediate. nvim-lint's `env` replaces the environment rather than
						-- extending it, hence environ() underneath GH_TOKEN.
						if installed(zizmor) then
							local buf = ev.buf
							gh_actions_prefetch(vim.fs.dirname(vim.api.nvim_buf_get_name(buf)), function()
								if not vim.api.nvim_buf_is_valid(buf) then
									return
								end
								vim.api.nvim_buf_call(buf, function()
									lint.try_lint(zizmor, {
										wrap_linter = function(linter)
											if gh.token then
												linter.env =
													vim.tbl_extend("force", vim.fn.environ(), { GH_TOKEN = gh.token })
											end
											return linter
										end,
									})
								end)
							end)
						end
					else
						lint.try_lint()
					end
				end,
			})
		end,
	},

	-- Neovim Lua development
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				{ path = "luvit-meta/library", words = { "vim%.uv" } },
			},
		},
	},
	{ "Bilal2453/luvit-meta", lazy = true },

	-- LSP progress and notification system
	{
		"j-hui/fidget.nvim",
		event = "VeryLazy",
		opts = {
			notification = {
				window = {
					winblend = 0,
					align = "bottom",
					relative = "editor",
				},
				override_vim_notify = false,
			},
		},
	},

	-- LSP servers
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"mason.nvim",
			"mason-org/mason-lspconfig.nvim",
			"hrsh7th/cmp-nvim-lsp",
			"b0o/schemastore.nvim",
		},
		opts = {
			diagnostics = {
				underline = true,
				update_in_insert = false,
				virtual_text = false,
				severity_sort = true,
				signs = {
					text = {
						[vim.diagnostic.severity.ERROR] = " ",
						[vim.diagnostic.severity.WARN] = " ",
						[vim.diagnostic.severity.HINT] = " ",
						[vim.diagnostic.severity.INFO] = " ",
					},
				},
			},
			inlay_hints = {
				enabled = false,
			},
			codelens = {
				enabled = false,
			},
			capabilities = {},
			format = {
				formatting_options = nil,
				timeout_ms = nil,
			},
			servers = {
				lua_ls = {
					settings = {
						Lua = {
							workspace = {
								checkThirdParty = false,
							},
							completion = {
								callSnippet = "Replace",
							},
						},
					},
				},
				pyright = {
					settings = {
						python = {
							analysis = {
								diagnosticMode = "openFilesOnly",
								autoSearchPaths = true,
								useLibraryCodeForTypes = true,
							},
						},
					},
				},
				eslint = {
					settings = {
						run = "onSave",
					},
				},
				terraformls = {
					-- Nearest ancestor holding terraform config/state wins, so each root module
					-- gets its own client instead of one client at the repo root. Replaces
					-- lspconfig.util.root_pattern (deprecated since 0.11 in favour of vim.lsp.config);
					-- a predicate rather than `root_markers` because markers match exact base names,
					-- never the *.tf glob.
					root_dir = function(bufnr, on_dir)
						on_dir(vim.fs.root(bufnr, function(name)
							return name:match("%.tf$") ~= nil
								or name == ".terraform"
								or name == ".terraform.lock.hcl"
								or name == ".git"
						end))
					end,
				},
				helm_ls = {
					settings = {
						["helm-ls"] = {
							yamlls = {
								path = "yaml-language-server",
							},
						},
					},
				},
				yamlls = {
					settings = {
						yaml = {
							-- Schemas come from schemastore.nvim (setup.yamlls below).
							format = {
								enable = true,
								-- yamlls's bundled prettier defaults to double quotes and rewrites
								-- every '...' in the file on save. Single quotes are literal (no
								-- escape processing) and what most workflows already use; prettier
								-- still picks double when the text itself holds a '.
								singleQuote = true,
							},
							validate = true,
							completion = true,
						},
					},
				},
				gh_actions_ls = {
					init_options = {
						-- Code action that fills in an action's required `with:` inputs.
						experimentalFeatures = { missingInputsQuickfix = true },
					},
					-- Multi-line completions (`with:` + newline + one indent level) come
					-- indented relative to the cursor line, leaning on the client's
					-- adjustIndentation. nvim-cmp only honours that for snippets and inserts
					-- plain text as-is, so the new line landed at column 2 instead of under the
					-- step. Re-indent every continuation line by the cursor line's indentation
					-- before cmp sees the items.
					on_init = function(client)
						local request = client.request
						client.request = function(self, method, params, handler, ...)
							if method ~= "textDocument/completion" or type(handler) ~= "function" then
								return request(self, method, params, handler, ...)
							end
							local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
							local line = vim.api.nvim_buf_get_lines(
								bufnr,
								params.position.line,
								params.position.line + 1,
								false
							)[1] or ""
							local indent = "\n" .. line:match("^%s*")
							return request(self, method, params, function(err, result, ...)
								local items = result and (result.items or result) or {}
								for _, item in ipairs(items) do
									if item.textEdit and item.textEdit.newText then
										item.textEdit.newText = item.textEdit.newText:gsub("\n", indent)
									end
									if item.insertText then
										item.insertText = item.insertText:gsub("\n", indent)
									end
								end
								return handler(err, result, ...)
							end, ...)
						end
					end,
					-- lspconfig's own root_dir (workflow directories only), plus the GitHub
					-- lookup: the server starts once gh_actions_prefetch is done.
					root_dir = function(bufnr, on_dir)
						local parent = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
						for _, dir in ipairs({ "/.github/workflows", "/.forgejo/workflows", "/.gitea/workflows" }) do
							if vim.endswith(parent, dir) then
								return gh_actions_prefetch(parent, function()
									if vim.api.nvim_buf_is_valid(bufnr) then
										on_dir(parent)
									end
								end)
							end
						end
					end,
					before_init = function(params, config)
						params.initializationOptions = vim.tbl_extend(
							"force",
							params.initializationOptions or {},
							gh_actions_context(config.root_dir)
						)
					end,
				},
				jsonls = {},
				marksman = {},
			},
			setup = {
				jsonls = function(_, opts)
					local has_schemastore, schemastore = pcall(require, "schemastore")
					if has_schemastore then
						opts.settings = {
							json = {
								schemas = schemastore.json.schemas(),
								validate = { enable = true },
							},
						}
					end
					vim.lsp.config("jsonls", opts)
					vim.lsp.enable("jsonls")
					return true
				end,
				-- yamlls pulls the whole SchemaStore catalog by default, workflow schema
				-- included, which repeats every error gh_actions_ls and actionlint already
				-- report on workflows. Swap its built-in store for schemastore.nvim's catalog
				-- minus that one entry; everything else (action.yml, compose, dependabot, ...)
				-- keeps its schema.
				yamlls = function(_, opts)
					local has_schemastore, schemastore = pcall(require, "schemastore")
					if has_schemastore then
						opts.settings.yaml.schemaStore = { enable = false, url = "" }
						opts.settings.yaml.schemas = schemastore.yaml.schemas({
							ignore = { "GitHub Workflow" },
							extra = {
								{
									name = "Kubernetes",
									description = "Kubernetes v1.18 manifests",
									fileMatch = { "*.k8s.yaml" },
									url = "https://raw.githubusercontent.com/instrumenta/kubernetes-json-schema/master/v1.18.0-standalone-strict/all.json",
								},
							},
						})
					end
					vim.lsp.config("yamlls", opts)
					vim.lsp.enable("yamlls")
					return true
				end,
			},
		},
		config = function(_, opts)
			local servers = opts.servers
			local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
			local capabilities = vim.tbl_deep_extend(
				"force",
				{},
				vim.lsp.protocol.make_client_capabilities(),
				has_cmp and cmp_nvim_lsp.default_capabilities() or {},
				opts.capabilities or {}
			)

			local function setup(server)
				local server_opts = vim.tbl_deep_extend("force", {
					capabilities = vim.deepcopy(capabilities),
				}, servers[server] or {})

				if opts.setup[server] then
					if opts.setup[server](server, server_opts) then
						return
					end
				elseif opts.setup["*"] then
					if opts.setup["*"](server, server_opts) then
						return
					end
				end
				vim.lsp.config(server, server_opts)
				vim.lsp.enable(server)
			end

			-- mason-lspconfig 2.x dropped the `handlers` dispatch and only honors
			-- ensure_installed/automatic_enable. So build the install list, turn OFF
			-- automatic_enable (otherwise mason re-enables each server with stock config
			-- and silently drops our per-server settings + cmp capabilities), then
			-- configure every server ourselves via setup().
			local ensure_installed = {}
			for server, server_opts in pairs(servers) do
				if server_opts then
					server_opts = server_opts == true and {} or server_opts
					if server_opts.mason ~= false then
						ensure_installed[#ensure_installed + 1] = server
					end
				end
			end

			local have_mason, mlsp = pcall(require, "mason-lspconfig")
			if have_mason then
				mlsp.setup({ ensure_installed = ensure_installed, automatic_enable = false })
			end

			for server, server_opts in pairs(servers) do
				if server_opts then
					setup(server)
				end
			end

			-- Configure diagnostics
			vim.diagnostic.config(vim.deepcopy(opts.diagnostics))

			-- LSP keymaps
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("UserLspConfig", {}),
				callback = function(ev)
					-- Inlay hints stay off in general (opts.inlay_hints), but on workflows
					-- gh_actions_ls uses them to spell out `cron:` schedules in plain English.
					local client = vim.lsp.get_client_by_id(ev.data.client_id)
					if
						client
						and client.name == "gh_actions_ls"
						and client:supports_method("textDocument/inlayHint")
					then
						vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
					end

					local function map(mode, lhs, rhs, desc)
						vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc })
					end

					-- Jump directly for single result, open Trouble for multiple
					local function on_list(options)
						vim.fn.setqflist({}, " ", options)
						if #options.items == 1 then
							vim.cmd.cfirst()
						else
							vim.cmd("Trouble qflist open focus=true")
						end
					end

					-- Navigation
					map("n", "gD", function()
						vim.lsp.buf.declaration({ on_list = on_list })
					end, "Go to Declaration")
					map("n", "gd", function()
						vim.lsp.buf.definition({ on_list = on_list })
					end, "Go to Definition")
					map("n", "K", vim.lsp.buf.hover, "Hover")
					map("n", "gi", function()
						vim.lsp.buf.implementation({ on_list = on_list })
					end, "Go to Implementation")
					-- nowait: fire immediately instead of waiting timeoutlen to disambiguate
					-- nvim 0.12's default grn/gra/grr/gri/grt chords (we use our own scheme).
					vim.keymap.set("n", "gr", function()
						vim.lsp.buf.references(nil, { on_list = on_list })
					end, { buffer = ev.buf, nowait = true, desc = "References" })

					-- Code actions (<leader>c group)
					map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
					map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code Action")
					map("n", "<leader>cD", function()
						vim.lsp.buf.type_definition({ on_list = on_list })
					end, "Type Definition")
					map("n", "<leader>cd", vim.diagnostic.open_float, "Diagnostic Float")
					map(
						"n",
						"<leader>cq",
						"<cmd>Trouble diagnostics toggle focus=true filter.buf=0<cr>",
						"Buffer Diagnostics (Trouble)"
					)
					map("n", "<leader>k", vim.lsp.buf.signature_help, "Signature Help")

					-- Workspace
					map("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, "Add Workspace Folder")
					map("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, "Remove Workspace Folder")
					map("n", "<leader>wl", function()
						print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
					end, "List Workspace Folders")

					-- Diagnostic navigation
					map("n", "[d", function()
						vim.diagnostic.jump({ count = -1 })
					end, "Previous Diagnostic")
					map("n", "]d", function()
						vim.diagnostic.jump({ count = 1 })
					end, "Next Diagnostic")
				end,
			})
		end,
	},

	-- Mason LSP config. No opts here on purpose: the nvim-lspconfig `config` above is
	-- the single caller of mason-lspconfig.setup() (with automatic_enable=false). Giving
	-- this spec `opts` would make lazy auto-call setup() a second time with the default
	-- automatic_enable=true, re-enabling servers with stock config. Install list lives in
	-- the `servers` table above and is derived in that config function.
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = { "mason.nvim" },
	},

	-- Language-specific tools and enhancements

	-- Go
	{
		"ray-x/go.nvim",
		dependencies = {
			"ray-x/guihua.lua",
			"neovim/nvim-lspconfig",
			"nvim-treesitter/nvim-treesitter",
		},
		config = function()
			require("go").setup()
		end,
		-- ft only: with event=CmdlineEnter too, lazy OR-combined them and loaded go.nvim
		-- (+ guihua) on the first ":" in ANY buffer, not just Go files.
		ft = { "go", "gomod" },
		build = ':lua require("go.install").update_all_sync()',
	},

	-- Rust. Off, but deliberately still installed: no Rust work at the moment, so this
	-- spec (and the rust-analyzer it starts) never loads. Drop the `cond` line to
	-- restore it -- but bump the pin first: `^4` is a dead major (4.26.1, predating
	-- Neovim 0.12) and upstream is on v9, so re-enabling as-is revives an unmaintained
	-- version.
	--
	-- `cond = false`, not `enabled = false`: enabled removes the plugin from the spec
	-- entirely, which puts its directory on `:Lazy clean`'s delete list. cond keeps it
	-- in the spec (installed, updated, simply never loaded) and marks it
	-- ignore_installed, so clean leaves it alone.
	{
		"mrcjkb/rustaceanvim",
		cond = false,
		version = "^4",
		ft = { "rust" },
		opts = {
			server = {
				on_attach = function(_, bufnr)
					vim.keymap.set("n", "<leader>cR", function()
						vim.cmd.RustLsp("codeAction")
					end, { desc = "Code Action", buffer = bufnr })
					vim.keymap.set("n", "<leader>dr", function()
						vim.cmd.RustLsp("debuggables")
					end, { desc = "Rust debuggables", buffer = bufnr })
				end,
				default_settings = {
					["rust-analyzer"] = {
						cargo = {
							allFeatures = true,
							loadOutDirsFromCheck = true,
							runBuildScripts = true,
						},
						checkOnSave = {
							allFeatures = true,
							command = "clippy",
							extraArgs = { "--no-deps" },
						},
						procMacro = {
							enable = true,
							ignored = {
								["async-trait"] = { "async_trait" },
								["napi-derive"] = { "napi" },
								["async-recursion"] = { "async_recursion" },
							},
						},
					},
				},
			},
		},
		config = function(_, opts)
			vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, opts or {})
		end,
	},

	-- Python
	{
		"linux-cultist/venv-selector.nvim",
		-- nvim-dap-python dropped from the deps: it, and nvim-dap behind it, had no
		-- trigger of their own, nothing ever called dap_python.setup(), and no debug
		-- adapter was ever installed -- so they sat on disk doing nothing. The dap
		-- integration here is pcall-guarded (venv-selector's path.update_python_dap),
		-- so it degrades cleanly. Re-add this entry if a debugger ever comes back.
		dependencies = { "neovim/nvim-lspconfig", "nvim-telescope/telescope.nvim" },
		-- `opts = {}` must stay even though it is empty: lazy only calls setup() when a
		-- spec has opts or config, and :VenvSelect is created inside setup()
		-- (user_commands.lua) -- the plugin ships no plugin/ dir. The old
		-- `name = { "venv", ".venv", ... }` in here was a v1 option that v2 ignores; its
		-- default searches already walk cwd/workspace for bin/python (covering those
		-- four) plus poetry, pipenv, conda and pipx. Requires `fd` on PATH.
		opts = {},
		ft = "python",
		keys = {
			{ "<leader>vs", "<cmd>VenvSelect<cr>", ft = "python", desc = "Select Venv" },
		},
	},

	-- JavaScript/TypeScript
	{
		"pmizio/typescript-tools.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig", "hrsh7th/cmp-nvim-lsp" },
		ft = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
		config = function()
			local capabilities = vim.lsp.protocol.make_client_capabilities()
			local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
			if has_cmp then
				capabilities = vim.tbl_deep_extend("force", capabilities, cmp_nvim_lsp.default_capabilities())
			end
			require("typescript-tools").setup({
				capabilities = capabilities,
			})
		end,
	},

	-- HTML/CSS
	{
		"mattn/emmet-vim",
		ft = { "html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact" },
		init = function()
			-- <C-g> not <C-y>: <C-y> is the normal-mode scroll key (mappings.lua), <C-z> is
			-- tmux suspend. mode "iv" + install_global=0 keep emmet in insert/visual and out
			-- of non-emmet buffers, so the scroll map is never shadowed by an emmet prefix.
			vim.g.user_emmet_leader_key = "<C-g>"
			vim.g.user_emmet_mode = "iv"
			vim.g.user_emmet_install_global = 0
		end,
	},

	-- Markdown
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = "cd app && yarn install",
		init = function()
			vim.g.mkdp_filetypes = { "markdown" }
		end,
		ft = { "markdown" },
	},

	-- Git integration
	{
		"rhysd/conflict-marker.vim",
		event = { "BufReadPost" },
		config = function()
			vim.g.conflict_marker_highlight_group = ""
			vim.g.conflict_marker_begin = "^<<<<<<< .*$"
			vim.g.conflict_marker_end = "^>>>>>>> .*$"
			vim.g.conflict_marker_separator = "^=======$"

			-- Key mappings for conflict resolution
			vim.keymap.set("n", "<leader>gdo", "<Plug>(conflict-marker-ourselves)", { desc = "Take Ours (conflict)" })
			vim.keymap.set(
				"n",
				"<leader>gdt",
				"<Plug>(conflict-marker-themselves)",
				{ desc = "Take Theirs (conflict)" }
			)
			vim.keymap.set("n", "<leader>gdn", "<Plug>(conflict-marker-none)", { desc = "Take Neither (conflict)" })
			vim.keymap.set("n", "<leader>gdb", "<Plug>(conflict-marker-both)", { desc = "Take Both (conflict)" })
			vim.keymap.set("n", "[x", "<Plug>(conflict-marker-prev-hunk)", { desc = "Previous conflict" })
			vim.keymap.set("n", "]x", "<Plug>(conflict-marker-next-hunk)", { desc = "Next conflict" })
		end,
	},
	{
		"tpope/vim-fugitive",
		dependencies = { "tpope/vim-rhubarb" },
		cmd = { "Git", "Gwrite", "Gread", "Gvdiffsplit", "Gdiffsplit", "Gblame", "Gpush", "Gpull", "GBrowse" },
		keys = {
			{ "<leader>gs", "<cmd>Git<cr>", desc = "Git Status" },
			{ "<leader>gc", "<cmd>Git commit<cr>", desc = "Git Commit" },
			{ "<leader>gp", "<cmd>Git push<cr>", desc = "Git Push" },
			{ "<leader>gl", "<cmd>Git log --oneline<cr>", desc = "Git Log" },
			{ "<leader>gb", "<cmd>Git blame<cr>", desc = "Git Blame" },
			{ "<leader>gds", "<cmd>Gvdiffsplit<cr>", desc = "Git Diff Split" },
			{ "<leader>gB", "<cmd>silent GBrowse<cr>", desc = "Browse on GitHub", silent = true },
			{
				"<leader>gB",
				":<C-u>silent '<,'>GBrowse<cr>",
				mode = "v",
				desc = "Browse selection on GitHub",
				silent = true,
			},
			{ "<leader>gY", "<cmd>silent GBrowse!<cr>", desc = "Copy GitHub URL", silent = true },
			{
				"<leader>gY",
				":<C-u>silent '<,'>GBrowse!<cr>",
				mode = "v",
				desc = "Copy GitHub URL (selection)",
				silent = true,
			},
		},
	},
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "" },
				change = { text = "" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "" },
				untracked = { text = "" },
			},
			signs_staged = {
				add = { text = "" },
				change = { text = "" },
				delete = { text = "" },
				topdelete = { text = "" },
				changedelete = { text = "" },
				untracked = { text = "" },
			},
			signs_staged_enable = true,
			-- Enable line number highlighting (equivalent to gitgutter highlight_linenrs)
			numhl = false,
			on_attach = function(buffer)
				local gs = package.loaded.gitsigns

				local function map(mode, l, r, desc)
					vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
				end

				map("n", "]h", function()
					gs.nav_hunk("next")
				end, "Next Hunk")
				map("n", "[h", function()
					gs.nav_hunk("prev")
				end, "Prev Hunk")
				map({ "n", "v" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
				map({ "n", "v" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
				map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
				-- stage_hunk toggles: on an already-staged hunk it unstages. That needs
				-- signs_staged_enable (above) to track staged hunks, and it replaces the
				-- deprecated undo_stage_hunk. Same operation as <leader>ghs; kept as its
				-- own binding for muscle memory.
				map("n", "<leader>ghu", gs.stage_hunk, "Unstage Hunk")
				map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
				map("n", "<leader>ghp", gs.preview_hunk, "Preview Hunk")
				map("n", "<leader>ghb", function()
					gs.blame_line({ full = true })
				end, "Blame Line")
				map("n", "<leader>ghd", gs.diffthis, "Diff This")
				map("n", "<leader>ghD", function()
					gs.diffthis("~")
				end, "Diff This ~")
				-- Was toggle_deleted (deprecated). Upstream's replacement is per-hunk at the
				-- cursor rather than a buffer-wide toggle.
				map("n", "<leader>gt", gs.preview_hunk_inline, "Preview Hunk Inline")
				map("n", "<leader>gw", gs.toggle_word_diff, "Toggle Word Diff")
				map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "GitSigns Select Hunk")
			end,
		},
	},

	-- Copilot
	{
		"zbirenbaum/copilot.lua",
		event = "InsertEnter",
		config = function()
			require("copilot").setup({
				suggestion = {
					enabled = true,
					auto_trigger = true, -- Show suggestions automatically
					debounce = 200,
					keymap = {
						accept = false, -- Disabled - use C-l via nvim-cmp instead
						dismiss = false,
						next = "<M-]>",
						prev = "<M-[>",
					},
				},
				panel = { enabled = false },
			})
		end,
	},

	-- TMUX integration
	{
		"christoomey/vim-tmux-navigator",
		keys = {
			{ "<M-h>", "<cmd>TmuxNavigateLeft<cr>", mode = { "n", "v", "t" } },
			{ "<M-j>", "<cmd>TmuxNavigateDown<cr>", mode = { "n", "v", "t" } },
			{ "<M-k>", "<cmd>TmuxNavigateUp<cr>", mode = { "n", "v", "t" } },
			{ "<M-l>", "<cmd>TmuxNavigateRight<cr>", mode = { "n", "v", "t" } },
			{ "<M-\\>", "<cmd>TmuxNavigatePrevious<cr>", mode = { "n", "v", "t" } },
		},
	},

	-- Zoom windows
	{
		"dhruvasagar/vim-zoom",
		-- <Plug>(zoom-toggle), not :ZoomToggle -- the plugin defines no command. Mapping
		-- it here also replaces vim-zoom's own default <C-W>m, which lazy would shadow.
		keys = {
			{ "<C-w>m", "<Plug>(zoom-toggle)", desc = "Zoom toggle" },
		},
	},
}
