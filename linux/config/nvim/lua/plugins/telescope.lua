return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "ahmedkhalf/project.nvim",
  },
  config = function()
    require("telescope").setup()
    pcall(require("telescope").load_extension, "projects")
  end,
}
