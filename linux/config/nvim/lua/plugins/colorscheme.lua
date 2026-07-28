return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    config = function()
      require("rose-pine").setup({
        variant = "main", -- 'auto', 'main', 'moon', or 'dawn'
        dark_variant = "main",
        bold_vert_split = false,
        dim_nc_background = false,
        disable_background = false,
        disable_float_background = false,
        styles = {
          bold = true,
          italic = true,
          transparency = false,
        },
        highlight_groups = {
          -- Intensificar los acentos rojos (Love)
          CursorLine = { bg = "#1f1d2e" },
          StatusLine = { fg = "#eb6f92", bg = "#191724" },
          NvimTreeNormal = { bg = "#191724" },
        },
      })
      vim.cmd("colorscheme rose-pine-main")
    end,
  },
}
