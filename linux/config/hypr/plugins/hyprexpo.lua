local theme = require("base.theme")

local user = os.getenv("USER") or "eztvn"
hl.plugin.load("/var/cache/hyprpm/" .. user .. "/hyprexpo/hyprexpo.so")

local EXPO_3D = true

local style = {
    hover_select_enable = 1,
    hover_select_delay = 350,
    edge_passthrough = 2,
    gaps_in = 16,
    gaps_out = 22,
    border_width = 2,
    tile_rounding = 12,
    bg_col = theme.color("darker_background", "#0e160e"),
    border_current = "rgba(ffffff60)",
    border_focus = "rgba(ffe9a9e6)",
    border_hover = "rgba(ffffff35)",
    border_default = "rgba(ffffff26)",
    background_image = os.getenv("HOME") .. "/.config/omarchy/backgrounds/black/amoled-black.png",
    background_dim = 0,
    background_transparent = 0,
    threed_enable = 1,
    threed_tilt = 15,
    threed_yaw = 0,
    threed_distance = 1.3,
    threed_radius = 0.04,
    threed_flip_v = 0,
    threed_fisheye = 0.1,
    threed_fisheye_pow = 2,
    glass_glow_enable = 0,
    glass_glow = 0.7,
    hover_scale = 1.05,
    slide_enable = 0,
    slide_amount = 0.16,
}

if hl.plugin.hyprexpo ~= nil then
    local config = {
        columns = 3,
        rows = 3,
        dynamic_grid = 0,
        skip_empty = 0,
        max_workspace = 9,
        gaps_in = style.gaps_in,
        gaps_out = style.gaps_out,
        bg_col = style.bg_col,
        wallpaper_bg = 1,
        border_width = style.border_width,
        border_color = style.border_default,
        border_color_current = style.border_current,
        border_color_focus = style.border_focus,
        border_color_hover = style.border_hover,
        tile_rounding = style.tile_rounding,
        workspace_method = "first 1",
        label_enable = 0,
        show_workspace_numbers = 0,
        keynav_enable = 1,
    }
    if EXPO_3D then
        config.reverse_rows = 1
        config.background_image = style.background_image
        config.background_dim = style.background_dim
        if hl.get_config("plugin:hyprexpo:background_transparent") ~= nil then
            config.background_transparent = style.background_transparent
        end
        config.threed_enable = style.threed_enable
        config.threed_tilt = style.threed_tilt
        config.threed_yaw = style.threed_yaw
        config.threed_distance = style.threed_distance
        config.threed_radius = style.threed_radius
        config.threed_flip_v = style.threed_flip_v
        config.threed_fisheye = style.threed_fisheye
        config.threed_fisheye_pow = style.threed_fisheye_pow
        config.glass_glow_enable = style.glass_glow_enable
        config.glass_glow = style.glass_glow
        config.hover_scale = style.hover_scale
        config.hover_select_enable = style.hover_select_enable
        config.hover_select_delay = style.hover_select_delay
        config.edge_passthrough = style.edge_passthrough
        config.slide_enable = style.slide_enable
        config.slide_amount = style.slide_amount
        config.animation = "specialWorkspace"
    end
    if hl.get_config("plugin:hyprexpo:block_pointer_lock") ~= nil then
        config.block_pointer_lock = 1
    end
    hl.config({ plugin = { hyprexpo = config } })
end

-- Curva de apertura/cierre de la grilla (traída del desktop): ease-out más
-- plano al principio, así se ven los pasos intermedios del zoom.
hl.curve("expoOpen", {
    type = "bezier",
    points = { { 0.22, 0.61 }, { 0.36, 1.0 } }
})
hl.animation({
    leaf = "specialWorkspace",
    enabled = true,
    speed = 4,
    bezier = "expoOpen"
})

return {
    threed = EXPO_3D,
    available = hl.plugin.hyprexpo ~= nil,
}
