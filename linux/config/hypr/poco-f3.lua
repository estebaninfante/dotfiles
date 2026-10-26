-- Poco F3 (scrcpy) como ventana propia: columna con el aspecto real del
-- teléfono (1080x2400), de alto completo del área útil (debajo de la barra) y
-- pegada al borde derecho del monitor. Sin bordes, sin redondeo, sin sombra.
--
-- Por qué acá y no sólo como regla declarativa: el alto útil depende del
-- monitor (su alto lógico menos el espacio que reserva la barra) y scrcpy
-- mapea la ventana con un tamaño propio, que además Hyprland re-acomoda
-- después del primer commit. Se calcula la geometría y se aplica varias veces
-- (eventos + timers), igual que whatsapp-call.lua.

local CLASS = "scrcpy"
local ASPECT = 1080 / 2400 -- 0.45: alto/ancho del panel del Poco F3
local BAR_FALLBACK = 24
local DEBUG = os.getenv("POCO_F3_DEBUG") == "1"

local function dbg(msg)
    if not DEBUG then return end
    hl.exec_cmd("printf '%s\\n' '" .. tostring(msg):gsub("'", "") .. "' >> /tmp/poco-f3.log")
end

-- w.monitor viene sin `scale` (no es el mismo objeto que hl.get_monitors()), así
-- que se busca el monitor real por id/nombre. Sin esto la geometría se calcula
-- en píxeles físicos y la ventana queda al doble de tamaño.
local function resolve_monitor(w)
    local ref = w and w.monitor
    local ref_id = type(ref) == "table" and (ref.id or ref.name) or ref
    for _, m in ipairs(hl.get_monitors()) do
        if ref_id ~= nil and (m.id == ref_id or m.name == ref_id) then
            return m
        end
    end
    return hl.get_active_monitor()
end

local function reserved_top(monitor)
    local r = monitor and monitor.reserved
    if type(r) == "table" and r[2] ~= nil then
        return math.floor(r[2])
    end
    return BAR_FALLBACK
end

-- x, y, ancho, alto (en píxeles lógicos) de la columna del teléfono.
local function geometry(monitor)
    if not monitor then return nil end
    local scale = (monitor.scale and monitor.scale > 0) and monitor.scale or 1
    local mon_w = math.floor(monitor.width / scale)
    local mon_h = math.floor(monitor.height / scale)
    local mon_x = monitor.x or 0
    local mon_y = monitor.y or 0

    local top = reserved_top(monitor)
    local height = mon_h - top
    local width = math.floor(height * ASPECT + 0.5)

    return mon_x + mon_w - width, mon_y + top, width, height
end

local function near(a, b) return math.abs((a or 0) - b) <= 1 end

local function fits(w, x, y, width, height)
    if not (w.floating and w.pinned and w.at and w.size) then return false end
    return near(w.at.x, x) and near(w.at.y, y) and near(w.size.x, width) and near(w.size.y, height)
end

local function place(w)
    if not (w and w.class == CLASS and w.address) then return end
    local monitor = resolve_monitor(w)
    local x, y, width, height = geometry(monitor)
    if not x then return end
    dbg(string.format("place %s floating=%s pinned=%s at=%s,%s size=%sx%s -> %d,%d %dx%d",
        w.address, tostring(w.floating), tostring(w.pinned),
        tostring(w.at and w.at.x), tostring(w.at and w.at.y),
        tostring(w.size and w.size.x), tostring(w.size and w.size.y), x, y, width, height))
    if fits(w, x, y, width, height) then return end

    local addr = "address:" .. w.address
    hl.dispatch(hl.dsp.window.float({ action = "set", window = addr }))
    hl.dispatch(hl.dsp.window.pin({ window = addr }))
    hl.dispatch(hl.dsp.window.resize({ window = addr, x = width, y = height, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = addr, x = x, y = y, relative = false }))
end

-- scrcpy re-acomoda la ventana después del primer commit: se re-aplica un par
-- de veces, como se hace con la ventanita de WhatsApp.
local function place_soon(w, delays)
    for _, ms in ipairs(delays or { 120, 500, 1200 }) do
        hl.timer(function() place(w) end, { timeout = ms, type = "oneshot" })
    end
end

local function on_window(w)
    place(w)
    place_soon(w)
end

local function place_all()
    for _, w in ipairs(hl.get_windows({ mapped = true })) do
        place(w)
        place_soon(w, { 300, 1000 })
    end
end

hl.on("window.open", on_window)
hl.on("window.class", on_window)
hl.on("window.title", on_window)
hl.on("monitor.added", place_all)
hl.on("monitor.removed", place_all)

return true
