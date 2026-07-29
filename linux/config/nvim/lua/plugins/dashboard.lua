return {
  "nvimdev/dashboard-nvim",
  event = "VimEnter",
  config = function()
    -- Función para leer el archivo y devolverlo como tabla
    local function get_header()
      local lines = {}
      local file = io.open(vim.fn.expand("~/.config/nvim/logo.txt"), "r")
      if file then
        for line in file:lines() do
          table.insert(lines, line)
        end
        file:close()
      end
      return lines
    end

    require("dashboard").setup({
      theme = 'doom',
      config = {
        header = get_header(),
        center = {
          { action = "Telescope projects", desc = "Projects", key = "p" },
          { action = "Telescope oldfiles", desc = "Recents", key = "r" },
          { action = "e ~/.config/nvim/init.lua", desc = "Config", key = "c" },
          { action = "qa", desc = "Exit", key = "q" },
        },
      },
    })
  end,
  dependencies = { "nvim-tree/nvim-web-devicons" }
}
