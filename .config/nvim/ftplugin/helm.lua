-- Neovim ships no runtime files for helm, which leaves commentstring empty and makes
-- gc a no-op. A template comment is stripped at render time, unlike `#`, which ends
-- up in the rendered manifest.
vim.bo.commentstring = "{{/* %s */}}"
