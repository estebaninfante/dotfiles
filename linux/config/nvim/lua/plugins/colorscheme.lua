return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    config = function()
      -- dawn = variante CLARA cálida (combina con kitty crema #FDF8F0)
      require("rose-pine").setup({
        variant = "dawn", -- 'auto', 'main' (oscuro), 'moon', or 'dawn'
        dark_variant = "main",
        bold_vert_split = false,
        dim_nc_background = true, -- fondo de ventana inactiva atenuado
        disable_background = false,
        disable_float_background = false,
        styles = {
          bold = true,
          italic = false, -- astigmatismo: nada de itálicas
          transparency = false,
        },
        highlight_groups = {
          CursorLine = { bg = "#f2ede3" }, -- crema sutil sobre base clara
          Visual = { bg = "#e0dacf" },
        },
      })
      vim.cmd("colorscheme rose-pine-dawn")
    end,
  },
}
