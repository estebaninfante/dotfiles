return {
  "epwalsh/obsidian.nvim",
  version = "*",
  ft = "markdown",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "hrsh7th/nvim-cmp",
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    workspaces = {
      { name = "alicia", path = "~/alicia" },
    },

    -- ── Notas nuevas ─────────────────────────────────────────────
    -- Crear nota donde estoy (misma carpeta que la nota actual)
    new_note_location = "current",
    -- Abrir notas en esta instancia de neovim (no otra ventana)
    open_notes_in = "current",
    -- Nombre de nota = titulo tal cual (sin IDs numericos)
    note_id_func = function(title)
      return title
    end,

    -- ── Daily notes ──────────────────────────────────────────────
    daily_notes = {
      folder = "daily",
      date_format = "%Y-%m-%d",
      template = nil,
    },

    -- ── Completion / enlaces ─────────────────────────────────────
    completion = {
      min_chars = 1,          -- autocomplete con 1 char (rapido)
      nvim_cmp = true,        -- integra con nvim-cmp
    },

    -- Formato de links wiki: [[note]] o [[note|alias]]
    wiki_link_func = function(opts)
      local result = "[[" .. opts.label .. "]]"
      if opts.path ~= nil then
        result = "[[" .. opts.label .. "|" .. opts.path:match("([^/]+)$") .. "]]"
      end
      return result
    end,

    -- ── Pegar imagenes ──────────────────────────────────────────
    images_folder = "assets",

    -- ── Follow links ────────────────────────────────────────────
    follow_url_func = function(url)
      vim.fn.jobstart({ "xdg-open", url })
    end,

    -- ── Picker (telescope) ──────────────────────────────────────
    picker = {
      name = "telescope",
      mappings = {
        new = "<C-x>",        -- crear nota nueva desde picker
        insert_link = "<C-l>", -- insertar link en buffer actual
      },
    },

    -- ── UI (checkboxes, etc) ────────────────────────────────────
    ui = {
      enable = true,
      tick = "│",
      checkboxes = {
        [" "] = { char = "", hl_group = "ObsidianTodo" },
        ["x"] = { char = "", hl_group = "ObsidianDone" },
        ["~"] = { char = "", hl_group = "ObsidianTilde" },
        ["!"] = { char = "", hl_group = "ObsidianImportant" },
      },
    },

    -- ── Templates ───────────────────────────────────────────────
    templates = {
      subdir = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
    },

    -- ── Sin frontmatter automatico ──────────────────────────────
    disable_frontmatter = true,
  },

  keys = {
    -- Buscar / abrir nota
    { "<leader>of", "<cmd>ObsidianQuickSwitch<cr>", desc = "Obsidian: buscar nota" },
    { "<leader>og", "<cmd>ObsidianSearch<cr>", desc = "Obsidian: grep en vault" },

    -- Crear nota
    { "<leader>on", "<cmd>ObsidianNew<cr>", desc = "Obsidian: nota nueva" },
    { "<leader>od", "<cmd>ObsidianDaily<cr>", desc = "Obsidian: nota diaria" },

    -- Enlaces (lo mas importante)
    { "<leader>ol", "<cmd>ObsidianLinks<cr>", desc = "Obsidian: links en nota" },
    { "<leader>ob", "<cmd>ObsidianBacklinks<cr>", desc = "Obsidian: backlinks" },
    { "<leader>oA", "<cmd>ObsidianAppendLink<cr>", desc = "Obsidian: agregar link" },
    { "gd", "<cmd>ObsidianFollowLink<cr>", desc = "Seguir link [[...]]" },

    -- Tags (conexion de conceptos)
    { "<leader>ot", "<cmd>ObsidianTags<cr>", desc = "Obsidian: buscar tags" },

    -- Pegar imagen (ctrl+v en insert tambien funciona)
    { "<leader>op", "<cmd>ObsidianPasteImg<cr>", desc = "Obsidian: pegar imagen" },

    -- Templates
    { "<leader>oT", "<cmd>ObsidianTemplate<cr>", desc = "Obsidian: insertar template" },

    -- Workspace
    { "<leader>os", "<cmd>ObsidianWorkspace<cr>", desc = "Obsidian: cambiar workspace" },

    -- Toggle checkbox (atajo extra rapido)
    { "<leader>x", function()
      local line = vim.api.nvim_get_current_line()
      local new = line:gsub("%[ %]", "[x]"):gsub("%[x%]", "[ ]"):gsub("%[~%]", "[ ]")
      vim.api.nvim_set_current_line(new)
    end, desc = "Toggle checkbox", mode = "n" },
  },
}
