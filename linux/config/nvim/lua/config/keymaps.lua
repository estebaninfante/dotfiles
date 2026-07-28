vim.g.mapleader = " "

-- Navegación con Kitty Navigator
vim.keymap.set("n", "<C-h>", ":KittyNavigateLeft<cr>")
vim.keymap.set("n", "<C-j>", ":KittyNavigateDown<cr>")
vim.keymap.set("n", "<C-k>", ":KittyNavigateUp<cr>")
vim.keymap.set("n", "<C-l>", ":KittyNavigateRight<cr>")

-- Atajo para guardar rápido
vim.keymap.set("n", "<leader>w", ":w<CR>")
