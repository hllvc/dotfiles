return {
  {
    "sainnhe/gruvbox-material",
    lazy = false,
    priority = 1000,
    config = function()
      -- Configure gruvbox-material
      vim.g.gruvbox_material_background = "medium"
      vim.g.gruvbox_material_foreground = "material"
      vim.g.gruvbox_material_enable_italic = 1
      vim.g.gruvbox_material_enable_bold = 1
      vim.g.gruvbox_material_transparent_background = 0
      vim.g.gruvbox_material_diagnostic_text_highlight = 1
      vim.g.gruvbox_material_diagnostic_line_highlight = 1
      vim.g.gruvbox_material_diagnostic_virtual_text = "colored"

      -- Set colorscheme
      vim.cmd("colorscheme gruvbox-material")

      -- Custom background color override
      vim.api.nvim_set_hl(0, "Normal", { bg = "#1b1b1b" })
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "#1b1b1b" })
      vim.api.nvim_set_hl(0, "SignColumn", { bg = "#1b1b1b" })
      vim.api.nvim_set_hl(0, "EndOfBuffer", { bg = "#1b1b1b" })

      -- Ensure terminal background matches
      if vim.fn.has("termguicolors") then
        vim.opt.termguicolors = true
      end
    end,
  },
}
