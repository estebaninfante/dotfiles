local variables = require("base.variables")
local power = require("base.power")

-- ¿Hay un monitor HDMI realmente conectado? Preguntamos a Hyprland en vez de
-- leer /sys/class/drm: al arrancar el sysfs puede decir "connected" un instante
-- (sin monitor real) y eso dejaba la laptop a escala 1 (todo chiquito).
local function hdmi_connected()
    for _, m in ipairs(hl.get_monitors()) do
        if m.name == "HDMI-A-1" then return true end
    end
    return false
end

local function apply_laptop_monitors()
    local refresh = power.low_power() and 60 or 120
    if hdmi_connected() then
        hl.monitor({ output = "eDP-2", mode = "1920x1080@" .. refresh, position = "0x0", scale = 1 })
        hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = 1, mirror = "eDP-2" })
    else
        hl.monitor({ output = "eDP-2", mode = "2880x1800@" .. refresh, position = "0x0", scale = 2 })
        hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1, mirror = "eDP-2" })
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
