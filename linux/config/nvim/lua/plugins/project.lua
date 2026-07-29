return {
  "ahmedkhalf/project.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  event = "VimEnter",
  config = function()
    require("project_nvim").setup({
      manual_mode = false,
      detection_methods = { "pattern", "lsp" },
      patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "package.json", "Makefile" },
      ignore_lsp = {},
      exclude_dirs = { "~/.cache/*", "~/.local/*" },
      show_hidden = false,
      silent_chdir = true,
      scope_chdir = "global",
      datapath = vim.fn.stdpath("data"),
    })
    pcall(require("telescope").load_extension, "projects")
  end,
}
