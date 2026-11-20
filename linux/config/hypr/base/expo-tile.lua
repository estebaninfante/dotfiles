-- ¿La grilla del overview tiene tile de este workspace?
--
-- Con `plugin:hyprexpo:dynamic_grid = 1` la grilla sólo arma tiles de los
-- espacios CON ventanas. Volar a un espacio vacío no aterriza y, peor, el plugin
-- NO avisa: `kb_selectn` devuelve éxito igual y no cierra la grilla. Resultado:
-- la grilla queda abierta a mitad del zoom del "peek" y las ventanas del espacio
-- actual se ven ~1.3x, colgando fuera de la pantalla, hasta que se abre y cierra
-- la grilla otra vez.
--
-- Por eso se decide ANTES de abrir: si el destino no tiene tile, no se vuela; se
-- cierra el overview y se salta derecho. Ver navigation.lua (`salto_sin_tile`).

local M = {}

-- `windows`: lo que devuelve hl.get_workspace_windows(<id>).
-- nil = no se pudo leer, se deja el vuelo como siempre.
function M.tiene_tile(windows)
    if windows == nil then return true end
    for _, window in ipairs(windows) do
        if window ~= nil then return true end
    end
    return false
end

return M
