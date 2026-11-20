-- Elegir el tile del overview (hyprexpo) y aterrizar en el workspace elegido.
--
-- El caso que rompía: `plugin:hyprexpo:dynamic_grid = 1` arma la grilla sólo con
-- los espacios que TIENEN ventanas. Si el destino está vacío no hay tile, el
-- plugin devuelve error y NO cierra la grilla. El vuelo (`fly_commit_now`) daba
-- por hecho que había cerrado: quedaba la grilla abierta a mitad del zoom del
-- `peek` (2.65), o sea las ventanas del espacio actual dibujadas ~1.3x y
-- colgando fuera de la pantalla. Se arreglaba recién al volver a abrir y cerrar
-- la grilla.
--
-- Por eso acá, si la selección no aterriza: cerrar la grilla a mano y saltar
-- derecho al workspace. `pcall` porque el fallo del plugin es un error de Lua
-- (`luaL_error`), no un valor de retorno.

local M = {}

-- `plugin`       hyprexpo (o nil si no está cargado)
-- `workspace`    id GLOBAL del workspace destino; nil = confirmar el tile enfocado
-- `focus_workspace(workspace)` cómo saltar al workspace sin el plugin
-- Devuelve true si el plugin se llevó el tile y cerró la grilla solo.
function M.commit(plugin, workspace, focus_workspace)
    if plugin == nil then
        return false
    end

    local landed
    if workspace ~= nil then
        landed = pcall(plugin.kb_selectn, workspace)
    else
        landed = pcall(plugin.kb_confirm)
    end

    if landed then
        return true
    end

    pcall(plugin.expo, "cancel")
    if workspace ~= nil and focus_workspace ~= nil then
        focus_workspace(workspace)
    end
    return false
end

return M
