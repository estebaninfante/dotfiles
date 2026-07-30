vim.g.mapleader = " "

-- Sincronizar el portapapeles de Neovim con el del sistema operativo
vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.termguicolors = true
vim.opt.wrap = false
vim.keymap.set("i", "kk", "<Esc>")
-- ==========================================
-- Navegación Dvorak Home Row (h t n s)
-- h = Izquierda | t = Abajo | n = Arriba | s = Derecha
-- ==========================================
vim.keymap.set({ "n", "v" }, "h", "h", { desc = "Mover a la izquierda" })
vim.keymap.set({ "n", "v" }, "t", "j", { desc = "Mover abajo" })
vim.keymap.set({ "n", "v" }, "n", "k", { desc = "Mover arriba" })
vim.keymap.set({ "n", "v" }, "s", "l", { desc = "Mover a la derecha" })

-- Remapear comandos originales de t, n, s a j, k, l si es necesario
vim.keymap.set({ "n", "v" }, "j", "t", { desc = "Hasta el carácter (remap de t)" })
vim.keymap.set({ "n", "v" }, "k", "n", { desc = "Siguiente búsqueda (remap de n)" })
vim.keymap.set({ "n", "v" }, "l", "s", { desc = "Sustituir carácter (remap de s)" })

-- Navegación fluida entre paneles / ventanas (Splits) con Ctrl + htns
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Mover a panel izquierdo" })
vim.keymap.set("n", "<C-t>", "<C-w>j", { desc = "Mover a panel inferior" })
vim.keymap.set("n", "<C-n>", "<C-w>k", { desc = "Mover a panel superior" })
vim.keymap.set("n", "<C-s>", "<C-w>l", { desc = "Mover a panel derecho" })

-- Navegación entre Buffers (Pestañas abiertas)
vim.keymap.set("n", "<S-h>", ":bprevious<cr>", { desc = "Buffer anterior" })
vim.keymap.set("n", "<S-s>", ":bnext<cr>", { desc = "Siguiente buffer" })
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

-- Búsqueda y Navegación (Telescope / LSP / Proyectos)
vim.keymap.set("n", "<leader>p", "<cmd>Telescope projects<cr>", { desc = "Abrir proyectos (.git)" })
vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Buscar archivos" })
vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Buscar texto (grep)" })
vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Ir a definición" })
vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Ver documentación (hover)" })
