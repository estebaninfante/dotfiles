return {
  {
    "mg979/vim-visual-multi",
    branch = "master",
    lazy = false,
    init = function()
      vim.g.VM_theme = "codedark"
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>",
        ["Find Subword Under"] = "<C-n>",
        ["Add Cursor Down"] = "<C-Down>",
        ["Add Cursor Up"] = "<C-Up>",
        ["Select Cursor Down"] = "<C-S-Down>",
        ["Select Cursor Up"] = "<C-S-Up>",
        ["Visual Regex"] = "<C-r>",
        ["Mouse Cursor"] = "<C-LeftMouse>",
        ["Mouse Word"] = "<C-RightMouse>",
        ["Mouse Plug"] = "<C-LeftDrag>",
        ["Mouse Insert"] = "<C-LeftRelease>",
        ["Switch Mode"] = "q",
        ["Find Next"] = "n",
        ["Find Prev"] = "N",
      }
    end,
  },
}
