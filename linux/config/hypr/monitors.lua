-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

-- Fuente de alimentacion: true si corre con bateria. Se re-evalua en cada
-- parseo/reload (hyprctl reload), asi el panel interno baja a 60Hz al
-- desenchufar sin depender de keywords.
local function power_on_battery()
    local p = io.open("/sys/class/power_supply/ADP0/online", "r")
    if not p then return false end
    local v = p:read("*l")
    p:close()
    return v == "0"
end

-- Perfil power-saver (D-Bus). Ahorro total = bateria O power-saver.
local function power_saver_profile()
    local h = io.popen("busctl get-property org.freedesktop.UPower.PowerProfiles " ..
        "/org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles " ..
        "ActiveProfile 2>/dev/null")
    if not h then return false end
    local v = h:read("*l")
    h:close()
    return v ~= nil and v:find("power-saver") ~= nil
end

local function low_power()
    return power_on_battery() or power_saver_profile()
end

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Panel interno del laptop (eDP-2): 60Hz en ahorro, 120Hz en rendimiento.
-- NOTE: el bloque MONITORS de hyprland.lua es la fuente efectiva; esta version
-- se mantiene por consistencia (menu Omarchy "Monitors"). No duplicar reglas:
-- hyprland.lua NO hace require de este archivo.
if low_power() then
    hl.monitor({ output = "eDP-2", mode = "2880x1800@60", position = "0x0", scale = omarchy_monitor_scale })
end

-- Orbiscreen virtual display (force scale 1)
hl.monitor({ output = "1920x1080", mode = "1920x1080@60", position = "auto", scale = 1 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
