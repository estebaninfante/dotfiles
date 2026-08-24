return {
  "barrett-ruth/live-server.nvim",
  cmd = { "LiveServerStart", "LiveServerStop" },
  init = function()
    vim.g.live_server = { port = 8080 }
  end,
}
