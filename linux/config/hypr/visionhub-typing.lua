-- vision-hub: avisar de la actividad del teclado.
--
-- El evento se dispara en cada tecla; solo actualizamos la fecha de un archivo.
-- vision-hub lee ese archivo para congelar el cambio de ventana por mirada
-- mientras escribís (más un respiro al soltar, `window_focus.typing_grace_s`).
--
-- Instalar:
--   1. cp contrib/hyprland-typing.lua ~/.config/hypr/visionhub-typing.lua
--   2. agregar  require("visionhub-typing")  en ~/.config/hypr/hyprland.lua
--   3. hyprctl reload

local HOME = os.getenv("HOME")
local LAST_KEY = HOME .. "/.cache/vision-hub-typing"

hl.on("input.keyboard.key", function(_keycode, _time, state)
    if state ~= 1 then return end -- 1 = tecla presionada
    local f = io.open(LAST_KEY, "w")
    if f then
        f:write("1")
        f:close()
    end
end)
