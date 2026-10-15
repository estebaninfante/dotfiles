local variables = require("base.variables")
local hyprexpo = require("plugins.hyprexpo")

local main_mod = variables.main_mod
local ws_keys = variables.workspace_keys
local EXPO_3D = hyprexpo.threed
local plugin = hl.plugin.hyprexpo

-- TEMP DEBUG (quitar antes de publicar)
local DBG_LOG = "/tmp/expo_dbg.log"
local function dbg(msg)
    local f = io.open(DBG_LOG, "a")
    if f then f:write(msg .. "\n"); f:close() end
end

local expo_focus
local expo_ui_toggle
local expo_fly_super_up

hl.bind(main_mod .. " + Y", function() expo_ui_toggle() end)

if plugin ~= nil then
    hl.define_submap("hyprexpo", function()
        hl.bind("left",  function() plugin.kb_focus("left")  end, { repeating = true })
        hl.bind("right", function() plugin.kb_focus("right") end, { repeating = true })
        hl.bind("up",    function() plugin.kb_focus("up")    end, { repeating = true })
        hl.bind("down",  function() plugin.kb_focus("down")  end, { repeating = true })
        hl.bind("RETURN", function() plugin.kb_confirm() end)
        hl.bind(main_mod .. " + Y", function() expo_ui_toggle() end)
        if EXPO_3D then
            for i = 1, 10 do
                hl.bind(main_mod .. " + " .. ws_keys[i], function() expo_focus(i) end)
                hl.bind(ws_keys[i], function() expo_focus(i) end)
                hl.bind(string.lower(ws_keys[i]), function() expo_focus(i) end)
            end
        end
        hl.bind("catchall", function() hl.dispatch(hl.dsp.submap("reset")) end)
    end)
end

local reset_ws_style
local expo_fly

local EXPO_HOLD_MS = 350
local SUPER_KEYCODES = { [133] = true, [134] = true }

local expo_hold = {
    timer      = nil,
    super_down = false,
    suppressed = false,
    open       = false,
}

local function expo_hold_cancel_timer()
    if expo_hold.timer then
        expo_hold.timer:set_enabled(false)
        expo_hold.timer = nil
    end
end

local function expo_hold_close()
    expo_hold_cancel_timer()
    if expo_hold.open then
        expo_hold.open = false
        if expo_fly then expo_fly.deliberate = false end
        if plugin ~= nil then
            plugin.expo("cancel")
        end
    end
end

local function expo_hold_arm()
    if expo_hold.suppressed or expo_hold.open or plugin == nil then
        return
    end
    expo_hold_cancel_timer()
    expo_hold.timer = hl.timer(function()
        expo_hold.timer = nil
        if expo_hold.super_down and not expo_hold.suppressed and not expo_hold.open then
            reset_ws_style()
            expo_hold.open = true
            if expo_fly then expo_fly.deliberate = true end
            plugin.expo("on")
        end
    end, { timeout = EXPO_HOLD_MS, type = "oneshot" })
end

if plugin ~= nil then
    hl.on("input.keyboard.key", function(keycode, _time, state)
        local is_super = SUPER_KEYCODES[keycode] == true
        if state == 0 then
            if is_super then
                expo_hold.super_down = false
                expo_hold_close()
                expo_hold.suppressed = false
                if expo_fly_super_up then expo_fly_super_up() end
            end
        else
            if is_super then
                if state == 1 then
                    expo_hold.super_down = true
                    expo_hold.suppressed = false
                    expo_hold_arm()
                end
            elseif expo_hold.super_down then
                expo_hold.suppressed = true
                expo_hold_cancel_timer()
            end
        end
    end)

    hl.on("keybinds.submap", function(name)
        hl.config({ input = { follow_mouse = name == "hyprexpo" and 0 or 1 } })
        if name ~= "hyprexpo" then
            if expo_hold.open then expo_hold.open = false end
            if expo_fly then
                if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
                expo_fly.open = false
                expo_fly.sel = nil
                expo_fly.want = nil
                expo_fly.pending = false
                expo_fly.deliberate = false
            end
        end
    end)
end

local EXPO_MODE = "release"
local EXPO_POLL_MS = 25
local EXPO_FLY_MS = 320
local EXPO_PEEK_ZOOM = 2.65
local EXPO_IDLE_MS = 1200
local EXPO_CLOSE_TICKS = 17
expo_fly = {
    open       = false,
    sel        = nil,
    want       = nil,
    pending    = false,
    busy       = 0,
    poll       = nil,
    commit     = nil,
    deliberate = false,
}

local function ws_grid_index(n)
    n = ((n - 1) % 9) + 1
    local col             = (n - 1) % 3
    local row_from_bottom = math.floor((n - 1) / 3)
    return (2 - row_from_bottom) * 3 + col
end

local fly_goto, fly_commit_now, fly_schedule_commit, fly_poll_step, ensure_poll, fly_open_and_go, fly_abort

fly_goto = function(target)
    if not expo_fly.open then return end
    local t      = ws_grid_index(target)
    local sel    = expo_fly.sel or t
    local cx, cy = sel % 3, math.floor(sel / 3)
    local tx, ty = t % 3, math.floor(t / 3)
    local dirx   = tx > cx and "right" or "left"
    local diry   = ty > cy and "down" or "up"
    for _ = 1, math.abs(tx - cx) do plugin.kb_focus(dirx) end
    for _ = 1, math.abs(ty - cy) do plugin.kb_focus(diry) end
    expo_fly.sel = t
end

fly_commit_now = function()
    if not expo_fly.open then return end
    dbg("COMMIT want=" .. tostring(expo_fly.want))
    if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
    if expo_fly.want then
        plugin.kb_selectn(expo_fly.want)
    else
        plugin.kb_confirm()
    end
    expo_fly.open       = false
    expo_fly.sel        = nil
    expo_fly.busy       = EXPO_CLOSE_TICKS
    expo_fly.deliberate = false
    ensure_poll()
end

fly_schedule_commit = function()
    if expo_fly.commit then expo_fly.commit:set_enabled(false) end
    local delay = EXPO_FLY_MS
    expo_fly.commit = hl.timer(function()
        expo_fly.commit = nil
        fly_commit_now()
    end, { timeout = delay, type = "oneshot" })
end

expo_fly_super_up = function()
    if expo_fly.deliberate then
        fly_commit_now()
    end
end

ensure_poll = function()
    if not expo_fly.poll then
        expo_fly.poll = hl.timer(fly_poll_step, { timeout = EXPO_POLL_MS, type = "repeat" })
    end
end

fly_poll_step = function()
    if expo_fly.busy > 0 then
        expo_fly.busy = expo_fly.busy - 1
        if expo_fly.busy == 0 and expo_fly.pending then
            local n = expo_fly.want
            expo_fly.pending = false
            dbg("POLL-pending-fire i=" .. tostring(n))
            if n then fly_open_and_go(n) end
        end
    end
    if not expo_fly.open and not expo_fly.pending and expo_fly.busy == 0 and expo_fly.poll then
        expo_fly.poll:set_enabled(false)
        expo_fly.poll = nil
    end
end

fly_open_and_go = function(n)
    local cur = hl.get_active_workspace()
    dbg("FLY_OPEN_AND_GO i=" .. tostring(n) .. " cur=" .. tostring(cur and cur.id))
    hl.exec_cmd("sleep 0.12; grim /tmp/fly_i" .. tostring(n) .. ".png")
    plugin.expo("on")
    expo_fly.open = true
    expo_fly.sel  = cur and ws_grid_index(cur.id) or nil
    expo_fly.want = n
    fly_goto(n)
    fly_schedule_commit()
end

fly_abort = function()
    if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
    expo_fly.pending    = false
    expo_fly.want       = nil
    expo_fly.deliberate = false
    if expo_fly.open then
        plugin.expo("cancel")
        expo_fly.open = false
        expo_fly.sel  = nil
        expo_fly.busy = EXPO_CLOSE_TICKS
        ensure_poll()
    end
end

expo_ui_toggle = function()
    reset_ws_style()
    if expo_hold.open then
        expo_hold.open = false
        expo_hold.suppressed = true
        expo_hold_cancel_timer()
        expo_fly.deliberate = true
        return
    end
    expo_fly.deliberate = true
    local was_open = expo_fly.open
    if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
    expo_fly.open    = false
    expo_fly.sel     = nil
    expo_fly.want    = nil
    expo_fly.pending = false
    plugin.expo("toggle")
    if was_open then
        expo_fly.busy = EXPO_CLOSE_TICKS
        ensure_poll()
    end
end

_G.expo_ui_toggle = expo_ui_toggle

local cur_ws_id  = nil
local last_ws_id = nil
local ws_travel_guard = false
local function note_ws()
    local w = hl.get_active_workspace()
    if not w then return end
    if w.id ~= cur_ws_id then
        if cur_ws_id ~= nil and not ws_travel_guard then
            last_ws_id = cur_ws_id
        end
        cur_ws_id = w.id
    end
end
note_ws()
hl.on("workspace.active", note_ws)

local function expo_fly_back()
    if last_ws_id then
        expo_focus(last_ws_id)
    end
end

expo_focus = function(i)
    reset_ws_style()
    local has_expo = plugin ~= nil
    local cur      = hl.get_active_workspace()

    if not EXPO_3D then
        local same = cur and cur.id == i
        hl.dispatch(hl.dsp.focus({ workspace = same and "previous" or tostring(i) }))
        return
    end

    if not has_expo or i > 9 then
        fly_abort()
        local same = cur and cur.id == i
        hl.dispatch(hl.dsp.focus({ workspace = same and "previous" or tostring(i) }))
        return
    end

    if expo_fly.open then
        dbg("OPEN-branch i=" .. tostring(i))
        expo_fly.want = i
        fly_goto(i)
        fly_schedule_commit()
        return
    end

    if expo_fly.busy > 0 then
        if cur and cur.id == i then
            return
        end
        -- El overview anterior todavía se está cerrando (closing == true) y
        -- kb_focus no anima en ese estado. En vez de saltar directo con
        -- kb_selectn, encolamos el destino: cuando el cierre termina,
        -- fly_poll_step reabre el expo y vuela hasta i (animado).
        dbg("BUSY-branch i=" .. tostring(i) .. " busy=" .. tostring(expo_fly.busy) .. " -> queue pending")
        expo_fly.want = i
        expo_fly.pending = true
        ensure_poll()
        return
    end

    if not expo_fly.pending and cur and cur.id == i then
        expo_fly_back()
        return
    end

    fly_open_and_go(i)
end

local TRAVEL_SPEED = 4
local TRAVEL_FADE_PCT = 100

local function ws_id_for_index(idx)
    idx = ((idx % 9) + 9) % 9
    local col             = idx % 3
    local row_from_top    = math.floor(idx / 3)
    local row_from_bottom = 2 - row_from_top
    return row_from_bottom * 3 + col + 1
end

local function set_ws_style(vertical, up, linear)
    local pct   = TRAVEL_FADE_PCT .. "%"
    local style = "slidefade " .. pct
    local speed = TRAVEL_SPEED
    if vertical then
        style = up and ("slidefadevert top " .. pct) or ("slidefadevert bottom " .. pct)
        local mon = hl.get_active_monitor()
        if mon and mon.width and mon.width > 0 and mon.height then
            speed = TRAVEL_SPEED * (mon.height / mon.width)
        end
    end
    hl.animation({
        leaf    = "workspaces",
        enabled = true,
        speed   = speed,
        bezier  = linear and "linear" or "expoSmooth",
        style   = style,
    })
    return math.floor(speed * 100)
end

reset_ws_style = function()
    set_ws_style(false, false, false)
end

local ws_style_timer = nil
local function ws_style_revert_after(ms)
    if ws_style_timer then ws_style_timer:set_enabled(false) end
    ws_style_timer = hl.timer(function()
        ws_style_timer = nil
        reset_ws_style()
    end, { timeout = ms, type = "oneshot" })
end

local travel = { steps = {}, timer = nil, linear = false, origin = nil }

local function travel_stop()
    if travel.timer then
        travel.timer:set_enabled(false)
        travel.timer = nil
    end
    travel.steps = {}
    if travel.origin ~= nil then
        last_ws_id = travel.origin
        travel.origin = nil
    end
    ws_travel_guard = false
end

local function travel_step()
    local nxt = table.remove(travel.steps, 1)
    if not nxt then
        travel_stop()
        return
    end
    local isLast = (#travel.steps == 0)
    local cur    = hl.get_active_workspace()
    local up     = (cur == nil) or (nxt.id > cur.id)
    local dur    = set_ws_style(nxt.vertical, up, travel.linear and not isLast)
    hl.dispatch(hl.dsp.focus({ workspace = tostring(nxt.id) }))
    ws_style_revert_after(dur + 20)
    if isLast then
        travel_stop()
        return
    end
    travel.timer = hl.timer(function()
        travel.timer = nil
        travel_step()
    end, { timeout = math.max(80, math.floor(dur * 0.5)), type = "oneshot" })
end

local function ws_travel(i)
    local cur = hl.get_active_workspace()

    if cur and i >= 1 and i <= 9 and cur.id == i and last_ws_id and last_ws_id ~= i then
        i = last_ws_id
    end

    if not cur or i > 9 or i < 1 then
        travel_stop()
        local same = cur and cur.id == i
        hl.dispatch(hl.dsp.focus({ workspace = same and "previous" or tostring(i) }))
        return
    end
    if cur.id == i then
        travel_stop()
        return
    end

    local was_traveling = (travel.timer ~= nil) or (#travel.steps > 0)
    local keep_origin   = travel.origin
    travel_stop()
    local ci     = ws_grid_index(cur.id)
    local ti     = ws_grid_index(i)
    local c, r   = ci % 3, math.floor(ci / 3)
    local tc, tr = ti % 3, math.floor(ti / 3)

    if tc ~= c and tr ~= r then
        travel_stop()
        expo_focus(i)
        return
    end

    local steps  = {}
    while c ~= tc do
        c = c + (tc > c and 1 or -1)
        steps[#steps + 1] = { id = ws_id_for_index(r * 3 + c), vertical = false }
    end
    while r ~= tr do
        r = r + (tr > r and 1 or -1)
        steps[#steps + 1] = { id = ws_id_for_index(r * 3 + c), vertical = true }
    end
    if #steps == 0 then return end

    travel.steps  = steps
    travel.linear = #steps > 1
    travel.origin = (was_traveling and keep_origin) or cur.id
    ws_travel_guard = true
    travel_step()
end

for i = 1, 10 do
    if i < 10 then
        hl.bind(main_mod .. " + " .. ws_keys[i], function() expo_focus(i) end)
    end
    hl.bind(main_mod .. " + SHIFT + " .. ws_keys[i], hl.dsp.window.move({ workspace = tostring(i) }))
end

local grid_dir = {
    up    = function(c) if c <= 6 then return c + 3 end end,
    down  = function(c) if c >= 4 then return c - 3 end end,
    left  = function(c) if (c - 1) % 3 > 0 then return c - 1 end end,
    right = function(c) if (c - 1) % 3 < 2 then return c + 1 end end,
}
local function grid_travel(dir)
    local cur = hl.get_active_workspace()
    if not cur or cur.id < 1 or cur.id > 9 then return end
    local target = grid_dir[dir] and grid_dir[dir](cur.id)
    if target then
        fly_abort()
        travel_stop()
        if dir == "up" then
            set_ws_style(true, true, false)
        elseif dir == "down" then
            set_ws_style(true, false, false)
        else
            set_ws_style(false, false, false)
        end
        hl.dispatch(hl.dsp.exec_cmd("~/.local/bin/grid-move " .. target))
        ws_style_revert_after(800)
    end
end
hl.bind(main_mod .. " + ALT + left",  function() grid_travel("left")  end)
hl.bind(main_mod .. " + ALT + right", function() grid_travel("right") end)
hl.bind(main_mod .. " + ALT + up",    function() grid_travel("up")    end)
hl.bind(main_mod .. " + ALT + down",  function() grid_travel("down")  end)

local HOT_SIZE = 3
local HOT_REARM = 60
local HOT_POLL_MS = 120
local hot_armed = true

if plugin ~= nil then
    hl.timer(function()
        local ok, p = pcall(hl.get_cursor_pos)
        if not ok or not p or not p.x or not p.y then return end
        if p.x <= HOT_SIZE and p.y <= HOT_SIZE then
            if hot_armed and not expo_fly.open and not expo_hold.open and expo_fly.busy == 0 then
                hot_armed = false
                reset_ws_style()
                expo_fly.deliberate = true
                plugin.expo("on")
                expo_fly.open = true
                local cur = hl.get_active_workspace()
                expo_fly.sel = cur and ws_grid_index(cur.id) or nil
                expo_fly.want = nil
            end
        elseif p.x > HOT_REARM or p.y > HOT_REARM then
            hot_armed = true
        end
    end, { timeout = HOT_POLL_MS, type = "repeat" })
end

-- TEMP TEST (quitar antes de publicar)
hl.timer(function()
    dbg("TEST: focus(5)")
    expo_focus(5)
    hl.timer(function()
        dbg("TEST: focus(4)")
        expo_focus(4)
    end, { timeout = 500, type = "oneshot" })
end, { timeout = 800, type = "oneshot" })

return true
