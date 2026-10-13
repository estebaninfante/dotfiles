local home = os.getenv("HOME")

local function mode()
    local handle = io.open(home .. "/dotfiles/linux/config/kitty/active-theme.conf", "r")
    if handle then
        local link = handle:read("*a"):match("theme%-([a-z]+)")
        handle:close()
        if link then return link end
    end
    return "dark"
end

local cache = {}

local function color(key, fallback)
    if cache[key] ~= nil then return cache[key] end

    local value = fallback
    local handle = io.popen("omarchy-theme-color " .. key .. " 2>/dev/null")
    if handle then
        local out = handle:read("*l")
        handle:close()
        if out and out ~= "" then value = out end
    end

    local hex = value:match("^#(%x%x%x%x%x%x)$")
    if hex then value = "rgb(" .. hex .. ")" end

    cache[key] = value
    return value
end

local function background(fallback)
    local link = home .. "/.local/state/omarchy/current/background"
    local handle = io.popen('realpath "' .. link .. '" 2>/dev/null')
    if handle then
        local out = handle:read("*l")
        handle:close()
        if out and out ~= "" then
            local file = io.open(out, "r")
            if file then file:close() return out end
        end
    end
    return fallback
end

return {
    mode = mode,
    color = color,
    background = background,
}
