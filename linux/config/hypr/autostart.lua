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

    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP ELECTRON_OZONE_PLATFORM_HINT GDK_SCALE HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start omarchy-shell.service")
    -- Suspensión por inactividad (10 min con batería, 30 min con corriente).
    -- Omarchy maneja screensaver/lock; hypridle solo suspende. Ver hypridle.conf.
    hl.exec_cmd("systemctl --user start hypridle.service")
    hl.exec_cmd("sleep 2 && systemctl --user start xdg-desktop-portal-hyprland && systemctl --user restart xdg-desktop-portal && systemctl --user start lan-mouse")

    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("dbus-update-activation-environment --systemd SSH_AUTH_SOCK")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-" .. (theme.mode() == "light" and "light" or "dark") .. "'")
    hl.exec_cmd("urserver --daemon")

    if variables.machine == "laptop" then
        hl.exec_cmd("sleep 5 && libinput-gestures-setup start")
    end

    hl.dsp.focus({ workspace = 5 })

    hl.exec_cmd("sleep 3 && hyprctl reload")
end)

return true
