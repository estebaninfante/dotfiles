local HOME = os.getenv("HOME")

local PLUGIN_SO = HOME .. "/.local/share/hypr3d-src/build/hypr3d.so"
local PANORAMA = HOME .. "/.local/share/hypr3d-world/panorama/city_rooftop.jpg"
local MAP = HOME .. "/.local/share/hypr3d-world/map/map.glb"

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

-- IMPORTANT: never call hl.plugin.load(PLUGIN_SO) from Lua config code.
-- Doing so re-enters Hyprland's plugin-load pass (handlePluginLoads -> reload
-- -> parse config -> hl.plugin.load again -> ...), which recurses until the
-- stack overflows and the session dies with a SIGSEGV before it is up.
-- Load it out-of-process instead; .local/bin/hypr3d-load.sh is idempotent and
-- no-ops when hypr3d is already loaded.
hl.exec_cmd(HOME .. "/.local/bin/hypr3d-load.sh")

-- The plugin's PLUGIN_INIT triggers a config reload, so this runs again with
-- hypr3d present and the settings get applied. It also covers later reloads.
if hl.plugin.hypr3d ~= nil then
    apply()
end

return { available = hl.plugin.hypr3d ~= nil }
