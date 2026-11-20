#!/usr/bin/env lua
-- Prueba de base/expo-tile.lua sin escritorio.
--
--   lua scripts/verify/expo-tile.lua
--
-- El caso real: ir con SUPER+<tecla> a un espacio SIN VENTANAS. La grilla de
-- hyprexpo es dinámica, así que ese espacio no tiene tile: el vuelo no aterriza,
-- el plugin no lo avisa y la grilla queda abierta a mitad del zoom del peek
-- (ventanas ~1.3x y colgando fuera de la pantalla). La decisión va antes de
-- abrir: sin tile, salto directo.

local here = (arg[0]:match("^(.*)/[^/]+$")) or "."
local candidates = {
    here .. "/../../linux/config/hypr",
    (os.getenv("HOME") or "") .. "/.config/hypr",
}
local found = nil
for _, dir in ipairs(candidates) do
    local probe = io.open(dir .. "/base/expo-tile.lua", "r")
    if probe then
        probe:close()
        found = dir
        break
    end
end
if not found then
    io.stderr:write("no encuentro base/expo-tile.lua\n")
    os.exit(1)
end
package.path = found .. "/?.lua;" .. package.path

local expo_tile = assert(require("base.expo-tile"))

local fallos = 0
local function expect(cond, nombre)
    if cond then
        print("ok   " .. nombre)
    else
        fallos = fallos + 1
        print("FALLA " .. nombre)
    end
end

expect(expo_tile.tiene_tile({}) == false,
    "espacio vacío: la grilla no tiene tile, no se vuela")
expect(expo_tile.tiene_tile({ { address = "0x1" } }) == true,
    "espacio con una ventana: hay tile, se vuela")
expect(expo_tile.tiene_tile({ { address = "0x1" }, { address = "0x2" } }) == true,
    "espacio con varias ventanas: hay tile")
expect(expo_tile.tiene_tile(nil) == true,
    "no se pudo leer la lista: no se rompe el vuelo de siempre")

print(fallos == 0 and "TODO OK" or ("FALLAS: " .. fallos))
os.exit(fallos == 0 and 0 or 1)
