local variables = require("base.variables")
local power = require("base.power")

local function hdmi_connected()
    for _, card in ipairs({ "card0", "card1", "card2", "card3" }) do
        local handle = io.open("/sys/class/drm/" .. card .. "-HDMI-A-1/status", "r")
        if handle then
            local status = handle:read("*l")
            handle:close()
            if status == "connected" then return true end
        end
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
