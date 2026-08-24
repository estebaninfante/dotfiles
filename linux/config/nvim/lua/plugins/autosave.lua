return {
  "okuuva/auto-save.nvim",
  cmd = "ASToggle",
  event = { "InsertLeave", "TextChanged" },
  opts = {
    execution_delay = 500, -- ms tras dejar insert/editar antes de guardar
  },
}
