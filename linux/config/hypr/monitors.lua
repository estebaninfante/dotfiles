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

if variables.machine == "laptop" then
    apply_laptop_monitors()
    hl.on("monitor.added", apply_laptop_monitors)
    hl.on("monitor.removed", apply_laptop_monitors)
    hl.monitor({ output = "HEADLESS-2", mode = "1920x1080@60", position = "0x1500", scale = 2 })
elseif variables.machine == "desktop" then
    hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })
end

return true
