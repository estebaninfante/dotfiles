local theme = require("base.theme")

local HOME = os.getenv("HOME")

-- Resuelve la IMAGEN de fondo del overview apuntando SIEMPRE a la misma fuente
-- unica que el escritorio (~/.local/state/omarchy/current/background, el symlink
-- que escribe `omarchy theme bg set` y sigue el hook theme-set + sync-wallpaper).
-- Con Wallpaper Engine (source=video) usa el frame PNG que captura
-- wallpaper-switch.sh del mismo wallpaper, asi el desktop (video en vivo) y la
-- grilla (frame del mismo efecto) comparten un solo wallpaper.
local function read_trim(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a") or ""
    f:close()
    return (s:match("^%s*(.-)%s*$"))
end

-- El plugin cachea la textura por STRING de ruta: si le pasamos el symlink, la
-- primera carga fallida (symlink roto al parsear) queda cacheada y el overview
-- pinta negro para siempre. Resolvemos al path real (readlink -f) para que cada
-- fondo nuevo sea una ruta distinta y la cache se invalide sola.
local function resolve_image(path)
    if not path then return nil end
    local f = io.popen("readlink -f -- " .. string.format("%q", path) .. " 2>/dev/null")
    if not f then return path end
    local resolved = (f:read("*a") or ""):match("^%s*(.-)%s*$")
    f:close()
    if resolved ~= "" and io.open(resolved, "r") then return resolved end
    return path
end

local bg_link     = HOME .. "/.local/state/omarchy/current/background"
local bg_source   = read_trim(HOME .. "/.config/wallpaper-source") or "static"
local bg_id       = read_trim(HOME .. "/.config/wallpaper-current") or ""
local bg_frame    = (bg_id ~= "") and (HOME .. "/.cache/wallpaper-frames/" .. bg_id .. ".png") or nil
-- Se pasa el SYMLINK, no la ruta resuelta: el plugin resuelve y cachea por
-- (ruta real + mtime + tamano) en cada apertura, y asi un cambio de wallpaper
-- (que reapunta el symlink) se ve al abrir el overview sin reload. Resolviendo
-- aca, el plugin se quedaba con la ruta vieja y se veian dos wallpapers.
local bg_image    = bg_link
if bg_source == "video" and bg_frame and io.open(bg_frame, "r") then
    bg_image = bg_frame
end
-- Si el resuelto no existe (symlink roto/refresco), cae al negro del tema.
if not io.open(bg_image, "r") then
    bg_image = HOME .. "/.config/omarchy/backgrounds/black/amoled-black.png"
end

-- IMPORTANT: never call hl.plugin.load(...) from Lua config code.
-- Doing so re-enters Hyprland's plugin-load pass (handlePluginLoads -> reload
-- -> parse config -> hl.plugin.load again -> ...), which recurses until the
-- stack overflows and the session dies with a SIGSEGV before it is up.
-- Load it out-of-process instead; .local/bin/hyprexpo-load.sh is idempotent
-- and no-ops when hyprexpo is already loaded.
hl.exec_cmd(HOME .. "/.local/bin/hyprexpo-load.sh")

-- Grilla PLANA: el overview se comporta como el de Windows+Tab (o el de
-- Hyprland nativo): los workspaces se ven derechos, sin tilt/perspectiva, sin
-- lente de pez y sin vineta. Con la pantalla vertical el tilt deformaba los
-- previews (cada tile quedaba en trapecio) y la lente curvaba los bordes.
-- Poniendo esto en true vuelve la grilla 3D del fork (threed_tilt/fisheye/
-- radius/glow de abajo); el resto de la config es la misma.
local EXPO_3D = false

local style = {
    hover_select_enable = 1,
    hover_select_delay = 350,
    edge_passthrough = 2,
    gaps_in = 16,
    gaps_out = 22,
    border_width = 2,
    -- Esquinas rectas: la grilla se lee como pestanas de workspace, no como
    -- tarjetas redondeadas (0 = sin radio en el modo plano y en el borde).
    tile_rounding = 0,
    bg_col = theme.color("darker_background", "#0e160e"),
    border_current = "rgba(ffffff60)",
    border_focus = "rgba(ffe9a9e6)",
    border_hover = "rgba(ffffff35)",
    border_default = "rgba(ffffff26)",
    -- UN SOLO WALLPAPER para desktop y overview: el plugin pinta su backdrop con
    -- la MISMA imagen canonica (o el frame del wallpaper de video). Se uso
    -- background_transparent = 1 (capa BACKGROUND real del compositor) pero hoy la
    -- sesion viva renderiza la grilla SIN tiles en ese modo (0-diff con kb_focus;
    -- con backdrop interno se ve grilla+previews, verificado con grim). Si se
    -- restaura el modo transparente, poner 1 aqui y borrar el resolver de arriba.
    background_image = bg_image,
    background_dim = 0,
    background_transparent = 0,
    threed_enable = 1,
    threed_tilt = 15,
    threed_yaw = 0,
    threed_distance = 1.3,
    -- Radio (en UV) de las miniaturas en 3D. 0 = rectas, igual que el modo plano.
    threed_radius = 0,
    -- 1 = el borde sigue la esquina redondeada de la miniatura; 0 = borde recto
    threed_border_round = 0,
    threed_flip_v = 0,
    -- Sin lente de pez: la grilla se ve plana en los bordes (0 = sin barril).
    threed_fisheye = 0,
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
    -- Orden numpad (1 abajo a la izquierda) y curva de apertura: son del
    -- overview, no del modo 3D, asi que valen en los dos.
    config.reverse_rows = 1
    config.animation = "specialWorkspace"
    -- UN SOLO WALLPAPER: el overview pinta el mismo archivo canonico que el
    -- escritorio y los tiles se capturan sin wallpaper, asi que se ve una sola
    -- imagen. Ojo: NO va dentro del bloque 3D, es lo que habilita el
    -- CTransparentTileGuard (tiles sin fondo).
    -- El .so resuelve el symlink y cachea por mtime+tamano, asi que un cambio de
    -- wallpaper se ve en la proxima apertura sin reload (antes quedaba cacheada la
    -- imagen vieja y se veian dos wallpapers distintos).
    config.background_image = style.background_image
    config.background_dim = style.background_dim
    if hl.get_config("plugin:hyprexpo:background_transparent") ~= nil then
        config.background_transparent = style.background_transparent
    end

    if EXPO_3D then
        config.threed_enable = style.threed_enable
        config.threed_tilt = style.threed_tilt
        config.threed_yaw = style.threed_yaw
        config.threed_distance = style.threed_distance
        config.threed_radius = style.threed_radius
        if hl.get_config("plugin:hyprexpo:threed_border_round") ~= nil then
            config.threed_border_round = style.threed_border_round
        end
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
    end
    if hl.get_config("plugin:hyprexpo:keep_layers") ~= nil then
        config.keep_layers = 1
    end
    if hl.get_config("plugin:hyprexpo:block_pointer_lock") ~= nil then
        config.block_pointer_lock = 1
    end
    -- Grilla de workspaces tambien con el layout scrolling (vertical en el desktop),
    -- no la vista nativa por columnas. Ver monitors.lua.
    if hl.get_config("plugin:hyprexpo:scrolling_overview") ~= nil then
        config.scrolling_overview = 0
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
