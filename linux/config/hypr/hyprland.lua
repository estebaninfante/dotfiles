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
hl.env("GDK_SCALE", "2")
-- PREPEND ~/.local/bin al PATH existente (NO reemplazarlo).
-- En NixOS los binarios estan en /run/current-system/sw/bin — si
-- reemplazamos el PATH, Hyprland no encuentra kitty/waybar/rofi.
hl.env("PATH", os.getenv("HOME") .. "/.local/bin:" .. os.getenv("PATH"))

-- ========================
-- MONITORS
-- ========================
-- bgcolor=rgba(0,0,0,1) eliminates white flash before hyprpaper loads
if machine == "laptop" then
    hl.monitor({ output = "eDP-1",     mode = "2880x1800@120", position = "0x0",      scale = 2 })
    hl.monitor({ output = "HDMI-A-1",  mode = "2560x1440@144", position = "1440x-270", scale = 1 })
elseif machine == "desktop" then
    hl.monitor({ output = "DP-1",  mode = "2560x1440@144", position = "0x0", scale = 1 })
end

-- ========================
-- INPUT
-- ========================
hl.config({
    input = {
        kb_layout   = "dvk_prog",
        kb_variant  = "basic",
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
        ["col.active_border"]   = "rgba(00000000)",
        ["col.inactive_border"] = "rgba(00000000)"
    },
    decoration = {
        rounding = 10,
        blur = {
            enabled = true,
            size   = 10,
            passes = 3
        }
    },
    })

hl.layer_rule({
    match = { namespace = "swaync" },
    blur = true
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
hl.config({
    animations = {
        enabled = false
    }
})

-- ========================
-- DEVICE (touchpad) — laptop only
-- ========================
if machine == "laptop" then
    hl.device({
        name    = "elan06fa:00-04f3:3280-touchpad",
        enabled = true
    })
end

-- ========================
-- AUTO-START (optimized order)
-- ========================
hl.on("hyprland.start", function()
    -- 1. Wallpaper immediately (first visual priority)
    hl.exec_cmd("hyprpaper --config ~/.config/hypr/hyprpaper-" .. machine .. ".conf")

    -- 2. Bar and UI
    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")

    -- 3. D-Bus environment and portals
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("/usr/libexec/xdg-desktop-portal-hyprland & /usr/libexec/xdg-desktop-portal &")

    -- 4. Background services
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    hl.exec_cmd("/usr/libexec/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
    hl.exec_cmd("urserver --daemon")
    hl.exec_cmd("swayosd-server --top-margin=0.4")
    hl.exec_cmd("sleep 5 && handy --start-hidden")
    hl.exec_cmd("lan-mouse daemon")

    if machine == "laptop" then
        hl.exec_cmd("sleep 5 && libinput-gestures-setup start")
    end
end)

-- ========================
-- WINDOW RULES
-- ========================
hl.window_rule({ match = { class = "kitty" }, opacity = "0.8 0.8" })
hl.window_rule({ match = { class = "com.moonlight_stream.Moonlight" }, workspace = "10" })
hl.window_rule({ match = { class = "com.moonlight_stream.Moonlight" }, fullscreen = 1 })
hl.window_rule({ match = { class = "libreoffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "soffice.*" }, workspace = "empty" })
hl.window_rule({ match = { class = "swayosd-server" }, float = 1 })
hl.window_rule({ match = { class = "swayosd-server" }, move = "1% 40%" })
hl.window_rule({ match = { class = "swayosd-server" }, size = "200 20" })
hl.window_rule({ match = { class = "swayosd-server" }, border_size = 0 })

-- ========================
-- KEYBINDS: SYSTEM & APPS
-- ========================
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SPACE",  hl.dsp.exec_cmd("rofi -show combi -modi \"combi,drun,Archivos:~/.local/bin/rofi-file-search.sh,Scripts:~/.local/bin/rofi-scripts-launcher.sh\" -combi-modes \"drun,Archivos,Scripts\" -show-icons"))
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("rofi -show Archivos -modi \"Archivos:~/.local/bin/rofi-file-search.sh\""))
hl.bind(mainMod .. " + ALT + SPACE",   hl.dsp.exec_cmd("rofi -show Scripts -modi \"Scripts:~/.local/bin/rofi-scripts-launcher.sh\""))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.local/bin/antigravity-ui.sh"))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("firefox"))

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + D", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + B", hl.dsp.focus({ workspace = "special" }))

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

-- Handy (speech-to-text)
hl.bind("F7", hl.dsp.exec_cmd("handy --toggle-transcription"))

-- OpenCode / TV toggle
hl.bind("F8",  hl.dsp.exec_cmd("kitty --directory ~/dotfiles -e ~/.opencode/bin/opencode"))
hl.bind("F9",  hl.dsp.exec_cmd("~/.local/bin/tv-toggle.sh"))

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
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + U", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + ntilde", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.window.move({ direction = "down" }))

-- ========================
-- RESIZE
-- ========================
hl.bind(mainMod .. " + left",  hl.dsp.window.resize({ x = -20, y = 0, relative = true }))
hl.bind(mainMod .. " + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }))
hl.bind(mainMod .. " + up",    hl.dsp.window.resize({ x = 0, y = -20, relative = true }))
hl.bind(mainMod .. " + down",  hl.dsp.window.resize({ x = 0, y = 20, relative = true }))

-- ========================
-- WORKSPACES
-- ========================
-- Key-to-workspace mapping (DVORAK-PROG layout)
local ws_keys = { "M", "W", "V", "H", "T", "N", "G", "C", "R", "S" }
for i = 1, 10 do
    hl.bind(mainMod .. " + " .. ws_keys[i], hl.dsp.focus({ workspace = tostring(i) }))
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