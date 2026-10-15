local HOME = os.getenv("HOME")

local PLUGIN_SO = HOME .. "/.local/share/hypr3d-src/build/hypr3d.so"
local PANORAMA = HOME .. "/.local/share/hypr3d-world/panorama/city_rooftop.jpg"
local MAP = HOME .. "/.local/share/hypr3d-world/map/map.glb"

local function ensure_loaded()
    if hl.plugin.hypr3d ~= nil then
        return true
    end
    pcall(function() hl.plugin.load(PLUGIN_SO) end)
    return hl.plugin.hypr3d ~= nil
end

local function apply()
    if hl.plugin.hypr3d == nil then
        return false
    end

    hl.plugin.hypr3d.config({
        world = {
            panorama = PANORAMA,
            grid = false,
        },
        map = {
            path = MAP,
            flat = true,
            collision = true,
            emissive_scale = 1.0,
            transform = {
                position = { x = 0, y = 0, z = 0 },
                rotation = { x = 0, y = 0, z = 0 },
                scale = { x = 1, y = 1, z = 1 },
            },
        },
        player = {
            flying = true,
            spawn = { x = 0, y = 2, z = 12 },
        },
        windows = { focus_on_aim = false },
    })

    hl.bind("SUPER + F12", hl.plugin.hypr3d.toggle)
    return true
end

local available = ensure_loaded()
if available then
    apply()
end


return { available = available }
