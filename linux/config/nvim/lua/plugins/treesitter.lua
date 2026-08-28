return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")

      pcall(ts.install, {
        "html",
        "css",
        "javascript",
        "typescript",
        "tsx",
        "json",
        "lua",
        "python",
        "qmljs",
      })

      vim.api.nvim_create_autocmd("FileType", {
        callback = function()
          local ft = vim.bo.filetype
          if ft == "" then
            return
          end
          if not pcall(vim.treesitter.language.add, ft) then
            return
          end
          if vim.treesitter.query.get("indents", ft, { warn = false }) then
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            vim.bo.indentkeys = vim.bo.indentkeys .. ",=end"
          end
        end,
      })
    end,
  },
  {
    "windwp/nvim-ts-autotag",
    opts = {},
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },
}