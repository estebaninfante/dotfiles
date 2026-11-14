local variables = require("base.variables")
local power = require("base.power")
local spaces = require("base.workspaces")

-- Los nombres de salida van en variables a propósito (no como texto literal en
-- las reglas). omarchy-hyprland-monitor-clamshell busca el PRIMER
-- `hl.monitor({ output = "eDP-2" ... scale = N` del archivo y ese N pasa a ser la
-- escala "configurada" del panel interno: si la actual no coincide, la reaplica.
-- Como acá hay dos ramas, con nombres literales leía la de HDMI (escala 1) y en
-- cada wake (al cerrar el screensaver o al volver de suspensión) mandaba el panel
-- a escala 1: todo se achicaba hasta que un reload lo devolvía a 2. Sin regla
-- literal que leer, ese script deja la escala en manos de Hyprland, que es la
-- única que manda acá.
local internal = "eDP-2"

-- Colgada de la laptop, la vertical (ASUS 4K) va a escala 2: 3840x2160 con
-- transform 3 = 1080x1920 lógicos, la misma densidad que el panel interno. Es
-- la disposición con la que se calibró la visión por mirada (vision-hub) el
-- 2026-11-13; antes era 1.25 como en el desktop (ver la rama desktop).
local EXTERNAL_SCALE = 2
-- Cuánto más arriba que la laptop empieza la vertical (px lógicos): la laptop
-- en 0x0 y la vertical a su izquierda en -1080x-1086.
local EXTERNAL_OFFSET_Y = 1086
local EXTERNAL_DEFAULT_TRANSFORM = 3
local INTERNAL_MODE = "2880x1800"

-- ¿Qué monitor es la vertical? Cualquiera que no sea el panel interno ni una
-- salida virtual (Sunshine crea HEADLESS-N para streamear; `pantalla-agente`
-- monta AGENTE-N para pruebas). Se pregunta a Hyprland en vez de asumir un
-- puerto: da igual si entra por HDMI o por USB-C/DP, y al arrancar no se cree
-- "conectado" un monitor que todavía no está.
local function external_monitor()
    for _, monitor in ipairs(hl.get_monitors()) do
        if monitor.name ~= internal
            and not monitor.name:match("^HEADLESS")
            and not monitor.name:match("^AGENTE") then
            return monitor
        end
    end
    return nil
end

-- Mejor modo del monitor: resolución nativa (la de mayor área) y, dentro de eso,
-- el refresh más alto que no pase el tope (144 con corriente, 60 con batería).
-- Así la vertical queda a 144 Hz igual que en el desktop, y si el puerto no
-- banca ese modo cae al más rápido que sí exista.
local function best_mode(monitor, cap)
    local modes = monitor.available_modes or {}
    local native_area = 0
    for _, md in ipairs(modes) do
        if md.width * md.height > native_area then native_area = md.width * md.height end
    end
    local within, fastest
    for _, md in ipairs(modes) do
        if md.width * md.height == native_area then
            if md.refresh_rate <= cap and (within == nil or md.refresh_rate > within.refresh_rate) then
                within = md
            end
            if fastest == nil or md.refresh_rate > fastest.refresh_rate then fastest = md end
        end
    end
    local chosen = within or fastest
    if not chosen then return nil end
    return string.format("%dx%d@%.2f", chosen.width, chosen.height, chosen.refresh_rate)
end

-- Adelantada: la usa apply_laptop_monitors, que está definida antes.
local apply_orientation_layout
local saved_transform

-- Cada pantalla es dueña de su juego de espacios: 1..9 la interna, 28..36 la
-- vertical (ver base/workspaces.lua). Sin estas reglas Hyprland reparte los
-- espacios como quiere al arrancar o al reconectar la vertical: la vertical
-- terminaba mostrando el espacio 1 de la laptop y los atajos cambiaban de set a
-- mitad de camino. `default` fija además el espacio inicial de cada pantalla.
local bound_external
local function bind_workspace_sets(external_name)
    if bound_external == (external_name or false) then return end
    bound_external = external_name or false
    for index = 1, spaces.SET_SIZE do
        hl.workspace_rule({
            workspace = tostring(spaces.PRIMARY_BASE + index - 1),
            monitor = internal,
            default = index == 1,
        })
    end
    if external_name then
        for index = 1, spaces.SET_SIZE do
            hl.workspace_rule({
                workspace = tostring(spaces.EXTERNAL_BASE + index - 1),
                monitor = external_name,
                default = index == 1,
            })
        end
    end
end

local function apply_laptop_monitors()
    local refresh = power.low_power() and 60 or 120
    local external = external_monitor()

    if not external then
        -- Laptop sola: el panel interno a pantalla completa, como siempre.
        hl.monitor({ output = internal, mode = INTERNAL_MODE .. "@" .. refresh, position = "0x0", scale = 2 })
        bind_workspace_sets(nil)
        apply_orientation_layout(0)
        return
    end

    local transform = saved_transform(external.name, EXTERNAL_DEFAULT_TRANSFORM)
    local mode = best_mode(external, power.low_power() and 60 or 144)
    if not mode then mode = "preferred" end

    -- Tamaño lógico de la vertical, sacado del modo elegido (no del estado
    -- actual del monitor, que puede ser el de antes de aplicar la regla).
    local ext_w, ext_h = external.width, external.height
    local mode_w, mode_h = mode:match("^(%d+)x(%d+)@")
    if mode_w then
        ext_w, ext_h = tonumber(mode_w), tonumber(mode_h)
    end
    if ext_w == nil or ext_w == 0 then ext_w, ext_h = 2560, 1440 end
    if transform % 2 == 1 then ext_w, ext_h = ext_h, ext_w end
    ext_w = math.floor(ext_w / EXTERNAL_SCALE + 0.5)
    ext_h = math.floor(ext_h / EXTERNAL_SCALE + 0.5)

    -- La laptop en el origen y la vertical a su izquierda, empezando
    -- EXTERNAL_OFFSET_Y más arriba (la disposición con la que se usa la mirada).
    hl.monitor({
        output = external.name,
        mode = mode,
        position = (-ext_w) .. "x" .. (-EXTERNAL_OFFSET_Y),
        scale = EXTERNAL_SCALE,
        transform = transform,
    })
    hl.monitor({
        output = internal,
        mode = INTERNAL_MODE .. "@" .. refresh,
        position = "0x0",
        scale = 2,
    })

    -- Mismo layout que en el desktop: en vertical, `scrolling` (franjas).
    bind_workspace_sets(external.name)
    apply_orientation_layout(transform)
end


-- Orientación guardada por `pantalla-orientacion` (SUPER+ALT+O). Girar no
-- reescribe este archivo: el guion aplica el cambio en vivo con `hyprctl eval`
-- y deja el número acá para que el próximo reload o arranque no devuelva todo a
-- horizontal. Qué es cada valor: 0 = normal, 1 = 90° horario, 2 = 180°, 3 = 90°
-- antihorario (1 y 3 son las dos verticales). Si el giro sale espejado al revés,
-- el otro vertical es el que falta: SUPER+ALT+SHIFT+O alterna entre 1 y 3.
saved_transform = function(output, fallback)
    local file = io.open(os.getenv("HOME") .. "/.local/state/omarchy/display-orientation", "r")
    if not file then return fallback end
    local transform = fallback
    for line in file:lines() do
        local name, value = line:match("^(%S+)%s+([0-3])$")
        if name == output then transform = tonumber(value) end
    end
    file:close()
    return transform
end

-- En vertical (pantalla alta y angosta) el layout de la VERTICAL es `scrolling`
-- con las columnas hacia abajo: cada ventana ocupa una franja horizontal de ancho
-- completo.
--
--   column_width = 1/3  -> tres ventanas quedan como tres franjas IGUALES de arriba
--                          abajo (673 / 666 / 673 en el panel de 1440x2560).
--   fullscreen_on_one_column = true -> con UNA sola ventana ocupa la pantalla
--                          entera (con false quedaba en un tercio).
--
-- OJO: `general.layout` es UNA sola cosa para todo el compositor. Con `scrolling`
-- global, el panel interno (horizontal) también se llenaba de franjas. Por eso el
-- layout va por regla de workspace: la laptop siempre dwindle, la vertical
-- scrolling (o master si el .so todavía no conoce scrolling_overview).
--
-- Con `scrolling` hyprexpo abria su vista nativa por columnas (se veia como un
-- bloque gris y negro) en vez de la grilla de workspaces. El fork agrega
-- plugin:hyprexpo:scrolling_overview (en 0 desde plugins/hyprexpo.lua) para usar
-- siempre la grilla. Si el .so cargado todavia no conoce esa opcion (build viejo,
-- falta reiniciar Hyprland), se queda en `master` para no romper la grilla.
-- En horizontal la vertical también vuelve dwindle, que es lo de siempre.
apply_orientation_layout = function(transform)
    local vertical = transform % 2 == 1
    local external_layout, external_opts

    -- El panel interno (eDP) siempre dwindle: es horizontal.
    hl.config({ general = { layout = "dwindle" } })

    if vertical then
        if hl.get_config("plugin:hyprexpo:scrolling_overview") ~= nil then
            external_layout = "scrolling"
            external_opts = { direction = "down", column_width = 0.3333, fullscreen_on_one_column = true }
            hl.config({ scrolling = { direction = "down", column_width = 0.3333, fullscreen_on_one_column = true } })
        else
            external_layout = "master"
            external_opts = { orientation = "top", new_status = "slave", mfact = 0.3333 }
            hl.config({ master = { orientation = "top", new_status = "slave", mfact = 0.3333 } })
        end
    else
        external_layout = "dwindle"
    end

    for index = 1, spaces.SET_SIZE do
        hl.workspace_rule({ workspace = tostring(spaces.PRIMARY_BASE + index - 1), layout = "dwindle" })
        local spec = { workspace = tostring(spaces.EXTERNAL_BASE + index - 1), layout = external_layout }
        if external_opts ~= nil then spec.layout_opts = external_opts end
        hl.workspace_rule(spec)
    end
end

if variables.machine == "laptop" then
    local function reapply()
        apply_laptop_monitors()
        -- Las reglas de ventanas fijas apuntan al último espacio de la pantalla
        -- de trabajo (Spotify): se re-registran cuando cambia cuál es.
        spaces.apply_window_rules()
    end

    reapply()
    hl.on("monitor.added", function()
        reapply()
        -- Un monitor recién agregado a veces todavía no anuncia sus modos; se
        -- re-aplica al segundo para no quedarse en el modo de cortesía (60 Hz).
        hl.timer(function() reapply() end, { timeout = 1500, type = "oneshot" })
    end)
    hl.on("monitor.removed", reapply)
    hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x1500", scale = 2 })
elseif variables.machine == "desktop" then
    -- La escala y el modo son los que eligió el panel de Better Displays (1.25 y
    -- 144Hz): quedaban solo en su archivo recordado y cualquier reload los
    -- pisaba con 1/144. Ahora viven acá, que carga después, y no bailan.
    --
    -- La regla va dos veces a propósito: por nombre de puerto (DP-2) y por la
    -- descripción del EDID. Si el monitor se reconecta en otro DP, el nombre
    -- cambia y la regla por nombre deja de servir; la de descripción lo sigue.
    -- Ojo: nunca poner un nombre de salida inventado acá — Hyprland crea un
    -- monitor fantasma con ese nombre y se queda sin señal el real.
    local transform = saved_transform("DP-2", 0)
    for _, output in ipairs({ "DP-2", "desc:ASUSTek COMPUTER INC VG27AQL3A T2LMQS058098" }) do
        hl.monitor({
            output = output,
            mode = "2560x1440@143.97301",
            position = "0x0",
            scale = 1.25,
            transform = transform
        })
    end
    apply_orientation_layout(transform)
end

-- Expuesto para el guard de energia: re-evalua la rama de monitores (60/120Hz)
-- en caliente con `hyprctl eval`, sin un `hyprctl reload` completo. El reload
-- tarda ~1.5s y deja el panel en negro todo ese rato; el eval tarda ~10ms.
_G.omarchy = _G.omarchy or {}
_G.omarchy.apply_power_monitors = apply_laptop_monitors
-- Para que el giro en vivo (pantalla-orientacion) cambie también el layout sin
-- un reload completo: `hyprctl eval "omarchy.apply_orientation(1)"`.
_G.omarchy.apply_orientation = apply_orientation_layout

return true
