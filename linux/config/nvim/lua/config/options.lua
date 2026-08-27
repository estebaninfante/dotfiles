-- Opciones de legibilidad / fatiga visual
-- (miopía + astigmatismo: sin itálicas, contraste suave, contexto visible)
local o = vim.opt

o.number = true -- línea absoluta actual como ancla
o.relativenumber = false -- números relativos cansan al leer
o.cursorline = true -- sigue la línea activa
o.scrolloff = 10 -- contexto arriba/abajo al hacer scroll
o.sidescrolloff = 8

-- Sin itálicas (el astigmatismo distorsiona los glifos inclinados)
vim.cmd([[
  hi Comment gui=NONE cterm=NONE
]])

o.wrap = false
o.linebreak = true
o.signcolumn = "yes" -- evita saltos de layout con diagnostics
o.cmdheight = 1
o.pumheight = 12 -- popup menú compacto

o.list = true
o.listchars = { tab = "→ ", trail = "·", nbsp = "␣" }

o.ignorecase = true
o.smartcase = true
