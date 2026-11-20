#!/usr/bin/env lua
-- Prueba de base/expo-commit.lua sin escritorio: plugin de mentira.
--
--   lua scripts/verify/expo-commit.lua
--
-- Los tres casos que importan:
--   1. el destino tiene tile  -> lo elige el plugin, no hay que cerrar a mano;
--   2. el destino está vacío  -> el plugin falla (luaL_error) y hay que cerrar
--      la grilla y saltar derecho (si no, queda el zoom del peek pegado);
--   3. sin tile enfocado (confirm) y el plugin falla -> se cierra igual.

local here = (arg[0]:match("^(.*)/[^/]+$")) or "."
local candidates = {
    here .. "/../../linux/config/hypr",
    (os.getenv("HOME") or "") .. "/.config/hypr",
}
local found = nil
for _, dir in ipairs(candidates) do
    local probe = io.open(dir .. "/base/expo-commit.lua", "r")
    if probe then
        probe:close()
        found = dir
        break
    end
end
if not found then
    io.stderr:write("no encuentro base/expo-commit.lua\n")
    os.exit(1)
end
package.path = found .. "/?.lua;" .. package.path

local expo_commit = assert(require("base.expo-commit"))

local fallos = 0

local function expect(cond, nombre)
    if cond then
        print("ok   " .. nombre)
    else
        fallos = fallos + 1
        print("FALLA " .. nombre)
    end
end

-- Plugin de mentira: registra qué le pidieron.
local function plugin(destino)
    local log = { cancel = 0, selects = {} }
    local p = {
        kb_selectn = function(id)
            table.insert(log.selects, id)
            if destino == "vacio" then
                -- El plugin real hace luaL_error cuando no hay tile.
                error("hyprexpo.kb_selectn: dispatcher failed", 0)
            end
        end,
        kb_confirm = function()
            if destino == "vacio" then
                error("hyprexpo.kb_confirm: dispatcher failed", 0)
            end
        end,
        expo = function(arg) log.cancel = log.cancel + (arg == "cancel" and 1 or 0) end,
    }
    return p, log
end

do -- 1. el workspace destino tiene tile
    local p, log = plugin("ok")
    local enfocados = {}
    local landed = expo_commit.commit(p, 7, function(ws) table.insert(enfocados, ws) end)
    expect(landed == true, "con tile: aterriza el plugin")
    expect(#log.selects == 1 and log.selects[1] == 7, "con tile: pide el workspace 7")
    expect(log.cancel == 0, "con tile: no cierra la grilla a mano")
    expect(#enfocados == 0, "con tile: no salta por atrás")
end

do -- 2. el workspace está vacío (no hay tile -> el plugin falla)
    local p, log = plugin("vacio")
    local enfocados = {}
    local landed = expo_commit.commit(p, 7, function(ws) table.insert(enfocados, ws) end)
    expect(landed == false, "vacío: no aterriza el plugin")
    expect(#log.selects == 1 and log.selects[1] == 7, "vacío: igual intenta el 7")
    expect(log.cancel == 1, "vacío: cierra la grilla a mano (el zoom no queda pegado)")
    expect(#enfocados == 1 and enfocados[1] == 7, "vacío: salta derecho al 7")
end

do -- 3. confirmar sin destino y el plugin falla
    local p, log = plugin("vacio")
    local enfocados = {}
    local landed = expo_commit.commit(p, nil, function(ws) table.insert(enfocados, ws) end)
    expect(landed == false, "confirm falla: devuelve false")
    expect(log.cancel == 1, "confirm falla: cierra la grilla")
    expect(#enfocados == 0, "confirm falla: no inventa workspace")
end

do -- 4. sin plugin (no cargado) no rompe ni cierra nada
    local landed = expo_commit.commit(nil, 7, function() error("no debería saltar") end)
    expect(landed == false, "sin plugin: devuelve false sin explotar")
end

print(fallos == 0 and "TODO OK" or ("FALLAS: " .. fallos))
os.exit(fallos == 0 and 0 or 1)
