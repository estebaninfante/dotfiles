vim.g.mapleader = " "

-- Sincronizar el portapapeles de Neovim con el del sistema operativo
vim.opt.clipboard = "unnamedplus"
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
vim.opt.termguicolors = true
vim.opt.wrap = false
vim.opt.scrolloff = 999

-- Dos columnas de números: absoluta + relativa
vim.api.nvim_set_hl(0, "StatusColAbs", { bold = false, fg = "#808080" })
vim.api.nvim_set_hl(0, "StatusColRel", { bold = false, fg = "#50C878" })

function _G.StatusColNumbers()
  local lnum = vim.v.lnum
  local rel = vim.v.relnum
  if rel == 0 then
    return string.format("%%#StatusColRel#%3d%%* %%#StatusColAbs#%3d │ %%*", 0, lnum)
  end
  return string.format("%%#StatusColAbs#%3d%%* %%#StatusColRel#%3d │ %%*", lnum, rel)
end

vim.o.statuscolumn = "%!v:lua.StatusColNumbers()"
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.keymap.set("i", "uu", "<Esc>")
vim.keymap.set("i", "\x1b[127;5~", "<C-w>", { desc = "Borrar palabra (ctrl+backspace)" })
vim.keymap.set("n", "ñ", "o<Esc>", { desc = "Línea vacía abajo" })

-- Enter: mantener columna actual (no ir a inicio de línea)
vim.keymap.set("i", "<CR>", function()
  local col = vim.fn.col(".")
  return "<CR><C-o>" .. col .. "|"
end, { expr = true, desc = "Enter manteniendo columna" })

-- Tab unificado: cmp menu → luasnip jump → minuet accept → indent previo
vim.keymap.set("i", "<Tab>", function()
  local cmp_ok, cmp = pcall(require, "cmp")
  if cmp_ok and cmp.visible() then
    vim.schedule(function() cmp.select_next_item() end)
    return ""
  end
  local ls_ok, ls = pcall(require, "luasnip")
  if ls_ok and ls.expand_or_jumpable() then
    ls.expand_or_jump()
    return ""
  end
  local minuet_ok, minuet_vt = pcall(require, "minuet.virtualtext")
  if minuet_ok and minuet_vt.action and minuet_vt.action.is_visible and minuet_vt.action.is_visible() then
    minuet_vt.action.accept()
    return ""
  end
  local prev = vim.fn.indent(vim.fn.line(".") - 1)
  if prev > 0 then
    return "<C-o>" .. prev .. "|"
  end
  return "<Tab>"
end, { expr = true, desc = "Tab unificado (cmp/luasnip/minuet/indent)" })
-- S-Tab unificado: cmp menu → luasnip jump prev → nothing → nothing
vim.keymap.set("i", "<S-Tab>", function()
  local cmp_ok, cmp = pcall(require, "cmp")
  if cmp_ok and cmp.visible() then
    cmp.select_prev_item()
    return ""
  end
  local ls_ok, ls = pcall(require, "luasnip")
  if ls_ok and ls.jumpable(-1) then
    ls.jump(-1)
    return ""
  end
  return "<S-Tab>"
end, { expr = true, desc = "S-Tab unificado (cmp/luasnip)" })
-- Navegación fluida entre paneles / ventanas (Splits) con Ctrl + hjkl
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Mover a panel izquierdo" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Mover a panel inferior" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Mover a panel superior" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Mover a panel derecho" })

-- Navegación entre Buffers (Pestañas abiertas)
vim.keymap.set("n", "<S-h>", ":bprevious<cr>", { desc = "Buffer anterior" })
vim.keymap.set("n", "<S-l>", ":bnext<cr>", { desc = "Siguiente buffer" })
vim.keymap.set("n", "<leader>bd", ":bdelete<cr>", { desc = "Cerrar buffer" })

-- Guardado rápido
vim.keymap.set("n", "<leader>w", ":w<cr>", { desc = "Guardar archivo" })
vim.keymap.set("n", "<leader>s", ":w<cr>", { desc = "Guardar archivo" })

-- Dashboard
vim.keymap.set("n", "<leader>h", "<cmd>Dashboard<cr>", { desc = "Abrir dashboard" })

-- Espacio en insert mode: sin delay de leader
vim.keymap.set("i", "<space>", "<space>", { nowait = true })

-- Copiar / Pegar / Cortar
vim.keymap.set({ "n", "v" }, "<C-c>", "y", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<C-v>", "p", { noremap = true, silent = true })
vim.keymap.set("i", "<C-v>", "<C-r>+", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<C-x>", "d", { noremap = true, silent = true })

-- File Explorer
vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file explorer" })

-- Búsqueda y Navegación (Telescope / LSP / Proyectos)
vim.keymap.set("n", "<leader>p", "<cmd>Telescope projects<cr>", { desc = "Abrir proyectos (.git)" })
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Buscar archivos" })
vim.keymap.set("n", "<leader>ft", "<cmd>Telescope live_grep<cr>", { desc = "Buscar texto (grep)" })
vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Ir a definición" })
vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Ver documentación (hover)" })

-- Live Server (preview web con recarga en navegador)
vim.keymap.set("n", "<leader>lo", "<cmd>LiveServerStart<cr>", { desc = "Live server: iniciar" })
vim.keymap.set("n", "<leader>lx", "<cmd>LiveServerStop<cr>", { desc = "Live server: detener" })

-- Auto-guardado
vim.keymap.set("n", "<leader>ua", "<cmd>ASToggle<cr>", { desc = "Toggle auto-guardado" })

-- Repetir último . en N líneas hacia abajo (ej: 5<leader>. repite 5 veces)
vim.keymap.set("n", "<leader>.", function()
  local count = vim.v.count1
  for _ = 1, count do
    vim.cmd("normal! .j")
  end
end, { desc = "Repetir último . en N líneas" })
