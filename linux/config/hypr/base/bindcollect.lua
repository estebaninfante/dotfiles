-- Registra los binds globales para reusarlos dentro de submaps que deben ser
-- transparentes (hoy: "dictado").
--
-- Un submap de Hyprland REEMPLAZA el mapa de atajos: cualquier bind que no esté
-- definido dentro deja de existir mientras el submap esté activo. Por eso, con
-- la transcripción activa, desaparecían los workspaces, fullscreen, mover y
-- redimensionar ventanas, etc. Acá se guarda cada bind global y
-- dictado-submap.lua los vuelve a registrar.
--
-- Se instala ANTES de que cargue cualquier archivo con binds (primer require de
-- hyprland.lua). Los binds internos de otros submaps no se guardan: mientras
-- corre el callback de define_submap, `en_submap` está en true.
local M = { globales = {} }

local bind_real   = hl.bind
local define_real = hl.define_submap
local en_submap   = false

hl.bind = function(teclas, accion, opciones)
    if not en_submap then
        M.globales[#M.globales + 1] = { teclas, accion, opciones }
    end
    if opciones ~= nil then
        return bind_real(teclas, accion, opciones)
    end
    return bind_real(teclas, accion)
end

hl.define_submap = function(nombre, cuerpo)
    return define_real(nombre, function(...)
        local previo = en_submap
        en_submap = true
        local ok, err = pcall(cuerpo, ...)
        en_submap = previo
        if not ok then
            error(err, 0)
        end
    end)
end

return M
