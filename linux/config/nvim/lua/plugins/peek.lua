return {
  "iamcco/markdown-preview.nvim",
  ft = "markdown",
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  keys = {
    { "<leader>mp", "<cmd>MarkdownPreview<cr>", desc = "Markdown: abrir preview en navegador" },
    { "<leader>mc", "<cmd>MarkdownPreviewStop<cr>", desc = "Markdown: cerrar preview" },
  },
  config = function()
    vim.g.mkdp_auto_start = 0
    vim.g.mkdp_auto_close = 1
    vim.g.mkdp_refresh_slow = 0
    vim.g.mkdp_browser = "brave"
    vim.g.mkdp_markdown_css = ""
    vim.g.mkdp_highlight_css = ""
    vim.g.mkdp_port = 0
    vim.g.mkdp_page_title = "${name}"
  end,
}
