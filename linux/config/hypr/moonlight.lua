local variables = require("base.variables")
local modes = require("base.modes")

local MOONLIGHT_CLASS  = "com.moonlight_stream.Moonlight"
local MOONLIGHT_SUBMAP = "moonlight"
local MOONLIGHT_KEY    = variables.main_mod .. " + " .. variables.workspace_keys[10]
local MOONLIGHT_SPECIAL = "moonlight"

local LAN_MOUSE_POLL_MS = 3000

local guard = false

local function grab(on)
    hl.config({ binds = { disable_keybind_grabbing = on } })
end

-- Con Moonlight abierto, lan-mouse tiene que soltar el KVM: la captura del
-- borde manda el puntero y el teclado a la otra máquina y, adentro del stream,
-- eso se realimenta: el mouse "desaparece" y no hay forma de volver. Se para el
-- daemon entero (no sólo la captura) para que no se re-arme ni por el borde ni
-- por un reinicio del servicio.
--
-- `off = true` significa "lan-mouse afuera".
local lan_mouse_applied = nil

local function set_lan_mouse(off)
    -- Memo: el sync corre cada 3 s y cada llamada son varios procesos.
    if lan_mouse_applied == off then
        return
    end
    lan_mouse_applied = off
    hl.exec_cmd("lan-mouse-streaming " .. (off and "on" or "off"))
end

local function off()
    grab(false)
    modes.streaming = false
    set_lan_mouse(false)
    if hl.get_current_submap() == MOONLIGHT_SUBMAP then
        hl.dispatch(hl.dsp.submap("reset"))
    end
end

-- Salida de emergencia. Un submap reemplaza TODO el mapa de atajos: si queda
-- armado (special visible con la ventana activa, o una transición rara), el
-- único atajo vivo es el toggle y parece que "Super dejó de andar". Esta tecla
-- fuerza la salida siempre y deja el guard puesto para que el poll de 3 s no
-- vuelva a entrar hasta que Moonlight pierda el foco.
local function force_out()
    guard = true
    off()
end

local function announce_submap()
    hl.exec_cmd("omarchy-notification-send -u critical 'Moonlight' "
        .. "'Atajos de Super bloqueados mientras streameás. Salir: SUPER+SHIFT+ESC'")
end

local SPECIAL_SELECTOR = "special:" .. MOONLIGHT_SPECIAL

local function moonlight_window()
    for _, w in ipairs(hl.get_windows({ class = MOONLIGHT_CLASS })) do
        return w
    end
    return nil
end

-- La ventana activa, no "una cualquiera de la clase": con dos instancias de
-- Moonlight abiertas, la primera podía ser la del special oculto y la segunda
-- la que tenía el foco.
local function active_moonlight()
    local w = hl.get_active_window()
    if w ~= nil and w.class == MOONLIGHT_CLASS then
        return w
    end
    return nil
end

local function in_special()
    local w = active_moonlight() or moonlight_window()
    return w ~= nil and w.workspace ~= nil and w.workspace.name == SPECIAL_SELECTOR
end

local function enter()
    if not in_special() then
        -- Por dirección, no por clase: con dos instancias abiertas, el selector
        -- por clase se llevaba las dos al special.
        local w = active_moonlight() or moonlight_window()
        if w ~= nil then
            hl.dispatch(hl.dsp.window.move({
                workspace = SPECIAL_SELECTOR,
                window = "address:" .. w.address,
            }))
        end
    end
    hl.dispatch(hl.dsp.workspace.toggle_special(MOONLIGHT_SPECIAL))
    guard = false
    -- Antes de armar el submap: navigation apaga sus gestos (esquina superior
    -- izquierda y hold de Súper) mirando este flag.
    modes.streaming = true
    if modes.close_overview then modes.close_overview() end
    set_lan_mouse(true)
    grab(true)
    if hl.get_current_submap() ~= MOONLIGHT_SUBMAP then
        hl.dispatch(hl.dsp.submap(MOONLIGHT_SUBMAP))
        announce_submap()
    end
end

local function leave()
    hl.dispatch(hl.dsp.workspace.toggle_special(MOONLIGHT_SPECIAL))
    guard = true
    off()
end

-- El submap sólo vale mientras se está streameando de verdad: la ventana
-- activa es Moonlight y vive en el special visible. Con sólo "clase enfocada"
-- se comía todos los atajos de Súper apenas el cliente quedaba en foco
-- (incluso sin conectar), y no había forma de salir sin pasar por el special.
--
-- Ojo: `monitor.active_special_workspace` llega SIEMPRE nil al Lua aunque
-- `hyprctl monitors` lo muestre, así que la visibilidad se deduce de la
-- ventana activa: sólo puede estar en el special si el special está visible.
local function streaming()
    local w = active_moonlight()
    return w ~= nil and w.workspace ~= nil and w.workspace.name == SPECIAL_SELECTOR
end

local function toggle()
    if streaming() then
        leave()
    else
        enter()
    end
end

local function sync()
    local cur = hl.get_current_submap() or ""
    modes.streaming = streaming()
    if modes.streaming then
        if cur ~= MOONLIGHT_SUBMAP and not guard then
            grab(true)
            hl.dispatch(hl.dsp.submap(MOONLIGHT_SUBMAP))
            announce_submap()
        end
    else
        guard = false
        if cur == MOONLIGHT_SUBMAP then
            off()
        elseif cur == "" or cur == "default" then
            grab(false)
        end
    end
    -- lan-mouse se decide por la VENTANA, no por el foco ni por el special: si
    -- se abre Moonlight desde el lanzador, la ventana todavía no está en el
    -- special y la captura del borde ya se estaba comiendo el puntero. Con la
    -- ventana abierta no se arma, aunque el foco vaya y venga.
    set_lan_mouse(moonlight_window() ~= nil)
end

hl.define_submap(MOONLIGHT_SUBMAP, function()
    hl.bind(MOONLIGHT_KEY, toggle)
    hl.bind(variables.main_mod .. " + SHIFT + ESCAPE", force_out,
        { description = "Moonlight: salir del submap" })
end)

hl.bind(MOONLIGHT_KEY, toggle)

hl.on("window.active", sync)
hl.on("window.close", sync)
hl.on("keybinds.submap", sync)
hl.timer(function() sync() end, { timeout = 800, type = "oneshot" })
hl.timer(function() sync() end, { timeout = LAN_MOUSE_POLL_MS, type = "repeat" })

return true
