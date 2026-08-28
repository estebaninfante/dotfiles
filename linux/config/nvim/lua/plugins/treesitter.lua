return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/nvim-treesitter/runtime")

      vim.api.nvim_create_autocmd("FileType", {
        callback = function()
          local ft = vim.bo.filetype
          if ft == "" then
            return
          end
          if not pcall(vim.treesitter.language.add, ft) then
            return
          end
          if not pcall(vim.treesitter.start) then
            return
          end
          if vim.treesitter.query.get(ft, "indents", { warn = false }) then
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