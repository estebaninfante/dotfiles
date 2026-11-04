-- hyprbars: barra de título arriba de CADA ventana, con botón de cerrar. Es la
-- forma de cerrar ventanas desde un cliente táctil (Moonlight en el celular),
-- donde no hay SUPER+Q.
--
-- Se carga fuera de proceso: hl.plugin.load() desde Lua reentra el parser y
-- desborda la pila antes de que arranque la sesión (ver plugins/hyprexpo.lua).
hl.exec_cmd((os.getenv("HOME") or "") .. "/.local/bin/hyprbars-load.sh")

-- 26 px de alto y texto de 12: el default (12 px) deja el ✕ del tamaño de un
-- pixel en un stream de 1920 de ancho, imposible de tocar desde el celular.
-- Solo aplica a ventanas nuevas; las que ya están abiertas la toman al
-- remapearse o al reiniciar la sesión.
hl.config({
    plugin = {
        hyprbars = {
            bar_height = 26,
            bar_text_size = 12,
            bar_padding = 10,
            bar_button_padding = 4,
        },
    },
})

return true
