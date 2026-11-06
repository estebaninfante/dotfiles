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
local function set_lan_mouse(off)
    -- Sin memo: el script es idempotente, y el daemon
    -- sunshine-lan-mouse-guard (o un reinicio de lan-mouse) puede cambiar el
    -- estado por fuera. Con memo la decisión local se quedaba obsoleta y la
    -- captura seguía armada en mitad de un stream.
    hl.exec_cmd("lan-mouse-capture.sh " .. (off and "off" or "on"))
end

local function off()
    grab(false)
    modes.streaming = false
    -- lan-mouse lo decide sync (por ventana abierta), no este teardown: si los
    -- dos escriben, se activa y desactiva la captura en el mismo tick.
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
    -- Sólo se oculta el special si el stream estaba ahí: streameando en un
    -- workspace normal, togglear lo mostraría (justo al revés).
    local w = active_moonlight()
    if w ~= nil and w.workspace ~= nil and w.workspace.name == SPECIAL_SELECTOR then
        hl.dispatch(hl.dsp.workspace.toggle_special(MOONLIGHT_SPECIAL))
    end
    guard = true
    off()
end

-- ¿Hay un stream vivo? El título "<equipo> - Moonlight" se queda pegado
-- cuando la conexión se cae: Moonlight sigue en pantalla completa mostrando
-- el último frame. Si se decide por título, el submap y la captura de
-- lan-mouse se quedan armados para siempre. La señal buena es el canal de
-- control de Sunshine (moonlight-live mira los puertos 47984/47989/48010).
--
-- Por io.popen y no os.execute: dentro de Hyprland os.execute devuelve nil
-- siempre (no recupera el estado del hijo), así que el modo streaming no se
-- armaba nunca. El código de salida se lee como texto.
local function moonlight_live()
    local p = io.popen(os.getenv("HOME") .. "/.local/bin/moonlight-live >/dev/null 2>&1; echo $?")
    if not p then return false end
    local rc = p:read("*l")
    p:close()
    return rc == "0"
end

-- El submap vale mientras el stream esté en foco y vivo. Con la sola clase
-- enfocada se comía todos los atajos de Súper apenas el cliente quedaba en
-- foco, incluso sin conectar.
--
-- Ojo: `monitor.active_special_workspace` llega SIEMPRE nil al Lua aunque
-- `hyprctl monitors` lo muestre, así que la visibilidad se deduce de la
-- ventana activa: sólo puede estar en el special si el special está visible.
local function streaming()
    return active_moonlight() ~= nil and moonlight_live()
end

local function toggle()
    if streaming() then
        leave()
    else
        enter()
    end
end

-- Si el stream murió con Moonlight en pantalla completa, la ventana se queda
-- con el último frame y el puntero relativo: el ratón deja de responder aunque
-- el resto del escritorio esté bien. Se sale de fullscreen (sin cerrar nada)
-- en la transición vivo -> muerto para devolver el puntero.
local function release_stale_fullscreen()
    for _, w in ipairs(hl.get_windows({ class = MOONLIGHT_CLASS })) do
        if (w.fullscreen or 0) > 0 and w.title ~= nil and w.title:find("%- Moonlight$") then
            hl.dispatch(hl.dsp.window.fullscreen({
                action = "unset",
                window = "address:" .. w.address,
            }))
        end
    end
end

local was_live = false
local last_lan_off = nil

local function sync()
    local cur = hl.get_current_submap() or ""
    local live = moonlight_live()
    modes.streaming = active_moonlight() ~= nil and live
    if was_live and not live then
        release_stale_fullscreen()
    end
    was_live = live
    if modes.streaming then
        if cur ~= MOONLIGHT_SUBMAP and not guard then
            grab(true)
            if modes.close_overview then modes.close_overview() end
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
    -- lan-mouse se decide por el stream vivo, no por el título de la ventana:
    -- el título queda pegado cuando se cae la conexión. Sólo se toca en los
    -- cambios: el guion cuesta ~250 ms y el poll es cada 3 s. El guard
    -- reconcilia el estado real cada 30 s como red de seguridad.
    if last_lan_off == nil or last_lan_off ~= live then
        set_lan_mouse(live)
        last_lan_off = live
    end
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
