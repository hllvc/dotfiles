-- Autocommands
local function augroup(name)
  return vim.api.nvim_create_augroup("lazyvim_" .. name, { clear = true })
end

-- Makefile settings
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("makefile"),
  pattern = "make",
  callback = function()
    vim.opt_local.expandtab = false
  end,
})

-- Fugitive buffer settings
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("fugitive"),
  pattern = "fugitive://*",
  callback = function()
    vim.opt_local.bufhidden = "delete"
  end,
})

-- Shell/Zsh folding
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("shell_folding"),
  pattern = { "sh", "zsh" },
  callback = function()
    vim.opt_local.foldmethod = "marker"
    vim.opt_local.foldmarker = "#{{{,#}}}"
  end,
})

-- Remember folds (optimized to exclude certain filetypes for performance)
local fold_blacklist = {
  "dashboard", "lazy", "mason", "help", "alpha", "telescope", "trouble", "qf", ""
}

local function should_save_view()
  local ft = vim.bo.filetype
  local bufname = vim.fn.expand("%")

  -- Skip if no filename or blacklisted filetype
  if bufname == "" or vim.tbl_contains(fold_blacklist, ft) then
    return false
  end

  -- Skip if buffer is temporary or special
  if vim.bo.buftype ~= "" or vim.wo.previewwindow then
    return false
  end

  return true
end

vim.api.nvim_create_autocmd("BufWinLeave", {
  group = augroup("remember_folds"),
  pattern = "*",
  callback = function()
    if should_save_view() then
      vim.cmd("silent! mkview!")
    end
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = augroup("remember_folds"),
  pattern = "*",
  callback = function()
    if should_save_view() then
      vim.cmd("silent! loadview")
    end
  end,
})

-- -- Dockerfile detection
-- vim.api.nvim_create_autocmd({ "BufNewFile", "BufCreate", "BufRead" }, {
--   group = augroup("dockerfile"),
--   pattern = "Dockerfile*",
--   callback = function()
--     vim.bo.filetype = "dockerfile"
--   end,
-- })

-- Terraform vars filetype detection
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufCreate" }, {
  group = augroup("terraform_vars"),
  pattern = "*.tfvars",
  callback = function()
    vim.bo.filetype = "terraform-vars"
  end,
})

-- Helm chart filetype detection
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = augroup("helm_detection"),
  pattern = { "*/templates/*.yaml", "*/templates/*.tpl" },
  callback = function()
    vim.bo.filetype = "helm"
  end,
})

-- Helm Chart.yaml and values files detection
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  group = augroup("helm_yaml_files"),
  pattern = { "*/Chart.yaml", "*/values.yaml", "*/values-*.yaml" },
  callback = function()
    -- Keep yaml filetype for better LSP support with yamlls
    vim.bo.filetype = "yaml"
  end,
})

-- Strip trailing whitespace and newlines on save (combined for performance)
local function clean_buffer_on_save()
  -- Skip for certain filetypes or special buffers
  local ft = vim.bo.filetype
  if vim.tbl_contains({"markdown", "text", "diff", "gitcommit"}, ft) or vim.bo.buftype ~= "" then
    return
  end

  local save_cursor = vim.fn.getpos(".")

  -- Strip trailing whitespace
  vim.cmd([[%s/\s\+$//e]])

  -- Strip trailing newlines
  vim.cmd([[%s/\n\+\%$//e]])

  vim.fn.setpos(".", save_cursor)
end

vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("clean_buffer"),
  pattern = "*",
  callback = clean_buffer_on_save,
})

-- Add newline for C files
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("c_newline"),
  pattern = "*.[ch]",
  callback = function()
    vim.cmd([[%s/\%$/\r/e]])
  end,
})

-- Save all files on focus lost
vim.api.nvim_create_autocmd("FocusLost", {
  group = augroup("save_on_focus_lost"),
  pattern = "*",
  callback = function()
    vim.cmd("silent! wa")
  end,
})

-- Cursor position memory fallback (in case mkview/loadview fails)
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("cursor_position"),
  pattern = "*",
  callback = function()
    local ft = vim.bo.filetype
    -- Skip for certain filetypes and special buffers
    if vim.tbl_contains(fold_blacklist, ft) or vim.bo.buftype ~= "" then
      return
    end

    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Minimal LSP file change handling for better autocompletion
-- Only refresh when necessary to avoid breaking LSP functionality

-- Simple workspace refresh for configuration file changes
vim.api.nvim_create_autocmd("BufWritePost", {
  group = augroup("lsp_config_refresh"),
  pattern = {
    "package.json",    -- Node.js dependencies
    "tsconfig.json",   -- TypeScript config
    "go.mod",          -- Go modules
    "Cargo.toml",      -- Rust dependencies
    "pyproject.toml",  -- Python project config
    "requirements.txt", -- Python requirements
  },
  callback = function()
    -- Only refresh workspace configuration for config files
    vim.schedule(function()
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      for _, client in pairs(clients) do
        if client.supports_method("workspace/didChangeConfiguration") then
          client.notify("workspace/didChangeConfiguration", { settings = {} })
        end
      end
    end)
  end,
})

-- Handle external file changes
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = augroup("lsp_external_changes"),
  pattern = "*",
  callback = function()
    -- Let LSP handle file changes naturally
    vim.cmd("checktime")
  end,
})


-- Define a reusable function to update lualine configuration
local function update_lualine_config(config_update)
  local lualine_require = require("lualine_require")
  local modules = lualine_require.lazy_require({ config_module = "lualine.config" })

  local current_config = modules.config_module.get_config()

  -- Allow passing a function to modify the config
  if type(config_update) == "function" then
    config_update(current_config)
  elseif type(config_update) == "table" then
    -- Merge the provided config updates
    for section, value in pairs(config_update) do
      current_config.sections[section] = value
    end
  end

  require("lualine").setup(current_config)
end
