local variables = require("base.variables")

local MOONLIGHT_CLASS  = "com.moonlight_stream.Moonlight"
local MOONLIGHT_SUBMAP = "moonlight"
local MOONLIGHT_KEY    = variables.main_mod .. " + " .. variables.workspace_keys[10]
local MOONLIGHT_SPECIAL = "moonlight"

local LAN_MOUSE_CAPTURE = "lan-mouse-capture.sh"
local LAN_MOUSE_POLL_MS = 3000

local guard = false

local function focused()
    local w = hl.get_active_window()
    return w ~= nil and w.class == MOONLIGHT_CLASS
end

local function grab(on)
    hl.config({ binds = { disable_keybind_grabbing = on } })
end

local function release_lan_mouse(on)
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

local function in_special()
    local w = moonlight_window()
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

local function special_visible()
    for _, m in ipairs(hl.get_monitors()) do
        local sp = m.active_special_workspace
        if sp ~= nil and sp.name == SPECIAL_SELECTOR then
            return true
        end
    end
    return false
end

local function toggle()
    if special_visible() then
        leave()
    else
        enter()
    end
end

local function sync()
    local cur = hl.get_current_submap() or ""
    if focused() then
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
