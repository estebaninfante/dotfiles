return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown", "markdown.mdx", "quarto", "rmd" },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    -- Conceal level: 2 oculta syntax markdown, 3 oculta todo
    concealcursor = "nc",
    -- Heading icons
    heading = {
      enabled = true,
      sign = true,
      icons = { "", "", "", "", "", "" },
      -- Show background behind heading
      backgrounds = {
        "RenderMarkdownH1Bg",
        "RenderMarkdownH2Bg",
        "RenderMarkdownH3Bg",
        "RenderMarkdownH4Bg",
        "RenderMarkdownH5Bg",
        "RenderMarkdownH6Bg",
      },
      position = "inline",
      width = "full",
    },
    -- Code blocks
    code = {
      enabled = true,
      sign = true,
      style = "full",
      left_margin = 0,
      left_pad = 0,
      right_pad = 0,
      min_width = 0,
      border = "none",
      language_pad = 0,
      language_icon = true,
      language_name = true,
      hider_repeat = true,
      highlight_gobble = true,
    },
    -- Dash (---)
    dash = {
      enabled = true,
      icon = "──────────────────────────────────────────────────────",
      width = "full",
    },
    -- Bullet lists
    bullet = {
      enabled = true,
      icons = { "", "", "", "" },
      left_margin = 0,
      highlight = "RenderMarkdownBullet",
    },
    -- Checkbox / task lists
    checkbox = {
      enabled = true,
      unchecked = { icon = "󰄱 " },
      checked = { icon = "󰱒 " },
      custom = {
        todo = { raw = "[~]", rendered = "󰥔 ", highlight = "RenderMarkdownTodo" },
        important = { raw = "[!]", rendered = " ", highlight = "RenderMarkdownImportant" },
        question = { raw = "[?]", rendered = " ", highlight = "RenderMarkdownQuestion" },
      },
    },
    -- Quote blocks
    quote = {
      enabled = true,
      icon = "│",
      repeat_linebreak = false,
      highlight = "RenderMarkdownQuote",
    },
    -- Link
    link = {
      enabled = true,
      image = "󰥔 ",
      link = "󰌷 ",
      footnote = "¹",
      web_link = "󰌹 ",
      highlight = "RenderMarkdownLink",
      custom = {
        web_link = { pattern = "^https?://", icon = "󰌹 ", highlight = "RenderMarkdownLink" },
      },
    },
    -- Table
    table = {
      enabled = true,
      sign = true,
      style = "full",
    },
    -- Callout boxes (Obsidian-style)
    callout = {
      enabled = true,
      icons = {
        note = "",
        tip = "",
        important = "",
        warning = "",
        caution = "",
      },
      language = {
        note = { raw = "[!note]", rendered = "󰋽 Note", highlight = "RenderMarkdownNote" },
        tip = { raw = "[!tip]", rendered = "󰌶 Tip", highlight = "RenderMarkdownTip" },
        important = { raw = "[!important]", rendered = "", highlight = "RenderMarkdownImportant" },
        warning = { raw = "[!warning]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarning" },
        caution = { raw = "[!caution]", rendered = "󰳦 Caution", highlight = "RenderMarkdownCaution" },
      },
    },
    -- Winblend for floating windows
    win_options = {
      conceallevel = { default = 2, rendered = 3 },
      concealcursor = { default = "nc", rendered = "nc" },
    },
  },
  config = function(_, opts)
    require("render-markdown").setup(opts)
    -- Sync with Kitty theme
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        require("render-markdown").setup(opts)
      end,
    })
  end,
}
