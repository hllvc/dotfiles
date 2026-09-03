-- Neovim ships no runtime files for the terraform-vars filetype (*.tfvars), so borrow
-- terraform's -- same HCL grammar, same comment syntax. Highlighting is handled by
-- syntax/terraform-vars.vim (setting &syntax here would be overwritten by Neovim's own
-- syntaxset autocmd, which fires after ftplugins), and the treesitter parser mapping is
-- registered in autocmds.lua, early enough for the indentexpr autocmd and foldexpr.
vim.cmd("runtime! ftplugin/terraform.vim indent/terraform.vim")
