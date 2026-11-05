-- Estado que comparten módulos que no deben encadenarse por require
-- (navigation define gestos, moonlight los tiene que apagar mientras streamea).
--
-- navigation.lua carga antes que moonlight.lua, así que el hook se publica acá
-- y moonlight lo llama al entrar en modo streaming.
local M = {
    -- true mientras Moonlight ocupa el special visible: los gestos locales
    -- (esquina superior izquierda, hold de Súper) se apagan y los atajos van
    -- enteros a la máquina remota.
    streaming = false,

    -- Lo completa navigation.lua: cierra el overview si quedó abierto.
    close_overview = nil,
}

return M
