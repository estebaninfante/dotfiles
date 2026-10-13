local function on_battery()
    local handle = io.open("/sys/class/power_supply/ADP0/online", "r")
    if not handle then return false end
    local value = handle:read("*l")
    handle:close()
    return value == "0"
end

local function saver_profile()
    local handle = io.popen("busctl get-property org.freedesktop.UPower.PowerProfiles " ..
        "/org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles " ..
        "ActiveProfile 2>/dev/null")
    if not handle then return false end
    local value = handle:read("*l")
    handle:close()
    return value ~= nil and value:find("power-saver") ~= nil
end

local function low_power()
    return on_battery() or saver_profile()
end

return {
    on_battery = on_battery,
    saver_profile = saver_profile,
    low_power = low_power,
}
