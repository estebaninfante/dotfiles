-- Llamada de WhatsApp: la ventanita de la llamada (la abre el PWA de Brave)
-- queda flotante, fija (pinned: visible en todos los workspaces) y con sólo el
-- video de la otra persona, en 16:9 arriba a la derecha del monitor.
--
-- Por qué acá y no sólo como regla declarativa: Chromium le pone el título a la
-- ventana un instante después de mapearla, así que una regla que matchea por
-- título no siempre llega a aplicarse. La regla de windowrules.lua cubre el caso
-- rápido; este handler escucha los eventos y la acomoda igual cuando el título
-- aparece más tarde (o cambia al entrar/salir del video).

local W, H, MARGIN, TOP = 640, 360, 24, 40

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
    local mon_w = m and math.floor(m.width / scale) or W + MARGIN * 2
    local mon_x = m and m.x or 0
    local mon_y = m and m.y or 0

    hl.dispatch(hl.dsp.window.float({ action = "set", window = addr }))
    hl.dispatch(hl.dsp.window.pin({ window = addr }))
    hl.dispatch(hl.dsp.window.resize({ window = addr, x = W, y = H, relative = false }))
    hl.dispatch(hl.dsp.window.move({
        window = addr,
        x = mon_x + mon_w - W - MARGIN,
        y = mon_y + TOP,
        relative = false,
    }))
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
