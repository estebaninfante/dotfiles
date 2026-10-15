-- Sin gaps: el usuario quiere todo pegado (barra y ventanas).
local GAP_MAX = 0
local GAP_MIN = 0
local GAP_DECAY = 2

local function gaps_for(count)
    count = math.max(1, count)
    local inverse = 1 / (count ^ GAP_DECAY)
    local gap = math.floor(GAP_MIN + (GAP_MAX - GAP_MIN) * inverse + 0.5)
    return gap, gap
end

local last_in, last_out = -1, -1

local function apply()
    local workspace = hl.get_active_workspace()
    local count = 0
    if workspace then
        for _, window in ipairs(hl.get_workspace_windows(workspace.id)) do
            if not window.floating and (window.fullscreen or 0) == 0 then count = count + 1 end
        end
    end
    local gap_in, gap_out = gaps_for(count)
    if gap_in ~= last_in or gap_out ~= last_out then
        last_in, last_out = gap_in, gap_out
        hl.config({ general = { gaps_in = gap_in, gaps_out = gap_out } })
    end
end

for _, event in ipairs({ "window.open", "window.close",
                        "window.move_to_workspace", "window.fullscreen",
                        "window.active", "workspace.active" }) do
    hl.on(event, apply)
end
hl.on("hyprland.start", apply)
pcall(apply)

return true
