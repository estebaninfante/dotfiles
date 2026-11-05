local variables = require("base.variables")

local MOONLIGHT_CLASS  = "com.moonlight_stream.Moonlight"
local MOONLIGHT_SUBMAP = "moonlight"
local MOONLIGHT_KEY    = variables.main_mod .. " + " .. variables.workspace_keys[10]
local MOONLIGHT_SPECIAL = "moonlight"

local LAN_MOUSE_CAPTURE = "lan-mouse-capture.sh"
local LAN_MOUSE_POLL_MS = 3000

local guard = false

local function grab(on)
    hl.config({ binds = { disable_keybind_grabbing = on } })
end

-- Sin daemon de lan-mouse no hay captura que soltar: el sync corre cada 3 s y
-- cada llamada al script son varios procesos. os.rename(p, p) comprueba que el
-- archivo existe sin crear ninguno. El socket queda huérfano al parar el
-- daemon, así que también se mira el flag del modo ahorro extremo (que lo para).
local LAN_MOUSE_SOCKET = (os.getenv("XDG_RUNTIME_DIR") or "") .. "/lan-mouse-socket.sock"
local POWER_EXTREME_FLAG = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
    .. "/power-extreme/on"

local lan_mouse_applied = nil

local function release_lan_mouse(on)
    -- Sin memo el timer de 3 s vuelve a llamar al script aunque el estado no
    -- cambie: lan-mouse recibía activate/deactivate repetidos (parpadeo de la
    -- captura y reconexiones).
    if lan_mouse_applied == on then
        return
    end
    if not os.rename(LAN_MOUSE_SOCKET, LAN_MOUSE_SOCKET) or os.rename(POWER_EXTREME_FLAG, POWER_EXTREME_FLAG) then
        lan_mouse_applied = nil
        return
    end
    lan_mouse_applied = on
    hl.exec_cmd(LAN_MOUSE_CAPTURE .. (on and " off" or " on"))
end

local function off()
    grab(false)
    release_lan_mouse(false)
    if hl.get_current_submap() == MOONLIGHT_SUBMAP then
        hl.dispatch(hl.dsp.submap("reset"))
    end
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
        hl.dispatch(hl.dsp.window.move({
            workspace = SPECIAL_SELECTOR,
            window = "class:" .. MOONLIGHT_CLASS,
        }))
    end
    hl.dispatch(hl.dsp.workspace.toggle_special(MOONLIGHT_SPECIAL))
    guard = false
    release_lan_mouse(true)
    grab(true)
    if hl.get_current_submap() ~= MOONLIGHT_SUBMAP then
        hl.dispatch(hl.dsp.submap(MOONLIGHT_SUBMAP))
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
    if streaming() then
        release_lan_mouse(true)
        if cur ~= MOONLIGHT_SUBMAP and not guard then
            grab(true)
            hl.dispatch(hl.dsp.submap(MOONLIGHT_SUBMAP))
        end
    else
        guard = false
        release_lan_mouse(false)
        if cur == MOONLIGHT_SUBMAP then
            off()
        elseif cur == "" or cur == "default" then
            grab(false)
        end
    end
end

hl.define_submap(MOONLIGHT_SUBMAP, function()
    hl.bind(MOONLIGHT_KEY, toggle)
end)

hl.bind(MOONLIGHT_KEY, toggle)

hl.on("window.active", sync)
hl.on("window.close", sync)
hl.on("keybinds.submap", sync)
hl.timer(function() sync() end, { timeout = 800, type = "oneshot" })
hl.timer(function() sync() end, { timeout = LAN_MOUSE_POLL_MS, type = "repeat" })

return true
