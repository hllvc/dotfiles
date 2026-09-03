" Neovim detects *.tfvars as `terraform-vars` (so terraform-ls treats them as variable
" files) but ships no syntax file for that filetype. Same HCL grammar as terraform.
if exists('b:current_syntax')
  finish
endif

runtime! syntax/terraform.vim
