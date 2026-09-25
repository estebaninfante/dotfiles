-- lock_anim.lua
-- Slide every window of the active workspace off-screen toward its nearest
-- edge, so hyprlock's screenshot shows a clean desktop. Restores on unlock.
-- Exposed as global OMARCHY_LOCK with .out() and .back().

local MARGIN = 80

local snapshot = {}

local function mon_of_ws(ws)
    local mon = ws and ws.monitor
    if mon and mon.position then return mon end
    return hl.get_active_monitor()
end

local function slide_out()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local mon = mon_of_ws(ws)
    if not mon or not mon.position then return end

    local mx, my = mon.position.x, mon.position.y
    local mw, mh = mon.width, mon.height

    local wins = hl.get_workspace_windows(ws.id) or {}

    snapshot = {}
    local targets = {}

    for _, w in ipairs(wins) do
        if w.address and w.mapped and not w.hidden and w.at and w.size then
            local rec = {
                address = w.address,
                x = w.at.x,
                y = w.at.y,
                w = w.size.x,
                h = w.size.y,
                floating = w.floating and true or false,
                fullscreen = w.fullscreen or 0,
            }
            snapshot[#snapshot + 1] = rec

            if rec.fullscreen ~= 0 then
                hl.dispatch(hl.dsp.window.fullscreen({ action = "unset", window = "address:" .. w.address }))
            end
            if not rec.floating then
                hl.dispatch(hl.dsp.window.float({ action = "set", window = "address:" .. w.address }))
            end

            local cx = rec.x + rec.w / 2
            local cy = rec.y + rec.h / 2
            local dl = cx - mx
            local dr = (mx + mw) - cx
            local dt = cy - my
            local db = (my + mh) - cy
            local edge = math.min(dl, dr, dt, db)

            local tx, ty = rec.x, rec.y
            if edge == dl then
                tx = mx - rec.w - MARGIN
            elseif edge == dr then
                tx = mx + mw + MARGIN
            elseif edge == dt then
                ty = my - rec.h - MARGIN
            else
                ty = my + mh + MARGIN
            end

            targets[#targets + 1] = { address = w.address, x = tx, y = ty }
        end
    end

    for _, t in ipairs(targets) do
        hl.dispatch(hl.dsp.window.move({
            window = "address:" .. t.address,
            x = t.x,
            y = t.y,
            relative = false,
        }))
    end
end

local function slide_back()
    for _, rec in ipairs(snapshot) do
        local addr = "address:" .. rec.address
        local w = hl.get_window(addr)
        if w then
            hl.dispatch(hl.dsp.window.move({
                window = addr, x = rec.x, y = rec.y, relative = false,
            }))
            if rec.floating == false then
                hl.dispatch(hl.dsp.window.float({ action = "unset", window = addr }))
            end
            if rec.fullscreen ~= 0 then
                hl.dispatch(hl.dsp.window.fullscreen({
                    action = "set", mode = "fullscreen", window = addr,
                }))
            end
        end
    end
    snapshot = {}
end

_G.OMARCHY_LOCK = {
    out = slide_out,
    back = slide_back,
}

return _G.OMARCHY_LOCK
