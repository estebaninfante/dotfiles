local power = require("base.power")

local border_cache

local function active_border(fallback)
    if border_cache then return border_cache end
    local home = os.getenv("HOME") or ""
    local handle = io.popen("readlink -f '" .. home .. "/.local/state/omarchy/current/background' 2>/dev/null")
    local image = handle and handle:read("*l") or nil
    if handle then handle:close() end
    if image and #image > 0 then
        local program = '{ if (match($0,/\\(([0-9]+),([0-9]+),([0-9]+)/,m)) { r=m[1]+0; g=m[2]+0; b=m[3]+0; l=0.299*r+0.587*g+0.114*b; if (l>ml) { ml=l; br=r; bg=g; bb=b } } } END { printf "%d %d %d", br, bg, bb }'
        local command = "magick '" .. image .. "' -colorspace sRGB -depth 8 -resize 64x64 txt:- 2>/dev/null | sed 1d | awk '" .. program .. "' 2>/dev/null"
        local query = io.popen(command)
        if query then
            local r, g, b = query:read("*a"):match("(%d+)%s+(%d+)%s+(%d+)")
            query:close()
            if r then
                r, g, b = tonumber(r), tonumber(g), tonumber(b)
                local maximum = math.max(r, g, b)
                if maximum > 0 then
                    local factor = (maximum < 205) and (205 / maximum) or 1
                    border_cache = string.format("rgba(%02x%02x%02xf2)",
                        math.min(255, math.floor(r * factor + 0.5)),
                        math.min(255, math.floor(g * factor + 0.5)),
                        math.min(255, math.floor(b * factor + 0.5)))
                    return border_cache
                end
            end
        end
    end
    border_cache = fallback
    return fallback
end

local blur_enabled = not power.low_power()

hl.config({
    general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
        ["col.active_border"] = active_border("rgba(cdcdcdf2)"),
        ["col.inactive_border"] = "rgba(00000000)"
    },
    decoration = {
        rounding = 3,
        blur = {
            enabled = blur_enabled,
            size = 8,
            passes = 3
        }
    }
})

hl.config({
    cursor = {
        no_hardware_cursors = 1
    }
})

return {
    blur_enabled = blur_enabled
}
