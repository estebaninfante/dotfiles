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
-- APPEARANCE (LOOK & FEEL)
-- ========================
hl.config({
    general = {
        gaps_in        = 8,
        gaps_out       = 12,
        border_size    = 0,
        ["col.active_border"]   = "rgba(255, 0, 0, 0.5)",
        ["col.inactive_border"] = "rgba(00000000)"
    },
    decoration = {
        rounding = 10,
        blur = {
            enabled = true,
            size   = 8,
            passes = 3
        }
    }
})

-- ========================
-- GAPS DINAMICOS POR Nº DE VENTANAS
-- ========================
-- A menos ventanas en el workspace activo, mas aire; a mas ventanas, menos,
-- con caida tipo polinomio: gap(n) = MIN + (MAX - MIN) / n^DECAY.
-- Tunear aqui:
local GAP_IN_MAX,  GAP_IN_MIN  = 16, 4    -- separacion entre tiles
local GAP_OUT_MAX, GAP_OUT_MIN = 44, 8    -- margen alrededor de la grilla
local GAP_DECAY                = 2        -- exponente: mayor = cae mas rapido

local function gaps_for(n)
    n = math.max(1, n)
    local inv = 1 / (n ^ GAP_DECAY)
    local gi  = math.floor(GAP_IN_MIN  + (GAP_IN_MAX  - GAP_IN_MIN)  * inv + 0.5)
    local go  = math.floor(GAP_OUT_MIN + (GAP_OUT_MAX - GAP_OUT_MIN) * inv + 0.5)
    return gi, go
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

-- windowsMove: glide suave al mover flotantes por teclado Y el morph 3D de la
-- grilla expo (abrir/cerrar = zoom). Curva sin rebote y mas lento para que el
-- viaje se sienta tridimensional y no un parpadeo.
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 8,
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


-- Carrusel de workspaces: al saltar ws1→ws5 desliza por los intermedios.
-- slidefade = deslizamiento + fundido: se nota menos el corte que el slide puro
-- (mas suave, menos brusco). El % es cuanto funde.
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 10,
    bezier = "expoSmooth",
    style = "slidefade 20%"
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

-- Layers (waybar, swaync, omarchy shell): apertura con popin
-- rápido. Rofi es un layer → sin esto abre instantáneo sin animación.
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 1,
    bezier = "default",
    style = "popin"
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
    gaps_in       = 0,        -- separacion entre tiles (0 = pegados)
    gaps_out      = 0,        -- margen alrededor de la grilla (0 = sin margen)
    border_width  = 0,        -- grosor del borde de cada tile (0 = sin borde)
    tile_rounding = 0,        -- esquinas redondeadas de los tiles (0 = cuadradas)
    bg_col         = theme_color("darker_background", "#0e160e"),
    border_current = theme_color("accent", "#7aba7c"),
    border_focus   = theme_color("cyan", "#6aca9a"),
    border_hover   = theme_color("muted", "#6a8a6c"),
}

if hl.plugin.hyprexpo ~= nil then
    hl.config({
        plugin = {
            hyprexpo = {
                columns = 3,
                rows = 3,
                dynamic_grid = 0,
                skip_empty = 0,
                max_workspace = 9,
                reverse_rows = 1,
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
            },
        },
    })
end

hl.bind(mainMod .. " + Y", function()
    hl.plugin.hyprexpo.expo("toggle")
end)

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
        hl.bind(mainMod .. " + Y", function() hl.plugin.hyprexpo.expo("toggle") end)
        -- Replica de los binds globales SUPER+<ws>: con la grilla abierta,
        -- SUPER+<n> salta al desktop n (fly-through).
        local ws_keys = { "M", "W", "V", "H", "T", "N", "G", "C", "R", "S" }
        for i = 1, 10 do
            hl.bind(mainMod .. " + " .. ws_keys[i], function() hl.plugin.hyprexpo.kb_selectn(i) end)
        end
        hl.bind("catchall", function() hl.dispatch(hl.dsp.submap("reset")) end)
    end)
end

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
            expo_hold.open = true
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
        if name ~= "hyprexpo" and expo_hold.open then
            expo_hold.open = false
        end
    end)
end

-- ========================
-- WINDOW RULES
-- ========================
hl.window_rule({ match = { class = "kitty" }, opacity = "0.90" })
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

-- Fly-through: SUPER+# abre la grilla y hace zoom al desktop #, para que el
-- cambio de desktop se sienta tridimensional (morph abrir grilla -> entrar al tile).
-- Solo para tiles visibles (grilla 3x3 = 1..9); ws 10 cae a focus normal.
-- Interrumpible: si apretas otro SUPER+# durante la animacion, el ultimo gana
-- (se reintenta hasta llegar, asi no queda pegado en el desktop anterior).
-- EXPO_FLY_MS = cuanto espera antes de entrar al tile (deja ver la grilla 3D).
-- Cerca de la duracion de windowsMove (800ms) = la grilla se forma casi del todo
-- antes del zoom de entrada. El morph en si sigue la curva "expoSmooth".
local EXPO_FLY_MS  = 600
local EXPO_POLL_MS = 25
local EXPO_FLY_MAX = 160 -- ticks de seguridad (~4s) para no reintentar sin fin
local expo_fly = { want = false, opened = false, ticks = 0, age = 0, timer = nil }

local function expo_fly_stop()
    if expo_fly.timer then
        expo_fly.timer:set_enabled(false)
        expo_fly.timer = nil
    end
    expo_fly.want   = false
    expo_fly.opened = false
    expo_fly.ticks  = 0
    expo_fly.age    = 0
end

local function expo_fly_step()
    local want = expo_fly.want
    local opened = expo_fly.opened
    if not want then
        expo_fly_stop()
        return
    end

    expo_fly.age = expo_fly.age + 1
    if expo_fly.age > EXPO_FLY_MAX then
        local target = want
        expo_fly_stop()
        hl.plugin.hyprexpo.expo("cancel")
        hl.dispatch(hl.dsp.focus({ workspace = tostring(target) }))
        return
    end

    -- Solo cortar cuando el destino quedo asentado: si ya abrimos la grilla,
    -- changeWorkspace() fija el activo de forma SINCRONA y un corte prematuro
    -- dejaria el overview a medio cerrar (state colgado en g_overviews).
    local cur = hl.get_active_workspace()
    if cur and cur.id == want and opened then
        expo_fly_stop()
        return
    end

    if not expo_fly.opened then
        hl.plugin.hyprexpo.expo("on")
        expo_fly.opened = true
        expo_fly.ticks  = math.max(1, math.floor(EXPO_FLY_MS / EXPO_POLL_MS))
        return
    end

    if expo_fly.ticks > 0 then
        expo_fly.ticks = expo_fly.ticks - 1
        return
    end

    -- expo("on") es idempotente y kb_selectn se ignora mientras la grilla se
    -- esta cerrando; el siguiente tick reintenta, por eso el ultimo destino gana.
    hl.plugin.hyprexpo.expo("on")
    hl.plugin.hyprexpo.kb_selectn(want)
end

local function expo_fly_start(i)
    if expo_fly.want == i and expo_fly.timer then
        return
    end
    expo_fly.want   = i
    expo_fly.opened = false
    expo_fly.ticks  = 0
    expo_fly.age    = 0
    if not expo_fly.timer then
        expo_fly.timer = hl.timer(expo_fly_step, { timeout = EXPO_POLL_MS, type = "repeat" })
    end
end

-- Memoria de "desktop anterior" propia. Hyprland NO expone el previous en Lua y
-- el "previous" nativo no sirve: el fly-through hace un cambio interno (grilla ->
-- tile) que dejaria el destino como anterior, y changeWorkspace() fija el activo
-- de forma SINCRONA (cuando llega el evento, el previo ya se perdio). Guardamos
-- el ultimo desktop DISTINTO al actual.
local cur_ws_id  = nil
local last_ws_id = nil
local function note_ws()
    local w = hl.get_active_workspace()
    if not w then return end
    if w.id ~= cur_ws_id then
        if cur_ws_id ~= nil then
            last_ws_id = cur_ws_id
        end
        cur_ws_id = w.id
    end
end
note_ws()
hl.on("workspace.active", note_ws)

local function expo_fly_back()
    local target = last_ws_id or (hl.get_active_workspace() and hl.get_active_workspace().id)
    if not target then
        return
    end
    expo_fly_stop()
    if hl.plugin.hyprexpo ~= nil then
        -- Mismo morph que el resto: abre la grilla y entra al desktop anterior.
        hl.plugin.hyprexpo.expo("on")
        hl.timer(function()
            hl.plugin.hyprexpo.kb_selectn(target)
        end, { timeout = EXPO_FLY_MS, type = "oneshot" })
    else
        hl.dispatch(hl.dsp.focus({ workspace = tostring(target) }))
    end
end

local expo_focus = function(i)
    local has_expo = hl.plugin.hyprexpo ~= nil
    if not has_expo or i > 9 then
        expo_fly_stop()
        local cur  = hl.get_active_workspace()
        local same = cur and cur.id == i
        hl.dispatch(hl.dsp.focus({ workspace = same and "previous" or tostring(i) }))
        return
    end

    local cur = hl.get_active_workspace()
    if not expo_fly.timer and cur and cur.id == i then
        expo_fly_back()
        return
    end

    expo_fly_start(i)
end

for i = 1, 10 do
    hl.bind(mainMod .. " + " .. ws_keys[i], function() expo_focus(i) end)
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
        hl.dispatch(hl.dsp.exec_cmd("~/.local/bin/grid-move " .. target))
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
