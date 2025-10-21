-- options
local opt = vim.opt
local o = vim.o
local g = vim.g

-- Basic options
opt.termguicolors = true
opt.syntax = "on"
opt.filetype = "on"

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Encoding and file handling
opt.encoding = "utf-8"
opt.swapfile = false
opt.autoread = true
opt.history = 1000

-- Editing behavior
opt.backspace = "indent,eol,start"
opt.clipboard = "unnamedplus"
opt.cursorline = true
opt.cursorlineopt = "both"

-- go to previous/next line with h,l,left arrow and right arrow
-- when cursor reaches end/beginning of line
-- opt.whichwrap:append "<>[]hl"

-- GUI options
opt.guioptions = ""
opt.mouse = ""

-- Search settings
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false
opt.incsearch = true

-- UI settings
opt.errorbells = false
opt.visualbell = false
opt.wrap = true
opt.linebreak = true
opt.showbreak = "↪"
opt.autoindent = true
opt.laststatus = 0
opt.scrolloff = 10
opt.hidden = true
opt.showmode = false

-- Command line
opt.wildmenu = true
opt.wildmode = "longest:full,full"

-- Ignore patterns
opt.wildignore:append({
  "*.pyc",
  "*_build/*",
  "**/coverage/*",
  "**/node_modules/*",
  "**/android/*",
  "**/ios/*",
  "**/.git/*"
})

opt.shell = vim.env.SHELL
opt.cmdheight = 1
opt.title = true
opt.showmatch = true
opt.updatetime = 250
opt.timeoutlen = 300
opt.backup = true
opt.writebackup = true
opt.backupdir = vim.env.HOME .. "/.nvim-backups/"
opt.signcolumn = "yes"
opt.shortmess:append("c")

-- Tab settings
opt.smarttab = true
opt.expandtab = true
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.shiftround = true

-- Code folding
opt.foldenable = true
opt.foldlevel = 0
opt.foldmethod = "syntax"
opt.foldlevelstart = 99

-- Invisible characters
opt.list = true
opt.listchars = {
  tab = "→ ",
  eol = "¬",
  trail = "⋅",
  extends = "❯",
  precedes = "❮"
}

-- Color column
opt.colorcolumn = "80"

-- View options for cursor position and fold memory
opt.viewoptions = "cursor,folds,slash,unix"
