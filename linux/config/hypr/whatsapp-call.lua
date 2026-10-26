-- Llamada de WhatsApp: la ventanita de la llamada (la abre el PWA de Brave)
-- queda flotante, fija (pinned: visible en todos los workspaces) y arriba a la
-- derecha del monitor.
--
-- Por qué acá y no sólo como regla declarativa: Chromium le pone el título a la
-- ventana un instante después de mapearla, así que una regla que matchea por
-- título no siempre llega a aplicarse. La regla de windowrules.lua cubre el caso
-- rápido; este handler escucha los eventos y la acomoda igual cuando el título
-- aparece más tarde (o cambia al entrar/salir del video).
--
-- El tamaño fino lo hace ~/.local/bin/whatsapp-call-fit: captura la ventana,
-- mide el rectángulo de video real (WhatsApp mete franjas negras cuando el
-- aspecto de la ventana no coincide con la cámara del otro lado) y la
-- redimensiona a ese aspecto, así se ve sólo la persona y no el rectángulo.
-- Se dispara un par de veces porque el video del otro lado tarda en conectar
-- y cambia el aspecto cuando aparece.

local W, H = 360, 520 -- arranque en 9:16; el fit lo corrige al aspecto real

local function is_call(w)
    if not w or not w.class or not w.title then return false end
    if not w.class:lower():find("whatsapp", 1, true) then return false end
    return w.title:match("[Ll]lamada de WhatsApp$") ~= nil
end

local function place(w)
    if not is_call(w) then return end
    if w.floating and w.pinned then return end

    local addr = "address:" .. w.address
    local m = w.monitor or hl.get_active_monitor()
    local scale = (m and m.scale and m.scale > 0) and m.scale or 1
    local mon_w = m and math.floor(m.width / scale) or W + 48
    local mon_x = m and m.x or 0
    local mon_y = m and m.y or 0

    hl.dispatch(hl.dsp.window.float({ action = "set", window = addr }))
    hl.dispatch(hl.dsp.window.pin({ window = addr }))
    hl.dispatch(hl.dsp.window.resize({ window = addr, x = W, y = H, relative = false }))
    hl.dispatch(hl.dsp.window.move({
        window = addr,
        x = mon_x + mon_w - W - 24,
        y = mon_y + 40,
        relative = false,
    }))

    local fit = function() hl.exec_cmd("~/.local/bin/whatsapp-call-fit") end
    hl.timer(fit, { timeout = 2500, type = "oneshot" })
    hl.timer(fit, { timeout = 7000, type = "oneshot" })
end

local function on_window(w)
    -- `window.open` puede llegar antes de que el cliente tenga título/clase
    -- definitivos; en ese caso no hacemos nada y esperamos al evento de título.
    place(w)
end

hl.on("window.open", on_window)
hl.on("window.title", on_window)
hl.on("window.class", on_window)

return true
