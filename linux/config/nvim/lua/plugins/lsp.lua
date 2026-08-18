return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/nvim-cmp",
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "L3MON4D3/LuaSnip",
    "saadparwaiz1/cmp_luasnip",
  },
  config = function()
    require("mason").setup()
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    vim.lsp.config("*", { capabilities = capabilities })

    require("mason-lspconfig").setup({
      ensure_installed = {
        "html",
        "cssls",
        "ts_ls",
        "tailwindcss",
        "emmet_ls",
        "pyright",
        "ruff",
        "jsonls",
      },
    })

    -- qmlls (QML): binario de qtdeclarative (paquete de sistema), no mason
    vim.lsp.config("qmlls", {
      cmd = { "qmlls" },
      on_attach = function(client, bufnr)
        -- qmlls 6.11 manda semantic tokens invalidos -> nvim 0.12.4 crashea
        vim.lsp.semantic_tokens.enable(false, { client_id = client.id, bufnr = bufnr })
      end,
    })
    vim.lsp.enable("qmlls")

    local cmp = require("cmp")
    cmp.setup({
      snippet = {
        expand = function(args)
          require("luasnip").lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<CR>"] = cmp.mapping.confirm({ select = true }),
        ["<Tab>"] = cmp.mapping.select_next_item(),
        ["<S-Tab>"] = cmp.mapping.select_prev_item(),
      }),
      sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "path" },
      }),
    })
  end,
}