return {
  {
    "mg979/vim-visual-multi",
    branch = "master",
    lazy = false,
    init = function()
      vim.g.VM_theme = "codedark"
      vim.g.VM_maps = {
        ["Find Under"] = "cu",
        ["Find Subword Under"] = "cU",
        ["Add Cursor Down"] = "<M-Down>",
        ["Add Cursor Up"] = "<M-Up>",
        ["Select Cursor Down"] = "<M-S-Down>",
        ["Select Cursor Up"] = "<M-S-Up>",
        ["Visual Regex"] = "cr",
        -- Mouse conserva Ctrl como modificador: sin modificador
        -- secuestraría el click normal. Si lo quieres sin Ctrl, avisa
        -- y lo pasamos a Alt (<M-LeftMouse>).
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
