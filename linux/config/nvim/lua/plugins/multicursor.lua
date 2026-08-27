return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "main",
    lazy = false,
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()

      local set = vim.keymap.set

      set({ "n", "x" }, "<Leader>n", function()
        mc.matchAddCursor(1)
      end, { desc = "MC: cursor en siguiente coincidencia" })

      set({ "n", "x" }, "<Leader>N", function()
        mc.matchAddCursor(-1)
      end, { desc = "MC: cursor en coincidencia anterior" })

      set({ "n", "x" }, "<Leader>S", function()
        mc.matchSkipCursor(1)
      end, { desc = "MC: saltar siguiente coincidencia" })

      set({ "n", "x" }, "<Leader>B", function()
        mc.matchSkipCursor(-1)
      end, { desc = "MC: saltar coincidencia anterior" })

      set({ "n", "x" }, "<Leader>j", function()
        mc.lineAddCursor(1)
      end, { desc = "MC: añadir cursor línea abajo" })

      set({ "n", "x" }, "<Leader>k", function()
        mc.lineAddCursor(-1)
      end, { desc = "MC: añadir cursor línea arriba" })

      mc.addKeymapLayer(function(layer)
        layer({ "n", "x" }, "<left>", mc.prevCursor, { desc = "MC: cursor anterior" })
        layer({ "n", "x" }, "<right>", mc.nextCursor, { desc = "MC: cursor siguiente" })
        layer({ "n", "x" }, "<Leader>x", mc.deleteCursor, { desc = "MC: borrar cursor actual" })
        layer({ "n", "x" }, "<c-q>", mc.toggleCursor, { desc = "MC: habilitar/deshabilitar" })

        layer("n", "<esc>", function()
          if mc.cursorsEnabled() then
            mc.clearCursors()
          else
            mc.enableCursors()
          end
        end, { desc = "MC: volver a un cursor" })
      end)
    end,
  },
}
