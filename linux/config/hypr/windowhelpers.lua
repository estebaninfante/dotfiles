local function focus_under_cursor()
    local p = hl.get_cursor_pos()
    if not p then return end
    local act = hl.get_active_window()
    local best, best_score = nil, -math.huge
    for _, w in ipairs(hl.get_windows({ mapped = true })) do
        if w.visible and not w.hidden and w.at and w.size then
            local ax, ay = w.at.x, w.at.y
            local sw, sh = w.size.x, w.size.y
            if ax and ay and sw and sh
                and p.x >= ax and p.x < ax + sw
                and p.y >= ay and p.y < ay + sh then
                local score = 0
                if w.floating then score = score + 100 end
                if (w.fullscreen or 0) > 0 then score = score + 200 end
                if act and w.address == act.address then score = score + 500 end
                score = score - (w.focus_history_id or 0)
                if score > best_score then
                    best_score = score
                    best = w
                end
            end
        end
    end
    if best and (not act or act.address ~= best.address) then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. best.address }))
    end
end

local ws_last_win = {}

hl.on("window.active", function()
    local w = hl.get_active_window()
    local ws = hl.get_active_workspace()
    if w and w.address and ws and ws.id then
        ws_last_win[ws.id] = w.address
    end
end)

hl.on("workspace.active", function()
    local ws = hl.get_active_workspace()
    if not ws or not ws.id then return end
    local addr = ws_last_win[ws.id]
    if not addr then return end
    local act = hl.get_active_window()
    if act and act.address == addr then return end
    for _, w in ipairs(hl.get_windows({ mapped = true })) do
        if w.address == addr and w.workspace and w.workspace.id == ws.id then
            hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
            return
        end
    end
    ws_last_win[ws.id] = nil
end)

local function count_floats_on_ws(ws_id)
    local n = 0
    for _, w in ipairs(hl.get_windows({ floating = true, mapped = true })) do
        if w.workspace and w.workspace.id == ws_id then
            n = n + 1
        end
    end
    return n
end

local FLOAT_MAX_W, FLOAT_MAX_H = 1600, 900

local function clamp_float(w)
    if not w or not w.floating or (w.fullscreen or 0) > 0 then return end
    if not w.size then return end
    local sw, sh = w.size.x, w.size.y
    if not sw or not sh then return end
    if sw > FLOAT_MAX_W or sh > FLOAT_MAX_H then
        local scale = math.min(FLOAT_MAX_W / sw, FLOAT_MAX_H / sh)
        hl.dispatch(hl.dsp.window.resize({
            window = "address:" .. w.address,
            x = math.floor(sw * scale),
            y = math.floor(sh * scale),
            relative = false
        }))
    end
end

local function clamp_floats_on_ws(ws_id)
    if not ws_id then return end
    for _, w in ipairs(hl.get_windows({ floating = true, mapped = true })) do
        if w.workspace and w.workspace.id == ws_id then
            clamp_float(w)
        end
    end
end

local function cycle_media(next)
    hl.dispatch(hl.dsp.window.cycle_next({ next = next }))
    hl.dispatch(hl.dsp.window.bring_to_top())
    local w = hl.get_active_window()
    if w and w.floating and w.workspace then
        if count_floats_on_ws(w.workspace.id) >= 2 then
            hl.dispatch(hl.dsp.window.fullscreen({ action = "set", mode = "fullscreen" }))
            clamp_floats_on_ws(w.workspace.id)
        end
    end
end

return {
    focus_under_cursor = focus_under_cursor,
    clamp_float = clamp_float,
    cycle_media = cycle_media,
}
