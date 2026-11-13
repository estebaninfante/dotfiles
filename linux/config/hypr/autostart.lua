local variables = require("base.variables")
local theme = require("base.theme")

hl.on("hyprland.start", function()
    local source = "static"
    local handle = io.open(os.getenv("HOME") .. "/.config/wallpaper-source", "r")
    if handle then source = handle:read("*a"):match("^%s*(.-)%s*$"); handle:close() end
    if variables.machine == "laptop" then
        hl.exec_cmd("sleep 1 && hyprpaper --config " .. os.getenv("HOME") .. "/.config/hypr/hyprpaper-laptop.conf")
    elseif source == "video" then
        hl.exec_cmd("sleep 1 && systemctl --user start linux-wallpaperengine.service")
    else
        hl.exec_cmd("sleep 1 && hyprpaper --config " .. os.getenv("HOME") .. "/.config/hypr/hyprpaper.conf")
    end

    -- hyprpaper arranca con el fondo canonico: sync-wallpaper aplica enseguida el
    -- fondo propio por monitor (wallpaper-monitors.conf) a hyprpaper y al backdrop
    -- del overview, sin esperar al timer de 2 min ni abrir la grilla en el fondo
    -- de la otra pantalla. Solo laptop: el desktop puede estar en modo video.
    if variables.machine == "laptop" then
        hl.exec_cmd("sleep 3 && " .. os.getenv("HOME") .. "/.local/bin/sync-wallpaper.sh")
    end

    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start omarchy-shell.service")
    -- Suspensión por inactividad (10 min con batería, 30 min con corriente).
    -- Omarchy maneja screensaver/lock; hypridle solo suspende. Ver hypridle.conf.
    hl.exec_cmd("systemctl --user start hypridle.service")
    -- Portapapeles compartido con el otro equipo (texto, capturas, videos).
    hl.exec_cmd("systemctl --user start clipboard-sync.service")
    hl.exec_cmd("sleep 2 && systemctl --user start xdg-desktop-portal-hyprland && systemctl --user restart xdg-desktop-portal && systemctl --user start lan-mouse")

    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-" .. (theme.mode() == "light" and "light" or "dark") .. "'")
    hl.exec_cmd("urserver --daemon")

    if variables.machine == "laptop" then
        hl.exec_cmd("sleep 5 && libinput-gestures-setup start")
    end

    -- Cada pantalla arranca en su propio juego de espacios: laptop 1..9, vertical
    -- 28..36 (ver base/workspaces.lua). Antes había un `focus workspace 5` sin
    -- mirar la pantalla: si al arrancar el foco estaba en la vertical, el 5 se
    -- creaba ahí y la vertical quedaba mostrando un espacio de la laptop.
    hl.timer(function()
        local spaces = require("base.workspaces")
        local internal = nil
        for _, monitor in ipairs(hl.get_monitors()) do
            local name = monitor.name
            if name:match("^eDP") then internal = internal or monitor end
            if not name:match("^HEADLESS") and not name:match("^AGENTE") then
                local base = spaces.base_for(monitor)
                local active = monitor.active_workspace
                local id = active and active.id or nil
                local in_set = type(id) == "number" and id >= base and id < base + spaces.SET_SIZE
                if not in_set then
                    hl.dispatch(hl.dsp.focus({ monitor = name }))
                    hl.dispatch(hl.dsp.focus({ workspace = tostring(base) }))
                end
            end
        end
        if internal ~= nil then
            hl.dispatch(hl.dsp.focus({ monitor = internal.name }))
        end
        hl.dispatch(hl.dsp.focus({ workspace = "5" }))
    end, { timeout = 2500, type = "oneshot" })

    hl.exec_cmd("sleep 3 && hyprctl reload")
end)

return true
