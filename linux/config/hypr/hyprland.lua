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
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- GDK_SCALE debe coincidir con la escala del monitor principal:
-- laptop eDP-1 scale=2, desktop DP-1 scale=1. Mismatch → GTK apps 2x.
if machine == "desktop" then
    hl.env("GDK_SCALE", "1")
else
    hl.env("GDK_SCALE", "2")
end
-- PREPEND ~/.local/bin al PATH existente (NO reemplazarlo).
-- En NixOS los binarios estan en /run/current-system/sw/bin — si
-- reemplazamos el PATH, Hyprland no encuentra kitty/waybar/quickshell.
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
    hl.monitor({ output = "HDMI-A-1",  mode = "2560x1440@144", position = "1440x-270", scale = 1 })
elseif machine == "desktop" then
    hl.monitor({ output = "DP-2",  mode = "2560x1440@144", position = "0x0", scale = 1 })
end

-- ========================
-- INPUT
-- ========================
hl.config({
    input = {
        kb_layout   = "dvk_prog,es,us",
        kb_variant  = "basic,,",
        follow_mouse = 1,
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
            size   = 10,
            passes = 3
        }
    }
})

hl.layer_rule({
    match = { namespace = "swaync" },
    blur = true
})

-- Blur gaussiano detrás de la barra quickshell (fondo translúcido).
-- La barra usa `color: "transparent"` + fondo rgba(0,0,0,0.6); Hyprland
-- difumina el escritorio que queda detrás → efecto cristal esmerilado.
hl.layer_rule({
    match = { namespace = "quickshell" },
    blur = true
})

-- Blur detrás del launcher: es un PopupWindow de quickshell, cubierto por el
-- layer_rule de namespace "quickshell" de arriba.

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
hl.animation({
    leaf = "global",
    enabled = false
})

-- Solo el movimiento se anima (glide suave al mover flotantes por teclado);
-- el resto de animaciones sigue desactivado.
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "default"
})

-- windowsMove tambien anima los drags manuales (mouse) → se sienten
-- lentos/trabados. Los drags del raton siguen instantaneos, solo el
-- movimiento por teclado conserva el glide.
hl.config({
    misc = {
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        force_default_wallpaper = -1,
        disable_hyprland_logo = true
    }
})


-- Carrusel de workspaces: al saltar ws1→ws5 desliza por los intermedios.
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 2,
    bezier = "default",
    style = "slide"
})

-- Apertura "TV viejo": bloom casi instantaneo desde 10% (snap on).
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4,
    bezier = "default",
    style = "popin 10%"
})

-- Cierre: colapso inverso (popin reproducido en reversa).
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 8,
    bezier = "default",
    style = "popin 10%"
})

-- Layers (waybar, swaync, quickshell): apertura con popin
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

    -- 2. Bar and UI (quickshell via systemd user service)
    hl.exec_cmd("swaync")

    -- 3. D-Bus environment and portals
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- Los paths /usr/libexec no existen en NixOS (store). Arrancar via
    -- systemd da a la unit el env (WAYLAND_DISPLAY) que necesita su condicion.
    hl.exec_cmd("sleep 2 && systemctl --user start xdg-desktop-portal-hyprland && systemctl --user restart xdg-desktop-portal && systemctl --user start lan-mouse")

    -- 4. Background services
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    -- polkit agent: hyprpolkitagent (unit systemd user, ver home.nix)
    -- (antes: /usr/libexec/polkit-gnome-authentication-agent-1, path
    --  inexistente en NixOS → fprintd-enroll denegaba por falta de agente)
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
    hl.exec_cmd("hyprctl dispatch workspace 5")
end)

-- ========================
-- WINDOW RULES
-- ========================
hl.window_rule({ match = { class = "kitty" }, opacity = "1 1" })
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
-- File chooser portal (GTK): ventana de selección de archivos un poco menos alta
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, max_size = "1260 560" })
-- Handy fallback overlay is a normal window on desktop NVIDIA. Keep it
-- visible without changing the target application's focus or blur state.
if machine == "desktop" then
    hl.window_rule({ match = { class = "handy", title = "Recording" }, float = 1, no_initial_focus = 1, no_blur = 1, border_size = 0 })
end

-- Modo juegos: Cartridges fullscreen en workspace 10
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, workspace = "10" })
hl.window_rule({ match = { class = ".*[Cc]artridges.*" }, fullscreen = 1 })

-- ========================
-- KEYBINDS: SYSTEM & APPS
-- ========================
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SPACE",  hl.dsp.exec_cmd("~/.local/bin/qs-launcher.sh apps"))
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("~/.local/bin/qs-launcher.sh files"))
hl.bind(mainMod .. " + ALT + SPACE",   hl.dsp.exec_cmd("~/.local/bin/qs-launcher.sh scripts"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.local/bin/antigravity-ui.sh"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("firefox"))

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + D", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pin())

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
-- SCREENSHOT (shot: grim + slurp + wl-copy)
-- ========================
hl.bind("Print",           hl.dsp.exec_cmd("bash -c '~/.local/bin/shot'"))
hl.bind("SHIFT + Print",   hl.dsp.exec_cmd("bash -c '~/.local/bin/shot full'"))
hl.bind("CTRL + Print",    hl.dsp.exec_cmd("bash -c '~/.local/bin/shot -s'"))
hl.bind("CTRL + SHIFT + Print", hl.dsp.exec_cmd("bash -c '~/.local/bin/shot -s full'"))
hl.bind(mainMod .. " + Print",       hl.dsp.exec_cmd("bash -c '~/.local/bin/shot active'"))
hl.bind(mainMod .. " + SHIFT + Print", hl.dsp.exec_cmd("bash -c '~/.local/bin/shot -e'"))

-- ========================
-- MOUSE BUTTONS
-- ========================
-- Atras (BTN_SIDE): copiar | Adelante (BTN_EXTRA): pegar
-- Rueda (mouse:274): Warp → Ctrl derecho mantenido | resto → Handy F7 (toggle)
hl.bind("mouse:275", hl.dsp.exec_cmd("wtype -M ctrl c -m ctrl"))
hl.bind("mouse:276", hl.dsp.exec_cmd("wtype -M ctrl v -m ctrl"))
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
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("~/.local/bin/voice tts toggle"))

-- OpenCode / TV toggle / Tema claro-oscuro
hl.bind("F8",  hl.dsp.exec_cmd("kitty --directory ~/dotfiles tmux new-session -A -s opencode ~/.opencode/bin/opencode"))
hl.bind("F9",  hl.dsp.exec_cmd("~/.local/bin/tv-toggle.sh"))
hl.bind("F11", hl.dsp.exec_cmd("~/.local/bin/theme-toggle.sh toggle"))

if machine == "laptop" then
    hl.bind("F10", hl.dsp.exec_cmd("~/.local/bin/toggle-lid.sh"))
end

-- ========================
-- FOCUS (DVORAK-PROG layout)
-- ========================
hl.bind(mainMod .. " + O", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + U", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + ntilde", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + E", hl.dsp.focus({ direction = "d" }))

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
hl.bind(mainMod .. " + SHIFT + O",      function() move_window("left",  -50, 0) end)
hl.bind(mainMod .. " + SHIFT + U",      function() move_window("right",  50, 0) end)
hl.bind(mainMod .. " + SHIFT + ntilde", function() move_window("up",     0, -50) end)
hl.bind(mainMod .. " + SHIFT + E",      function() move_window("down",   0, 50) end)

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
for i = 1, 10 do
    hl.bind(mainMod .. " + " .. ws_keys[i], function()
        local ws = hl.get_active_workspace()
        if ws and ws.id == i then
            hl.dispatch(hl.dsp.focus({ workspace = "previous" }))
        else
            hl.dispatch(hl.dsp.focus({ workspace = tostring(i) }))
        end
    end)
    hl.bind(mainMod .. " + SHIFT + " .. ws_keys[i], hl.dsp.window.move({ workspace = tostring(i) }))
end

-- ========================
-- MOONLIGHT MODE (Toggle)
-- ========================
hl.bind("CTRL + Delete", hl.dsp.exec_cmd("~/.local/bin/toggle_moonlight.sh"), { locked = true })

-- Passthrough submap
hl.define_submap("passthrough", function()
    hl.bind("CTRL + Delete", hl.dsp.exec_cmd("~/.local/bin/toggle_moonlight.sh"), { locked = true, submap_universal = true })
    hl.bind("catchall", hl.dsp.submap("reset"))
end)
