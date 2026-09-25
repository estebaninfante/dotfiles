-- ========================
-- GLOBAL VARIABLES

-- ========================
local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "dolphin"
local menu = "ulauncher"

-- ========================
-- MACHINE DETECTION
-- ========================
local f = io.open(os.getenv("HOME") .. "/.config/machine-type", "r")
local machine = f and f:read("*a"):match("^%s*(.-)%s*$") or "laptop"
if f then f:close() end

-- La grilla 3D/fisheye de hyprexpo es un parche LOCAL del plugin que solo vive
-- en el desktop. En laptop se usa el plugin stock (grilla plana, sin peek ni
-- claves 3D). Este flag gatea todo lo experimental a desktop; laptop queda con
-- el overview basico.
local EXPO_3D = (machine == "desktop")

-- Tema global (canonico: active-theme.conf de kitty, symlink al repo).
-- Devuelve "light"|"dark"; default dark si no se puede leer.
local function theme_mode()
    local t = io.open(os.getenv("HOME") .. "/dotfiles/linux/config/kitty/active-theme.conf", "r")
    if t then
        local link = t:read("*a"):match("theme%-([a-z]+)")
        t:close()
        if link then return link end
    end
    return "dark"
end

-- Colores del tema Omarchy actual, resueltos desde colors.toml via
-- omarchy-theme-color. Devuelve "rgb(rrggbb)" o el fallback dado. Se cachea
-- por proceso: al cambiar de tema, omarchy-theme-set hace hyprctl reload y se
-- vuelve a evaluar esta config, refrescando los colores.
local theme_color_cache = {}
local function theme_color(key, fallback)
    if theme_color_cache[key] ~= nil then return theme_color_cache[key] end

    local val = fallback
    local p = io.popen("omarchy-theme-color " .. key .. " 2>/dev/null")
    if p then
        local out = p:read("*l")
        p:close()
        if out and out ~= "" then val = out end
    end

    local hex = val:match("^#(%x%x%x%x%x%x)$")
    if hex then val = "rgb(" .. hex .. ")" end

    theme_color_cache[key] = val
    return val
end

-- ========================
-- XWAYLAND
-- ========================
hl.config({
    xwayland = {
        force_zero_scaling = true
    }
})

-- ========================
-- ENVIRONMENT VARIABLES
-- ========================
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
-- GDK_SCALE debe coincidir con la escala del monitor principal:
-- laptop eDP-1 scale=2, desktop DP-1 scale=1. Mismatch → GTK apps 2x.
if machine == "desktop" then
    hl.env("GDK_SCALE", "1")
else
    hl.env("GDK_SCALE", "2")
end
-- PREPEND ~/.local/bin al PATH existente (NO reemplazarlo).
-- Prepend para no perder el PATH del sistema (kitty/waybar en /usr/bin).
hl.env("PATH", os.getenv("HOME") .. "/.local/bin:" .. os.getenv("PATH"))
hl.env("XDG_DATA_HOME", os.getenv("HOME") .. "/.local/share")
if machine == "desktop" then
    -- WebKitGTK DMA-BUF can render Handy's Wayland overlay fully transparent
    -- with the desktop NVIDIA stack. Force software WebKit compositing.
    hl.env("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
    -- gtk-layer-shell overlay is transparent on this desktop's Wayland stack;
    -- use Handy's regular always-on-top recording window instead.
    hl.env("HANDY_NO_GTK_LAYER_SHELL", "1")
end

-- ========================
-- MONITORS
-- ========================
-- bgcolor=rgba(0,0,0,1) eliminates white flash before wallpaper loads
if machine == "laptop" then
    hl.monitor({ output = "eDP-1",     mode = "2880x1800@120", position = "0x0",      scale = 2 })
    -- NOTE: mirror = "eDP-1" has race condition in Hyprland 0.56.1.
    -- If mirror doesn't apply on boot, run workaround:
    --   hyprctl eval 'hl.monitor({ output = "HDMI-A-1", disabled = true })'
    --   sleep 1 && hyprctl eval 'hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@144", position = "0x0", scale = 1, mirror = "eDP-1", disabled = false })'
    hl.monitor({ output = "HDMI-A-1",  mode = "2560x1440@144", position = "0x0", scale = 1, mirror = "eDP-1" })
elseif machine == "desktop" then
    hl.monitor({ output = "DP-2",  mode = "2560x1440@144", position = "0x0", scale = 1 })
end

-- ========================
-- INPUT
-- ========================
hl.config({
    general = {
        resize_on_border = true
    },
    input = {
        kb_layout   = "dvk_prog,es,us",
        kb_variant  = "basic,,",
        kb_options  = "caps:none",
        follow_mouse = 1,
        mouse_refocus = true,
        sensitivity = 0
    }
})

if machine == "laptop" then
    hl.config({
        input = {
            touchpad = {
                disable_while_typing = true,
                tap_to_click = true,
                clickfinger_behavior = true,
                tap_and_drag = false,
                drag_lock = false,
                natural_scroll = true,
                scroll_factor = 0.5
            }
        }
    })
end

-- ========================
-- BORDE DE VENTANA ACTIVA = COLOR DEL WALLPAPER
-- ========================
-- Toma el fondo actual de Omarchy (~/.local/state/omarchy/current/background,
-- symlink), muestrea su pixel mas brillante con ImageMagick y lo re-escala a
-- una intensidad visible: los wallpapers gradiente casi-negro -> rojo quedarian
-- invisibles como borde de 2px. Se conserva el tono (mismos ratios RGB).
-- Cache por proceso: cambiar de fondo exige hyprctl reload.
local active_border_cache
local function active_border(fallback)
    if active_border_cache then return active_border_cache end
    local home = os.getenv("HOME") or ""
    local p = io.popen("readlink -f '" .. home .. "/.local/state/omarchy/current/background' 2>/dev/null")
    local img = p and p:read("*l") or nil
    if p then p:close() end
    if img and #img > 0 then
        local prog = '{ if (match($0,/\\(([0-9]+),([0-9]+),([0-9]+)/,m)) { r=m[1]+0; g=m[2]+0; b=m[3]+0; l=0.299*r+0.587*g+0.114*b; if (l>ml) { ml=l; br=r; bg=g; bb=b } } } END { printf "%d %d %d", br, bg, bb }'
        local cmd = "magick '" .. img .. "' -depth 8 -resize 64x64 txt:- 2>/dev/null | sed 1d | awk '" .. prog .. "' 2>/dev/null"
        local q = io.popen(cmd)
        if q then
            local r, g, b = q:read("*a"):match("(%d+)%s+(%d+)%s+(%d+)")
            q:close()
            if r then
                r, g, b = tonumber(r), tonumber(g), tonumber(b)
                local mx = math.max(r, g, b)
                if mx > 0 then
                    local k = (mx < 205) and (205 / mx) or 1
                    active_border_cache = string.format("rgba(%02x%02x%02xf2)",
                        math.min(255, math.floor(r * k + 0.5)),
                        math.min(255, math.floor(g * k + 0.5)),
                        math.min(255, math.floor(b * k + 0.5)))
                    return active_border_cache
                end
            end
        end
    end
    active_border_cache = fallback
    return fallback
end

-- ========================
-- APPEARANCE (LOOK & FEEL)
-- ========================
hl.config({
    general = {
        gaps_in        = 10,
        gaps_out       = 10,
        border_size    = 2,
        ["col.active_border"]   = active_border("rgba(e0413bff)"),
        ["col.inactive_border"] = "rgba(00000000)"
    },
    decoration = {
        rounding = 3,
        blur = {
            enabled = true,
            size   = 8,
            passes = 3
        }
    }
})

-- ========================
-- GAPS DINAMICOS POR Nº DE VENTANAS (SIMETRICOS)
-- ========================
-- Un unico valor para gaps_in y gaps_out en cada momento: las cuatro gaps
-- (barra, bordes de pantalla y entre ventanas) miden siempre lo mismo. El
-- valor baja a medida que hay mas ventanas en el workspace.
local GAP_MAX   = 18   -- pocas ventanas
local GAP_MIN   = 8    -- muchas ventanas
local GAP_DECAY = 2    -- exponente: mayor = cae mas rapido

local function gaps_for(n)
    n = math.max(1, n)
    local inv = 1 / (n ^ GAP_DECAY)
    local g   = math.floor(GAP_MIN + (GAP_MAX - GAP_MIN) * inv + 0.5)
    return g, g
end

local last_gi, last_go = -1, -1

local function apply_dynamic_gaps()
    local ws = hl.get_active_workspace()
    local n = 0
    if ws then
        for _, w in ipairs(hl.get_workspace_windows(ws.id)) do
            if not w.floating and (w.fullscreen or 0) == 0 then n = n + 1 end
        end
    end
    local gi, go = gaps_for(n)
    if gi ~= last_gi or go ~= last_go then
        last_gi, last_go = gi, go
        hl.config({ general = { gaps_in = gi, gaps_out = go } })
    end
end

for _, ev in ipairs({ "window.open", "window.close", "window.destroy",
                      "window.move_to_workspace", "window.fullscreen",
                      "window.active", "workspace.active" }) do
    hl.on(ev, apply_dynamic_gaps)
end
hl.on("hyprland.start", apply_dynamic_gaps)
pcall(apply_dynamic_gaps)

hl.layer_rule({
    match = { namespace = "swaync" },
    blur = true
})

-- Sistema de captura de pantalla (shot: wayfreeze + slurp + grim): ninguna
-- capa debe animarse. grim captura la salida COMPUESTA, asi que si wayfreeze
-- o el selector de slurp ("selection") entran/salen con el style "popin" del
-- leaf "layers" (mas abajo), la captura los pilla a medio animar y sale la
-- imagen encogida hacia el centro.
hl.layer_rule({
    match = { namespace = "wayfreeze" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "selection" },
    no_anim = true,
    animation = "none"
})

hl.layer_rule({
    match = { namespace = "hyprpicker" },
    no_anim = true,
    animation = "none"
})

-- swappy (editor de capturas) como ventana: sin animacion de entrada/salida.
hl.window_rule({ match = { class = "swappy" }, no_anim = true })

-- Omarchy shell blur (handled by omarchy's own shell config)
-- Launcher (omarchy-menu): blur tras el fondo semitransparente del menu
-- (shell.toml [menu] background-alpha). Sin esta regla solo se ve "fantasma".
-- no_anim: el fade lo maneja el propio menu en QML (eztvn.menu, 140ms);
-- el popin del compositor + blur rompe el fade-out de capas (issue 875).
hl.layer_rule({
    match = { namespace = "omarchy-menu" },
    blur = true,
    no_anim = true,
    animation = "none"
})

-- ========================
-- CURSOR
-- ========================
hl.config({
    cursor = {
        no_hardware_cursors = 0
    }
})

-- ========================
-- ANIMATIONS
-- ========================
-- Interruptor maestro de animaciones. Con false, TODA animacion (incluido
-- el leaf "workspaces") se fuerza a warp instantaneo, ignorando los leaves.
-- Debe estar en true para que cualquier leaf animado funcione.
hl.config({
    animations = {
        enabled = true
    }
})

-- Arbol desactivado por defecto: todo hereda "off" salvo lo que se activa
-- explicitamente abajo (windowsMove + workspaces).

-- Curva suave sin rebote (ease-out): arranca con impulso y desacelera al final.
-- Reemplaza al bezier "default" (que trae overshoot y se siente mas brusco) en
-- el morph 3D de la grilla y en el deslizamiento de workspaces.
hl.curve("expoSmooth", {
    type = "bezier",
    points = { { 0.16, 1.0 }, { 0.30, 1.0 } }
})

hl.animation({
    leaf = "global",
    enabled = true,
    speed = 8,
    bezier = "default"
})

-- windowsMove: glide suave al mover flotantes por teclado Y el morph de la
-- grilla expo (abrir/cerrar = zoom, y el salto entre workspaces con SUPER+n).
-- Curva sin rebote; velocidad mas corta = saltos entre workspaces mas agiles.
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 4,
    bezier = "expoSmooth"
})

-- windowsMove tambien anima los drags manuales (mouse) → se sienten
-- lentos/trabados. Los drags del raton siguen instantaneos, solo el
-- movimiento por teclado conserva el glide.
hl.config({
    misc = {
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        on_focus_under_fullscreen = 1
    }
})


-- Carrusel de workspaces: slide puro para que las ventanas se "empujen" y el
-- cambio se sienta continuo (un mismo espacio, sin salto/fundido). El viaje por
-- desktops intermedios lo maneja ws_travel (seccion WORKSPACE TRAVEL), que
-- ademas cambia el estilo a vertical segun la direccion del grid.
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 4,
    bezier = "expoSmooth",
    style = "slide"
})

-- Apertura "TV viejo": bloom casi instantaneo desde 10% (snap on).
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4,
    bezier = "default",
    style = "slide"
})

-- Cierre: colapso inverso (popin reproducido en reversa).
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2,
    bezier = "default",
    style = "slide"
})

-- Layers (waybar, swaync, omarchy shell): popin + fade simetricos in/out.
-- speed 1 hacia atras era lentisima (in tardaba) y layersOut heredaba estilo
-- vacio → el cierre desaparecia sin animacion. In/Out y fade explicitos.
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 6,
    bezier = "default",
    style = "popin"
})
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 6,
    bezier = "default",
    style = "popin"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 6,
    bezier = "default",
    style = "popin"
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 6,
    bezier = "default"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 6,
    bezier = "default"
})

-- ========================
-- DEVICE (touchpad) — laptop only
-- ========================
if machine == "laptop" then
    -- Disable the ELAN Mouse companion (relative device without DWT).
    -- ELAN HID multitouch creates both Mouse + Touchpad; Mouse ignores
    -- disable_while_typing, so palm touches move the cursor while typing.
    hl.device({
        name    = "elan06fa:00-04f3:3280-mouse",
        enabled = false
    })
    hl.device({
        name    = "elan06fa:00-04f3:3280-touchpad",
        enabled = true
    })
end

-- ========================
-- AUTO-START (optimized order)
-- ========================
hl.on("hyprland.start", function()
    -- 1. Wallpaper immediately (via hyprpaper)
    if machine == "laptop" then
        hl.exec_cmd("sleep 1 && hyprpaper --config /home/eztvn/.config/hypr/hyprpaper-laptop.conf")
    else
        -- Desktop: linux-wallpaperengine via systemd user service
    end

    -- 2. Bar and UI (omarchy shell via omarchy-launch-shell)
    hl.exec_cmd("omarchy-launch-shell")
    hl.exec_cmd("swaync")

    -- 3. D-Bus environment and portals
    -- ELECTRON_OZONE_PLATFORM_HINT/GDK_SCALE: apps activadas via dbus/systemd
    -- (tray, xdg-open) no heredan env de Hyprland. Sin el hint, Electron cae a
    -- XWayland y con force_zero_scaling abre 1x sobre monitor scale=2 (chico).
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE")
    -- Arrancar via systemd da a la unit el env (WAYLAND_DISPLAY) que necesita.
    hl.exec_cmd("sleep 2 && systemctl --user start xdg-desktop-portal-hyprland && systemctl --user restart xdg-desktop-portal && systemctl --user start lan-mouse")

    -- 4. Background services
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    -- polkit agent: hyprpolkitagent (unit systemd user, ver setup-omarchy.sh)
    hl.exec_cmd("hypridle")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-" .. (theme_mode() == "light" and "light" or "dark") .. "'")
    hl.exec_cmd("urserver --daemon")
    hl.exec_cmd("swayosd-server --top-margin=0.4")
    hl.exec_cmd("sleep 5 && handy --start-hidden")

    -- Sunshine (host Moonlight): arranca con retardo una vez Wayland-1 +
    -- xdg-desktop-portal estan listos (captura via Wayland, no KMS).
    -- NO via graphical-session.target: con linger arranca al boot y captura
    -- la GPU (KMS) antes del compositor → cuelga GDM/login.
    hl.exec_cmd("sleep 8 && systemctl --user start sunshine")

    if machine == "laptop" then
        hl.exec_cmd("sleep 5 && libinput-gestures-setup start")
    end

    -- Arrancar siempre en el workspace 5
    hl.dsp.focus({ workspace = 5 })

    -- Re-parsea config ~3s después del inicio para limpiar la barra de
    -- error transitorio de Hyprland (aparece al login, desaparece al guardar).
    hl.exec_cmd("sleep 3 && hyprctl reload")
end)

-- ========================
-- HYPREXPO (overview grilla)
-- 9 slots fijos: 3 cols × 3 rows. SUPER+Y abre/cierra.
-- Orden numpad: 789 / 456 / 123 (reverse_rows=1, parche local del plugin).
-- Autocarga desde config (Hyprland >= 0.56, hl.plugin.load). Así el plugin
-- queda cargado en cada arranque aunque hyprpm no se invoque al inicio.
-- ========================
hl.plugin.load("/var/cache/hyprpm/eztvn/hyprexpo/hyprexpo.so")

-- ========================
-- HYPREXPO: ESTILO (editar aqui)
-- ========================
-- Todo el aspecto visual de la grilla vive en esta tabla. Cambia un valor y
-- ejecuta: hyprctl reload
-- Los colores salen del tema Omarchy activo (colors.toml); al cambiar de tema
-- se refrescan solos porque omarchy-theme-set recarga Hyprland.
local expo_style = {
    gaps_in       = 0,        -- separacion entre tiles (flotantes)
    gaps_out      = 22,       -- margen alrededor de la grilla
    border_width  = 2,        -- grosor del borde de cada tile (glass fino)
    tile_rounding = 12,       -- esquinas redondeadas de los tiles (glass)
    bg_col         = theme_color("darker_background", "#0e160e"),
    -- Borde glass fino: blanco/accent semitransparente para no cortar el fondo.
    border_current = "rgba(ffffff60)",
    border_focus   = "rgba(ffe9a960)",
    border_hover   = "rgba(ffffff35)",
    -- Fondo detras de los escritorios flotantes (imagen). Vacio = color bg_col.
    background_image = "/home/eztvn/.config/hypr/wallpapers/gradient_blackred_simple_1440p.jpg",
    background_dim   = 0,     -- oscurecer la imagen (0-100)
    -- Grilla en perspectiva 3D (experimental). threed_enable=0 la deja plana.
    threed_enable   = 1,      -- 1 = grilla inclinada en perspectiva (selector 3D)
    threed_tilt     = 50,     -- inclinacion en grados (0 = sin perspectiva)
    threed_yaw      = 0,      -- giro horizontal en grados
    threed_distance = 1.3,    -- distancia de camara (alturas de monitor)
    threed_radius   = 0.04,   -- redondeo de esquinas en 3D (fraccion, glass look)
    threed_flip_v   = 0,      -- voltear verticalmente las texturas (0/1)
    -- Lente ojo de pez: curva los bordes de la grilla (0 = sin distorsion).
    threed_fisheye  = 0.18,   -- fuerza del barrel fisheye (comprime bordes, no magnifica)
    threed_fisheye_pow = 2,   -- exponente del radial
    -- Estetica neon/glass: bloom alrededor de los tiles.
    glass_glow_enable = 1,    -- 1 = glow neon activo
    glass_glow      = 0.7,    -- intensidad del bloom
    hover_scale     = 1.05,   -- escala del tile al pasar el mouse (1 = sin zoom)
    -- Slide direccional del cierre: la grilla se corre hacia el tile destino y
    -- vuelve (out/in), en la direccion del movimiento (horizontal o vertical).
    slide_enable    = 0,      -- 0 = zoom simple y limpio (sin reajuste)
    slide_amount    = 0.16,   -- corrimiento como fraccion del monitor
}

-- Laptop: sin parche local -> grilla plana y limpia. Estos valores tambien se
-- omiten al configurar el plugin (mas abajo) para no mandar claves que el
-- plugin stock no conoce.
if not EXPO_3D then
    expo_style.threed_enable     = 0
    expo_style.threed_fisheye    = 0
    expo_style.glass_glow_enable = 0
    expo_style.hover_scale       = 1.0
    expo_style.slide_enable      = 0
    expo_style.background_image  = ""
end

if hl.plugin.hyprexpo ~= nil then
    -- Claves base: las entienden tanto el plugin stock (laptop) como el parcheado.
    local expo_cfg = {
        columns = 3,
        rows = 3,
        dynamic_grid = 0,
        skip_empty = 0,
        max_workspace = 9,
        gaps_in = expo_style.gaps_in,
        gaps_out = expo_style.gaps_out,
        bg_col = expo_style.bg_col,
        border_width = expo_style.border_width,
        border_color_current = expo_style.border_current,
        border_color_focus = expo_style.border_focus,
        border_color_hover = expo_style.border_hover,
        tile_rounding = expo_style.tile_rounding,
        workspace_method = "first 1",
        label_enable = 0,
        show_workspace_numbers = 0,
        keynav_enable = 1,
    }
    -- Claves del parche local (3D/fisheye/glass/reverse_rows). Solo desktop: el
    -- plugin stock no las reconoce.
    if EXPO_3D then
        expo_cfg.reverse_rows = 1
        expo_cfg.background_image = expo_style.background_image
        expo_cfg.background_dim = expo_style.background_dim
        expo_cfg.threed_enable = expo_style.threed_enable
        expo_cfg.threed_tilt = expo_style.threed_tilt
        expo_cfg.threed_yaw = expo_style.threed_yaw
        expo_cfg.threed_distance = expo_style.threed_distance
        expo_cfg.threed_radius = expo_style.threed_radius
        expo_cfg.threed_flip_v = expo_style.threed_flip_v
        expo_cfg.threed_fisheye = expo_style.threed_fisheye
        expo_cfg.threed_fisheye_pow = expo_style.threed_fisheye_pow
        expo_cfg.glass_glow_enable = expo_style.glass_glow_enable
        expo_cfg.glass_glow = expo_style.glass_glow
        expo_cfg.hover_scale = expo_style.hover_scale
        expo_cfg.slide_enable = expo_style.slide_enable
        expo_cfg.slide_amount = expo_style.slide_amount
    end
    hl.config({ plugin = { hyprexpo = expo_cfg } })
end

-- expo_focus / expo_ui_toggle se definen mas abajo (seccion fly-through).
-- Forward-decl para que los binds de abajo (submap) los usen y no queden con nil.
local expo_focus
local expo_ui_toggle
local expo_fly_super_up

hl.bind(mainMod .. " + Y", function() expo_ui_toggle() end)

-- Navegacion por teclado dentro de la grilla expo. El plugin entra al submap
-- "hyprexpo" al abrir (keynav_enable=1) y lo abandona al cerrar, asi que aqui
-- solo definimos sus binds. Flechas mueven el foco del tile, Enter confirma y
-- salta al workspace, y catchall devuelve el control al submap por defecto.
-- Nota: el submap usa los binds internos del plugin (keynav) tal como vienen.
if hl.plugin.hyprexpo ~= nil then
    hl.define_submap("hyprexpo", function()
        -- Flechas: navegan el foco del tile dentro de la grilla (keynav del plugin).
        hl.bind("left",  function() hl.plugin.hyprexpo.kb_focus("left")  end, { repeating = true })
        hl.bind("right", function() hl.plugin.hyprexpo.kb_focus("right") end, { repeating = true })
        hl.bind("up",    function() hl.plugin.hyprexpo.kb_focus("up")    end, { repeating = true })
        hl.bind("down",  function() hl.plugin.hyprexpo.kb_focus("down")  end, { repeating = true })
        hl.bind("RETURN", function() hl.plugin.hyprexpo.kb_confirm() end)
        -- Sin esto el catchall se come el primer SUPER+Y y habria que pulsarlo
        -- dos veces para cerrar la grilla.
        hl.bind(mainMod .. " + Y", function() expo_ui_toggle() end)
        -- Replica de los binds globales SUPER+<ws>: con la grilla abierta,
        -- SUPER+<n> salta al desktop n (fly-through). Solo desktop: en laptop el
        -- plugin stock no tiene peek/retarget y la navegacion queda con flechas
        -- y Enter (keynav nativo).
        if EXPO_3D then
            local ws_keys = { "M", "W", "V", "H", "T", "N", "G", "C", "R", "S" }
            for i = 1, 10 do
                hl.bind(mainMod .. " + " .. ws_keys[i], function() expo_focus(i) end)
                hl.bind(ws_keys[i], function() expo_focus(i) end)
                hl.bind(string.lower(ws_keys[i]), function() expo_focus(i) end)
            end
        end
        hl.bind("catchall", function() hl.dispatch(hl.dsp.submap("reset")) end)
    end)
end

-- Deja el leaf workspaces en horizontal (definida abajo, junto a set_ws_style).
-- El fly-through y el long-press la usan antes de su definicion.
local reset_ws_style
-- Estado del fly-through (definido abajo); el long-press lo usa antes de su def.
local expo_fly

-- ========================
-- EXPO: LONG-PRESS SUPER
-- Mantener SUPER en solitario EXPO_HOLD_MS abre la grilla; al soltarlo se cierra
-- con "cancel" y te deja en el desktop actual (sin cambiar de workspace).
-- Si mientras SOSTIENES SUPER pulsas cualquier otra tecla (SUPER+flecha, SUPER+Q,
-- cambio de ventana, etc.) se cancela la apertura y NO se vuelve a armar hasta
-- soltar SUPER por completo: asi un atajo nunca dispara la grilla.
-- Deteccion por el bus crudo input.keyboard.key (xkb keycode = evdev + 8, o sea
-- Super_L=133 / Super_R=134), en vez de un bindr sobre modificador: esos se
-- cancelan si pulsas otra tecla entre medio y no serian fiables.
-- El estado es un booleano, NO un contador: Hyprland puede emitir el mismo
-- evento mas de una vez y el contador se desincronizaba, dejando el long-press
-- trabado (suppressed pegado) hasta recargar la config.
-- ========================
local EXPO_HOLD_MS = 350
local SUPER_KEYCODES = { [133] = true, [134] = true }

local expo_hold = {
    timer      = nil,    -- oneshot pendiente para abrir la grilla
    super_down = false,  -- hay algun Super pulsado ahora mismo
    suppressed = false,  -- se pulso otra tecla durante este hold: no abrir
    open       = false,  -- la grilla la abrio este long-press (para cerrarla al soltar)
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
        if hl.plugin.hyprexpo ~= nil then
            hl.plugin.hyprexpo.expo("cancel")
        end
    end
end

local function expo_hold_arm()
    if expo_hold.suppressed or expo_hold.open or hl.plugin.hyprexpo == nil then
        return
    end
    expo_hold_cancel_timer()
    expo_hold.timer = hl.timer(function()
        expo_hold.timer = nil
        if expo_hold.super_down and not expo_hold.suppressed and not expo_hold.open then
            reset_ws_style()
            expo_hold.open = true
            -- Long-press: grilla deliberada -> el commit espera al release.
            if expo_fly then expo_fly.deliberate = true end
            hl.plugin.hyprexpo.expo("on")
        end
    end, { timeout = EXPO_HOLD_MS, type = "oneshot" })
end

if hl.plugin.hyprexpo ~= nil then
    hl.on("input.keyboard.key", function(keycode, _time, state)
        local is_super = SUPER_KEYCODES[keycode] == true
        if state == 0 then -- released
            if is_super then
                expo_hold.super_down = false
                expo_hold_close()
                expo_hold.suppressed = false
                -- Fly-through: al soltar SUPER confirmamos el tile elegido.
                if expo_fly_super_up then expo_fly_super_up() end
            end
        else -- pressed (1) o repeated (2)
            if is_super then
                if state == 1 then
                    -- Re-armar en cada press (idempotente): un release perdido
                    -- no deja el estado trabado.
                    expo_hold.super_down = true
                    expo_hold.suppressed = false
                    expo_hold_arm()
                end
            elseif expo_hold.super_down then
                -- Otra tecla con SUPER pulsado: es un atajo, no grilla.
                expo_hold.suppressed = true
                expo_hold_cancel_timer()
            end
        end
    end)

    -- Si la grilla se cierra por otra via (SUPER+Y, catchall, kb_confirm...) el
    -- submap sale de "hyprexpo": sincronizamos el estado para no cancelar de mas
    -- al soltar SUPER.
    hl.on("keybinds.submap", function(name)
        if name ~= "hyprexpo" then
            if expo_hold.open then expo_hold.open = false end
            if expo_fly and expo_fly.deliberate then expo_fly.deliberate = false end
        end
    end)
end

-- ========================
-- WINDOW RULES
-- ========================
-- Tiled no enfocadas: mas transparencia. Especificas despues (ganan), flotantes al final (opacas).
hl.window_rule({ match = { class = ".*" }, opacity = "0.95 0.75" })
hl.window_rule({ match = { class = "kitty" }, opacity = "0.90" })
hl.window_rule({ match = { class = "brave-browser" }, opacity = "0.88 0.82" })
hl.window_rule({ match = { float = true }, opacity = "1.0 1.0" })
hl.window_rule({ match = { class = "com.stremio.Stremio" }, idle_inhibit = "always" })
hl.window_rule({ match = { class = "com.moonlight_stream.Moonlight" }, workspace = "10" })
hl.window_rule({ match = { class = "com.moonlight_stream.Moonlight" }, fullscreen = 1 })
hl.window_rule({ match = { class = "leia" }, workspace = "10" })
hl.window_rule({ match = { class = "leia" }, fullscreen = 1 })
hl.window_rule({ match = { class = "libreoffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "soffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "Spotify" }, workspace = "9" })
hl.window_rule({ match = { class = "swayosd-server" }, float = 1 })
hl.window_rule({ match = { class = "swayosd-server" }, move = "1% 40%" })
hl.window_rule({ match = { class = "swayosd-server" }, size = "200 20" })
hl.window_rule({ match = { class = "swayosd-server" }, border_size = 0 })
-- Omarchy menu (replaces custom quickshell launcher)
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, max_size = "1260 560" })
if machine == "desktop" then
    hl.window_rule({ match = { class = "handy", title = "Recording" }, float = 1, no_initial_focus = 1, no_blur = 1, border_size = 0 })
end

-- Modo juegos: Cartridges fullscreen en workspace 10
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, workspace = "10" })
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, fullscreen = 1 })

-- Flotantes: tope de tamaño via clamp_float() en SUPER+D / media mode.
-- NO usar window_rule max_size global: afecta tiled y fuerza float al abrir.

-- ========================
-- WINDOW HELPERS (foco bajo cursor + media stack)
-- ========================
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

-- ========================
-- FOCO POR WORKSPACE (memoria gana)
-- follow_mouse sigue activo para el dia a dia, pero al cambiar de workspace
-- se restaura la ultima ventana usada en ese ws (mayor especificidad).
-- ========================
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
    -- Verificar que la ventana siga viva en ese ws antes de enfocar.
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

-- ========================
-- KEYBINDS: SYSTEM & APPS
-- ========================
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SPACE",  hl.dsp.exec_cmd("omarchy-menu toggle"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.local/bin/antigravity-ui.sh"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("firefox"))

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))
-- SUPER+F: fullscreen de la ventana bajo el cursor
hl.bind(mainMod .. " + F", function()
    focus_under_cursor()
    hl.dispatch(hl.dsp.window.fullscreen())
end)
-- SUPER+SHIFT+F: modo media (float + fullscreen) de la ventana bajo el cursor
hl.bind(mainMod .. " + SHIFT + F", function()
    focus_under_cursor()
    local w = hl.get_active_window()
    if w and not w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "set" }))
    end
    hl.dispatch(hl.dsp.window.fullscreen({ action = "set", mode = "fullscreen" }))
end)
-- SUPER+D: toggle float bajo el cursor (clamp size para no simular fullscreen)
hl.bind(mainMod .. " + D", function()
    focus_under_cursor()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    clamp_float(hl.get_active_window())
end)
-- SUPER+P: Beckon voice control (replaced pin — moved to SHIFT+P)
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("beckon"))

hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exit())

-- ========================
-- VOLUME (SwayOSD)
-- ========================
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 3%+ && swayosd-client --output-volume raise"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%- && swayosd-client --output-volume lower"), { repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && swayosd-client --output-volume mute-toggle"))

-- ========================
-- MEDIA KEYS
-- ========================
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- ========================
-- BRIGHTNESS (SwayOSD)
-- ========================
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set +3% && swayosd-client --brightness raise"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 3%- && swayosd-client --brightness lower"), { repeating = true })

-- ========================
-- SCREENSHOT (shot: wayfreeze + grim + slurp + wl-copy)
-- ========================
hl.bind("Print",           hl.dsp.exec_cmd("~/.local/bin/shot"))
hl.bind("SHIFT + Print",   hl.dsp.exec_cmd("~/.local/bin/shot full"))
hl.bind("CTRL + Print",    hl.dsp.exec_cmd("~/.local/bin/shot -s"))
hl.bind("CTRL + SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/shot -s full"))
hl.bind(mainMod .. " + Print",       hl.dsp.exec_cmd("~/.local/bin/shot active"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/shot -e"))

-- ========================
-- MOUSE BUTTONS
-- ========================
-- Atras (BTN_SIDE): copiar | Adelante (BTN_EXTRA): pegar
-- Rueda (mouse:274): Warp → Ctrl derecho mantenido | resto → Handy F7 (toggle)
hl.bind("mouse:275", hl.dsp.exec_cmd("wtype -M ctrl -M shift c -m shift -m ctrl"))
hl.bind("mouse:276", hl.dsp.exec_cmd("wtype -M ctrl -M shift v -m shift -m ctrl"))
hl.bind("mouse:274", hl.dsp.exec_cmd("~/.local/bin/middle-click.sh down"))
hl.bind("mouse:274", hl.dsp.exec_cmd("~/.local/bin/middle-click.sh up"), { release = true })

-- Handy (speech-to-text)
-- F7: transcribir SIEMPRE con post-procesado (prompt custom en Handy)
hl.bind("F7", hl.dsp.exec_cmd("handy --toggle-post-process"))

-- F5: activa/desactiva push de Notify de OpenCode al celular.
hl.bind("F5", hl.dsp.exec_cmd("~/.local/bin/notify-push-toggle.sh"))

-- ── Voz local (sistema voice, ver linux/voice + ~/.local/bin/voice) ──
-- Toggle TTS: activa/desactiva la voz (daemon + alertas de opencode).
-- El dictado se hace con Handy (F7); la voz solo habla respuestas.
-- Para cambiarla: bindear otra tecla a "~/.local/bin/voice tts toggle".
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("handy --toggle-post-process"))

-- Nota: el resumen de voz on-demand y su toggle NO usan keybinds (chocaban con
-- los workspaces V/SHIFT+V). Se manejan por comando: ver plugin voice de opencode.

-- OpenCode / TV toggle / Tema claro-oscuro
hl.bind("F8",  hl.dsp.exec_cmd("kitty --directory ~/dotfiles tmux new-session -A -s opencode opencode --agent dotfiles"))
hl.bind("F9",  hl.dsp.exec_cmd("~/.local/bin/tv-toggle.sh"))
hl.bind("F11", hl.dsp.exec_cmd("~/.local/bin/theme-toggle.sh toggle"))

if machine == "laptop" then
    hl.bind("F10", hl.dsp.exec_cmd("~/.local/bin/toggle-lid.sh"))
end

-- ========================
-- FOCUS (DVORAK-PROG layout)
-- ========================
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("omarchy-hyprland-window-pop"))
hl.bind(mainMod .. " + O", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + U", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + ntilde", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + E", hl.dsp.focus({ direction = "d" }))

-- SUPER+TAB / SUPER+SHIFT+TAB: ciclar ventanas; si hay par de flotantes
-- (media: Spotify+Netflix), la activa se re-fullscreen-ea al subirla.
hl.bind(mainMod .. " + TAB", function() cycle_media(true) end)
hl.bind(mainMod .. " + SHIFT + TAB", function() cycle_media(false) end)

-- ========================
-- MOVE WINDOWS
-- ========================
-- Flotantes: "movewindow" las teleporta al borde del monitor (abrupto).
-- Mejor: mover por pasos de px (glide). Tiled: swap normal.
local function move_window(dir, dx, dy)
    local w = hl.get_active_window()
    if w ~= nil and w.floating then
        hl.dispatch(hl.dsp.window.move({ x = dx, y = dy, relative = true }))
    else
        hl.dispatch(hl.dsp.window.move({ direction = dir }))
    end
end
hl.bind(mainMod .. " + SHIFT + O",      function() move_window("left",  -50, 0) end, { repeating = true })
hl.bind(mainMod .. " + SHIFT + U",      function() move_window("right",  50, 0) end, { repeating = true })
hl.bind(mainMod .. " + SHIFT + ntilde", function() move_window("up",     0, -50) end, { repeating = true })
hl.bind(mainMod .. " + SHIFT + E",      function() move_window("down",   0, 50) end, { repeating = true })

-- ========================
-- RESIZE
-- ========================
hl.bind(mainMod .. " + left",  hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + up",    hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
hl.bind(mainMod .. " + down",  hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })

-- ========================
-- WORKSPACES
-- ========================
-- Key-to-workspace mapping (DVORAK-PROG layout)
local ws_keys = { "M", "W", "V", "H", "T", "N", "G", "C", "R", "S" }

-- Fly-through (DENTRO de la grilla): con la grilla ABIERTA (SUPER+Y o
-- long-press SUPER), SUPER+# mueve el foco al tile # y hace zoom al desktop.
-- Fuera de la grilla, SUPER+# usa ws_travel (deslizamiento continuo, seccion
-- WORKSPACE TRAVEL), no esto. Solo tiles visibles (grilla 3x3 = 1..9).
-- Estado del fly-through. Guardamos aca las "posiciones": si la grilla esta
-- abierta (open), que tile tiene el foco (sel, indice de grilla 1..9 numpad) y
-- cual es el ultimo destino pedido (want). Mientras encadenas SUPER+# mantenemos
-- la grilla ABIERTA y solo MOVEMOS el foco (kb_focus), asi recalcular la direccion
-- es instantaneo y no se corta ninguna animacion.
--
-- Modos (EXPO_MODE):
--   "always3d" SIEMPRE morpha 3D: cada press abre la grilla y hace zoom
--              al tile. Si encadenas rapido, cada press espera a que termine el
--              morph anterior y reabre (cola) -> todo 3D, nunca un corte directo.
--   "hybrid"   como always3d, pero si encadenas durante el cierre cambia de
--              desktop al toque (corta el morph, maxima respuesta).
--   "release" (ACTIVO) el commit sucede al SOLTAR SUPER en las aperturas
--              DELIBERADAS (SUPER+Y / long-press / encadenar): mantienes SUPER,
--              la grilla queda abierta y cada SUPER+# re-apunta al instante;
--              al soltar cae al ultimo tile con un solo morph. Un SUPER+# DIRECTO
--              (grilla cerrada) aterriza rapido a EXPO_FLY_MS aunque sostengas SUPER.
--              EXPO_IDLE_MS es red de seguridad por si se pierde el release.
local EXPO_MODE        = "release"
local EXPO_POLL_MS     = 25
local EXPO_FLY_MS      = 90  -- grilla abierta antes de confirmar (da el 3D)
local EXPO_PEEK_ZOOM   = 2.65 -- zoom-out sutil: 1.0=grilla completa, 3.0=un tile ocupa todo (2.65 ~ deja ver bordes vecinos)
local EXPO_IDLE_MS     = 1200 -- release: red de seguridad si se pierde el release (alto para no aterrizar mientras sostienes SUPER)
local EXPO_CLOSE_TICKS = 17  -- ~425ms: morph de cierre (windowsMove=4) a esperar antes de reabrir
expo_fly = {
    open       = false, -- grilla abierta y navegable por nosotros
    sel        = nil,   -- tile con el foco actual (indice de grilla 1..9, numpad)
    want       = nil,   -- ultimo desktop pedido
    pending    = false, -- hay un want esperando a que termine el cierre anterior
    busy       = 0,     -- ticks restantes del morph de cierre
    poll       = nil,   -- timer de poll (solo corre si busy>0 o pending)
    commit     = nil,   -- oneshot de confirmacion por inactividad
    deliberate = false, -- grilla abierta a proposito (SUPER+Y / long-press / encadenado)
                        -- -> el commit espera al release; si es false (SUPER+# directo)
                        -- -> aterriza rapido aunque sostengas SUPER.
}

-- Indice del desktop n dentro de la grilla visible (top-left = 0).
-- Config: columns=3, rows=3, reverse_rows=1 -> orden numpad 789/456/123:
--   fila top 0 = 7,8,9 | fila 1 = 4,5,6 | fila 2 (bottom) = 1,2,3.
local function ws_grid_index(n)
    n = ((n - 1) % 9) + 1
    local col             = (n - 1) % 3
    local row_from_bottom = math.floor((n - 1) / 3)
    return (2 - row_from_bottom) * 3 + col
end

local fly_goto, fly_commit_now, fly_schedule_commit, fly_poll_step, ensure_poll, fly_open_and_go, fly_abort

-- Mueve el foco de la grilla hasta el desktop `target`. Cada kb_focus corre un
-- tile; calculamos el delta desde `sel` (estado guardado), asi encadenar destinos
-- es inmediato y siempre parte de la posicion real.
fly_goto = function(target)
    if not expo_fly.open then return end
    local t      = ws_grid_index(target)
    local sel    = expo_fly.sel or t
    local cx, cy = sel % 3, math.floor(sel / 3)
    local tx, ty = t % 3, math.floor(t / 3)
    local dirx   = tx > cx and "right" or "left"
    local diry   = ty > cy and "down" or "up"
    for _ = 1, math.abs(tx - cx) do hl.plugin.hyprexpo.kb_focus(dirx) end
    for _ = 1, math.abs(ty - cy) do hl.plugin.hyprexpo.kb_focus(diry) end
    expo_fly.sel = t
end

-- Confirma y dispara el zoom de entrada al tile elegido (commit inmediato).
fly_commit_now = function()
    if not expo_fly.open then return end
    if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
    if expo_fly.want then
        hl.plugin.hyprexpo.kb_selectn(expo_fly.want)
    else
        hl.plugin.hyprexpo.kb_confirm()
    end
    expo_fly.open       = false
    expo_fly.sel        = nil
    expo_fly.busy       = EXPO_CLOSE_TICKS
    expo_fly.deliberate = false
    ensure_poll()
end

fly_schedule_commit = function()
    if expo_fly.commit then expo_fly.commit:set_enabled(false) end
    -- Aterriza rapido SIEMPRE (aunque sostengas SUPER): el zoom-out del peek no
    -- debe quedarse pegado mientras cambias de desktop. Encadenar re-apunta el
    -- morph en vuelo (ver expo_focus), asi que no hace falta esperar al release.
    local delay = EXPO_FLY_MS
    expo_fly.commit = hl.timer(function()
        expo_fly.commit = nil
        fly_commit_now()
    end, { timeout = delay, type = "oneshot" })
end

-- Modo "release": al soltar SUPER confirmamos de inmediato. En "hybrid" el commit
-- ya lo dispara EXPO_FLY_MS, asi que soltar SUPER no hace nada.
expo_fly_super_up = function()
    -- Al soltar SUPER confirmamos lo que este pendiente (no-op si ya aterrizo).
    fly_commit_now()
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
            if n then fly_open_and_go(n) end
        end
    end
    -- Sin nada pendiente ni animacion de cierre, apagamos el poll.
    if not expo_fly.open and not expo_fly.pending and expo_fly.busy == 0 and expo_fly.poll then
        expo_fly.poll:set_enabled(false)
        expo_fly.poll = nil
    end
end

-- Abre la grilla y navega al destino n. El foco arranca en el desktop actual.
fly_open_and_go = function(n)
    local cur = hl.get_active_workspace()
    if hl.plugin.hyprexpo.peek then
        hl.plugin.hyprexpo.peek(EXPO_PEEK_ZOOM)
    else
        hl.plugin.hyprexpo.expo("on")
    end
    expo_fly.open = true
    expo_fly.sel  = cur and ws_grid_index(cur.id) or nil
    expo_fly.want = n
    fly_goto(n)
    fly_schedule_commit()
end

-- Cancela el fly-through y deja la grilla cerrandose (si estaba abierta).
fly_abort = function()
    if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
    expo_fly.pending    = false
    expo_fly.want       = nil
    expo_fly.deliberate = false
    if expo_fly.open then
        hl.plugin.hyprexpo.expo("cancel")
        expo_fly.open = false
        expo_fly.sel  = nil
        expo_fly.busy = EXPO_CLOSE_TICKS
        ensure_poll()
    end
end

-- SUPER+Y manual: resetea el estado del fly-through (para no quedar desincronizado
-- si la cerras a mano en medio de un viaje) y luego togglea la grilla. No usamos
-- fly_abort() porque dispararia "cancel" y el "toggle" la reabriria.
expo_ui_toggle = function()
    reset_ws_style()
    -- Pin del long-press: si la grilla la abrio mantener-SUPER y se pulsa
    -- SUPER+Y, transferir propiedad (no togglear, no cerrar al soltar).
    if expo_hold.open then
        expo_hold.open = false
        expo_hold.suppressed = true
        expo_hold_cancel_timer()
        expo_fly.deliberate = true
        return
    end
    -- SUPER+Y es una apertura deliberada de la grilla -> commit al release.
    expo_fly.deliberate = true
    local was_open = expo_fly.open
    if expo_fly.commit then expo_fly.commit:set_enabled(false); expo_fly.commit = nil end
    expo_fly.open    = false
    expo_fly.sel     = nil
    expo_fly.want    = nil
    expo_fly.pending = false
    hl.plugin.hyprexpo.expo("toggle")
    if was_open then
        expo_fly.busy = EXPO_CLOSE_TICKS
        ensure_poll()
    end
end

-- Expuesto a la barra de Omarchy (widget eztvn.grid): el boton llama
-- `hyprctl eval 'expo_ui_toggle()'`. Como expo_ui_toggle es un local del archivo,
-- publicamos una copia global para que el chunk de eval la alcance.
_G.expo_ui_toggle = expo_ui_toggle

-- Memoria de "desktop anterior" propia. Hyprland NO expone el previous en Lua y
-- el "previous" nativo no sirve: el fly-through hace un cambio interno (grilla ->
-- tile) que dejaria el destino como anterior, y changeWorkspace() fija el activo
-- de forma SINCRONA (cuando llega el evento, el previo ya se perdio). Guardamos
-- el ultimo desktop DISTINTO al actual.
local cur_ws_id  = nil
local last_ws_id = nil
-- Mientras un viaje continuo (ws_travel) pasa por desktops intermedios, el evento
-- workspace.active dispara por CADA tramo. Si dejaramos que note_ws corra, el
-- "desktop anterior" quedaria apuntando al ULTIMO intermedio y volver con la misma
-- tecla caeria en un desktop de paso (se perdia el camino). El viaje fija el
-- anterior en su ORIGEN (ver travel_stop).
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
    -- El zoom/peek convive con el leaf workspaces: lo dejamos SIEMPRE en horizontal
    -- para que el cambio de desktop interno del plugin (al cerrar) no herede un
    -- slidevert pegado de un viaje vertical anterior (se veia slide vertical
    -- donde debia ir el zoom horizontal).
    reset_ws_style()
    local has_expo = hl.plugin.hyprexpo ~= nil
    local cur      = hl.get_active_workspace()

    -- Laptop (plugin stock, sin parche): sin fly-through ni peek. Salto directo
    -- al desktop destino (o al anterior si pides el actual).
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

    -- Grilla abierta: recalcula al toque hacia el nuevo destino (sin cerrar).
    if expo_fly.open then
        expo_fly.want = i
        fly_goto(i)
        fly_schedule_commit()
        return
    end

    -- Cierre en curso (morph en vuelo). Va ANTES del chequeo "mismo desktop"
    -- porque changeWorkspace() del plugin es SINCRONO: al confirmar, el desktop
    -- activo ya cambio aunque el morph siga volando. Sin esto, pulsar el numero
    -- del desktop al que estamos yendo caeria en expo_fly_back (salto erratico).
    --   always3d -> retarget instantaneo: el plugin re-apunta la animacion al
    --               nuevo tile en caliente (kb_selectn sin guard de closing).
    --   hybrid   -> cambio directo (corta el morph: maxima respuesta).
    --   release  -> encola y reabre cuando termina.
    if expo_fly.busy > 0 then
        if cur and cur.id == i then
            return -- ya vamos a ese desktop; dejamos terminar el morph
        end
        -- El morph de cierre anterior esta en vuelo: lo REAPUNTAMOS al nuevo tile
        -- (retarget instantaneo del plugin) en vez de encolar una reapertura. Asi
        -- cambiar de desktop en rapido redirige el vuelo sin reabrir el zoom.
        -- Si el cierre ya termino (busy desfasado), peek reabre la grilla y el
        -- commit (EXPO_FLY_MS) confirma el destino.
        expo_fly.want = i
        expo_fly.open = true
        if hl.plugin.hyprexpo.peek then hl.plugin.hyprexpo.peek(EXPO_PEEK_ZOOM) end
        hl.plugin.hyprexpo.kb_selectn(i)
        expo_fly.busy = EXPO_CLOSE_TICKS
        fly_schedule_commit()
        ensure_poll()
        return
    end

    -- Grilla cerrada, mismo desktop: ir al anterior (si hay historial).
    if not expo_fly.pending and cur and cur.id == i then
        expo_fly_back()
        return
    end

    fly_open_and_go(i)
end

-- ========================
-- WORKSPACE TRAVEL (continuo, sin saltos)
-- ========================
-- SUPER+# NO abre la grilla en los movimientos de un solo eje: cambia de desktop
-- con un deslizamiento nativo (slidefade) para que las ventanas se "empujen" y se
-- sienta como un mismo espacio continuo. Si el destino esta lejos en el mismo eje,
-- se pasa por los desktops intermedios del grid 3x3 para que se vean las pantallas
-- de en medio. Los movimientos DIAGONALES (cambian de fila Y columna) si abren el
-- fly-through/overview del hyprexpo (el morfo de zoom "3D"), igual que SUPER+Y /
-- long-press SUPER.
local TRAVEL_SPEED = 4 -- duracion horizontal en decisegundos (4 = 400ms); el vertical se ajusta por aspecto
local TRAVEL_FADE_PCT = 100 -- recorrido del slidefade (100 = slide completo + fade)

local function ws_id_for_index(idx)
    idx = ((idx % 9) + 9) % 9
    local col             = idx % 3
    local row_from_top    = math.floor(idx / 3)
    local row_from_bottom = 2 - row_from_top
    return row_from_bottom * 3 + col + 1
end

-- Cambia el estilo del leaf workspaces segun la direccion del tramo.
-- Horizontal: "slide" (la direccion auto por id ya coincide con el grid).
-- Vertical: "slidevert" + token explicito, porque el id del grid crece hacia
-- ARRIBA (fila superior = 7,8,9), al reves que el eje Y de Hyprland. Sin el
-- token, subir se ve como bajar. `up` = el destino esta arriba del actual:
--   up   -> new entra desde arriba (left=false) -> "slidevert top"
--   down -> new entra desde abajo (left=true)  -> "slidevert bottom"
-- `linear` = tramo intermedio de un viaje largo: sin ease-out, para que la
-- velocidad sea constante y el intermedio se cruce "de largo" sin frenar.
local function set_ws_style(vertical, up, linear)
    -- slide + fade: el slide solo "empujaba" (se sentia brusco). slidefade desvanece
    -- el desktop saliente mientras entra el nuevo. TRAVEL_FADE_PCT controla cuanto
    -- se desliza (100 = slide completo con fade; menos = mas crossfade).
    local pct   = TRAVEL_FADE_PCT .. "%"
    local style = "slidefade " .. pct
    local speed = TRAVEL_SPEED
    if vertical then
        style = up and ("slidefadevert top " .. pct) or ("slidefadevert bottom " .. pct)
        -- Igualar la velocidad percibida (px/ms): el recorrido vertical es mas
        -- corto (alto < ancho), asi que dura menos para sentirse igual que el
        -- horizontal. speed = TRAVEL_SPEED * alto/ancho  (ej. 4*1440/2560 ~ 2.25)
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
    return math.floor(speed * 100) -- duracion del tramo en ms
end

-- Vuelve el leaf workspaces al estilo horizontal por defecto (el de la config).
-- Clave: set_ws_style muta un leaf GLOBAL que persiste. Si un tramo vertical lo
-- deja en slidevert, el SIGUIENTE cambio que no fije estilo (el close interno del
-- hyprexpo, grid-move, un click en la barra) hereda ese slidevert y se ve un slide
-- vertical donde deberia ir horizontal/zoom. Por eso lo restauramos siempre.
reset_ws_style = function()
    set_ws_style(false, false, false)
end

-- Revert diferido: deja correr la animacion del tramo (ya creada con su estilo) y
-- despues restaura el horizontal. Un solo timer; cada llamada reemplaza al previo.
local ws_style_timer = nil
local function ws_style_revert_after(ms)
    if ws_style_timer then ws_style_timer:set_enabled(false) end
    ws_style_timer = hl.timer(function()
        ws_style_timer = nil
        reset_ws_style()
    end, { timeout = ms, type = "oneshot" })
end

local travel = { steps = {}, timer = nil, linear = false, origin = nil }

-- Termina/reinicia un viaje. Fija el "desktop anterior" en el ORIGEN del viaje
-- (donde arranco), no en el ultimo intermedio: asi volver con la misma tecla
-- retrace el camino en vez de saltar a un desktop de paso.
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
    -- intermedios: velocidad constante (linear); ultimo: ease-out para aterrizar
    local dur    = set_ws_style(nxt.vertical, up, travel.linear and not isLast)
    hl.dispatch(hl.dsp.focus({ workspace = tostring(nxt.id) }))
    -- La animacion ya quedo creada con su estilo; restaura el horizontal cuando el
    -- tramo termine (cubre tambien el ultimo). El siguiente tramo reemplaza el timer.
    ws_style_revert_after(dur + 20)
    if isLast then
        travel_stop()
        return
    end
    -- Re-arma el siguiente tramo a mitad de vuelo del actual, con el intervalo
    -- ajustado a la duracion de ESTE eje (el vertical es mas corto).
    travel.timer = hl.timer(function()
        travel.timer = nil
        travel_step()
    end, { timeout = math.max(80, math.floor(dur * 0.5)), type = "oneshot" })
end

local function ws_travel(i)
    local cur = hl.get_active_workspace()

    -- Volver al desktop anterior: pedir el MISMO desktop en el que ya estas elige
    -- el ultimo desktop distinto (last_ws_id) como destino real. Lo tratamos como
    -- un viaje normal para que retrace el camino con la orientacion correcta (antes
    -- era un dispatch pelado: perdia el camino y, si venia de un tramo vertical,
    -- heredaba el slide horizontal -> direccion equivocada).
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

    -- Reconstruye el camino desde el desktop REAL actual (soporta encadenar).
    -- Si ya hay un viaje en curso, conservamos su ORIGEN para que "volver" apunte
    -- al primer desktop del viaje y no a un intermedio.
    local was_traveling = (travel.timer ~= nil) or (#travel.steps > 0)
    local keep_origin   = travel.origin
    travel_stop()
    local ci     = ws_grid_index(cur.id)
    local ti     = ws_grid_index(i)
    local c, r   = ci % 3, math.floor(ci / 3)
    local tc, tr = ti % 3, math.floor(ti / 3)

    -- Movimiento DIAGONAL: no es un tramo recto, asi que en vez del slide cae al
    -- fly-through/overview del hyprexpo (el morfo de zoom "3D" entre tiles no
    -- contiguos). Los movimientos de un solo eje (laterales) siguen con slidefade.
    if tc ~= c and tr ~= r then
        travel_stop() -- corta cualquier viaje en curso para que no compita con el morfo
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

    -- Viaje por slide nativo (sin hyprexpo/overview) para los tramos de un solo eje.
    -- Las diagonales ya retornaron arriba (expo_focus). Aqui solo quedan rectos:
    -- adyacente = 1 tramo; lejano = intermedios con velocidad constante.
    travel.steps  = steps
    travel.linear = #steps > 1 -- viaje largo: intermedios a velocidad constante
    travel.origin = (was_traveling and keep_origin) or cur.id
    ws_travel_guard = true
    travel_step() -- primer tramo inmediato (responsividad); re-arma los siguientes
end

for i = 1, 10 do
    hl.bind(mainMod .. " + " .. ws_keys[i], function() ws_travel(i) end)
    hl.bind(mainMod .. " + SHIFT + " .. ws_keys[i], hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Viaje hop-by-hop entre desktops: SUPER+ALT+flechas mueve a la celda vecina del
-- grid 3x3 (numpad 789/456/123) animando el recorrido por los intermedios via
-- ~/.local/bin/grid-move. No-op en los bordes (sin wrap).
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
        -- grid-move no fija estilo: lo hereda del leaf. Lo ponemos segun la
        -- direccion del vecino (arriba/abajo = slidevert) y lo restauramos despues
        -- para no dejar el slidevert pegado al siguiente cambio. Cortamos cualquier
        -- fly-through/viaje en curso para que no compitan.
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
hl.bind(mainMod .. " + ALT + left",  function() grid_travel("left")  end)
hl.bind(mainMod .. " + ALT + right", function() grid_travel("right") end)
hl.bind(mainMod .. " + ALT + up",    function() grid_travel("up")    end)
hl.bind(mainMod .. " + ALT + down",  function() grid_travel("down")  end)

-- ========================
-- MOONLIGHT MODE (Toggle)
-- ========================
hl.bind("CTRL + Delete", hl.dsp.exec_cmd("~/.local/bin/toggle_moonlight.sh"), { locked = true })

-- Passthrough submap
hl.define_submap("passthrough", function()
    hl.bind("CTRL + Delete", hl.dsp.exec_cmd("~/.local/bin/toggle_moonlight.sh"), { locked = true, submap_universal = true })
    hl.bind("catchall", hl.dsp.submap("reset"))
end)

-- Lock animation (slide windows off-screen on lock)
require("lock_anim")
