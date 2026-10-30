-- Submap "dictado": lo activa `omar dictate` mientras graba y lo quita al
-- terminar. Enter no debe llegar a la app: cierra la grabación, espera a que se
-- pegue todo y recién entonces presiona Enter. Sin dictado abierto, `--enter`
-- presiona Enter normal (y sale del submap), así la tecla nunca queda muerta.
--
-- Antes este submap sólo tenía Enter, Súper+I y F7. Como un submap reemplaza el
-- mapa de atajos, mientras transcribías no respondía ningún otro atajo. Ahora
-- sólo Enter se adueña: se replaysan los binds globales ya registrados por el
-- resto de la config (ver base/bindcollect.lua). Se define al final de
-- hyprland.lua para que la lista esté completa.
local binds = require("base.bindcollect")

hl.define_submap("dictado", function()
    hl.bind("RETURN", hl.dsp.exec_cmd("~/.local/bin/omar dictate --enter"))
    hl.bind("KP_Enter", hl.dsp.exec_cmd("~/.local/bin/omar dictate --enter"))

    for _, b in ipairs(binds.globales) do
        if b[3] ~= nil then
            hl.bind(b[1], b[2], b[3])
        else
            hl.bind(b[1], b[2])
        end
    end
end)
