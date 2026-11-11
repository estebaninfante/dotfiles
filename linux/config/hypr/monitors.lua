local variables = require("base.variables")
local power = require("base.power")

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
local external = "HDMI-A-1"

-- ¿Hay un monitor HDMI realmente conectado? Preguntamos a Hyprland en vez de
-- leer /sys/class/drm: al arrancar el sysfs puede decir "connected" un instante
-- (sin monitor real) y eso dejaba la laptop a escala 1 (todo chiquito).
local function hdmi_connected()
    for _, m in ipairs(hl.get_monitors()) do
        if m.name == external then return true end
    end
    return false
end

local function apply_laptop_monitors()
    local refresh = power.low_power() and 60 or 120
    if hdmi_connected() then
        hl.monitor({ output = internal, mode = "1920x1080@" .. refresh, position = "0x0", scale = 1 })
        hl.monitor({ output = external, mode = "1920x1080@60", position = "0x0", scale = 1, mirror = internal })
    else
        hl.monitor({ output = internal, mode = "2880x1800@" .. refresh, position = "0x0", scale = 2 })
        hl.monitor({ output = external, mode = "preferred", position = "auto", scale = 1, mirror = internal })
    end
end

-- Orientación guardada por `pantalla-orientacion` (SUPER+ALT+O). Girar no
-- reescribe este archivo: el guion aplica el cambio en vivo con `hyprctl eval`
-- y deja el número acá para que el próximo reload o arranque no devuelva todo a
-- horizontal. Qué es cada valor: 0 = normal, 1 = 90° horario, 2 = 180°, 3 = 90°
-- antihorario (1 y 3 son las dos verticales). Si el giro sale espejado al revés,
-- el otro vertical es el que falta: SUPER+ALT+SHIFT+O alterna entre 1 y 3.
local function saved_transform(output, fallback)
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

-- En vertical (pantalla alta y angosta) el layout es `scrolling` con las columnas
-- hacia abajo: cada ventana ocupa una franja horizontal de ancho completo.
--
--   column_width = 1/3  -> tres ventanas quedan como tres franjas IGUALES de arriba
--                          abajo (673 / 666 / 673 en el panel de 1440x2560).
--   fullscreen_on_one_column = true -> con UNA sola ventana ocupa la pantalla
--                          entera (con false quedaba en un tercio).
--
-- Antes estaba `master` con mfact 1/3: daba tres alturas iguales pero las dos de
-- abajo iban LADO A LADO en vez de una debajo de otra.
-- En horizontal vuelve dwindle, que es lo de siempre.
local function apply_orientation_layout(transform)
    if transform % 2 == 1 then
        hl.config({
            general = { layout = "scrolling" },
            scrolling = { direction = "down", column_width = 0.3333, fullscreen_on_one_column = true }
        })
    else
        hl.config({ general = { layout = "dwindle" } })
    end
end

if variables.machine == "laptop" then
    apply_laptop_monitors()
    hl.on("monitor.added", apply_laptop_monitors)
    hl.on("monitor.removed", apply_laptop_monitors)
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
