return {
  -- Helm chart support
  {
    "towolf/vim-helm",
    ft = "helm",
    init = function()
      -- Enable Helm syntax detection
      vim.g.helm_template_search_path = "templates"
    end,
  },
}
