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

      -- Deshabilitar la completado nativo al usar multi-cursor
      set("n", { "<Leader>x", "<Leader>X" }, function()
        mc.addCursor()
      end, { desc = "Añadir cursor en la siguiente ocurrencia" })

      set({ "n", "v" }, "<C-S-down>", mc.lineAddCursor, { desc = "Añadir cursor línea abajo" })
      set({ "n", "v" }, "<C-S-up>", mc.lineAddCursorReverse, { desc = "Añadir cursor línea arriba" })
      set({ "n", "v" }, "<C-down>", mc.lineSkipCursor, { desc = "Saltar cursor línea abajo" })
      set({ "n", "v" }, "<C-up>", mc.lineSkipCursorReverse, { desc = "Saltar cursor línea arriba" })

      -- Deshacer cambios de multi-cursor con una tecla
      set("n", "<C-c>", mc.undoCursor, { desc = "Deshacer cursor" })
      set("n", "<C-r>", mc.redoCursor, { desc = "Rehacer cursor" })

      -- Mover cursor arriba/abajo
      set("n", "<C-p>", mc.prevCursor, { desc = "Cursor anterior" })
      set("n", "<C-n>", mc.nextCursor, { desc = "Cursor siguiente" })

      -- Pegar junto al cursor
      set("n", "<leader>P", mc.paste, { desc = "Pegar" })

      -- Copiar las líneas afectadas
      set("n", "<C-s>", mc.yankLines, { desc = "Copiar líneas afectadas" })

      -- Detectar cuando se pulse una tecla inusual
      local suggestions = mc.getSuggestions
      set("n", "<C-l>", function()
        suggestions()
      end, { desc = "Mostrar sugerencias de multi-cursor" })

      -- Salir del modo multi-cursor
      set("n", "<ESC>", mc.exit, { desc = "Salir de multi-cursor" })
    end,
  },
}
