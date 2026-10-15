local variables = require("base.variables")
local helpers = require("windowhelpers")

local main_mod = variables.main_mod

hl.bind(main_mod .. " + RETURN", hl.dsp.exec_cmd(variables.terminal))
hl.bind(main_mod .. " + SHIFT + RETURN", hl.dsp.exec_cmd(variables.terminal .. " --class ssh-desktop --title \"SSH: desktop\" ~/.local/bin/ssh-desktop"))
hl.bind(main_mod .. " + SPACE",  hl.dsp.exec_cmd("omarchy-menu toggle"))
hl.bind(main_mod .. " + SHIFT + I", hl.dsp.exec_cmd("omarchy-launch-or-focus-tui \"~/.local/bin/investigaciones\""), { description = "Investigaciones (Logseq)" })
hl.bind(main_mod .. " + A", hl.dsp.exec_cmd("~/.local/bin/antigravity-ui.sh"))
hl.bind(main_mod .. " + Z", hl.dsp.exec_cmd("firefox"))

hl.bind(main_mod .. " + Q", hl.dsp.window.close())
hl.bind(main_mod .. " + L", hl.dsp.exec_cmd("omarchy-system-lock"))
hl.bind(main_mod .. " + F", function()
    helpers.focus_under_cursor()
    hl.dispatch(hl.dsp.window.fullscreen())
end)
hl.bind(main_mod .. " + SHIFT + F", function()
    helpers.focus_under_cursor()
    local w = hl.get_active_window()
    if w and not w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "set" }))
    end
    hl.dispatch(hl.dsp.window.fullscreen({ action = "set", mode = "fullscreen" }))
end)
hl.bind(main_mod .. " + D", function()
    helpers.focus_under_cursor()
    hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
    helpers.clamp_float(hl.get_active_window())
end)
hl.bind(main_mod .. " + SHIFT + D", hl.dsp.exec_cmd("~/.local/bin/hypr3d-toggle.sh"))
hl.bind(main_mod .. " + P", hl.dsp.exec_cmd("beckon"))

hl.bind(main_mod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(main_mod .. " + SHIFT + X", hl.dsp.exit())

-- Voz del sistema: repetir los últimos mensajes (voz + notificaciones).
hl.bind(main_mod .. " + ALT + V", hl.dsp.exec_cmd("~/.local/bin/voice repeat"))
hl.bind(main_mod .. " + ALT + SHIFT + V", hl.dsp.exec_cmd("~/.local/bin/voice repeat 3"))
-- Terminal nueva con pi (panel tmux + foco), desde el teclado.
hl.bind(main_mod .. " + ALT + RETURN", hl.dsp.exec_cmd("~/.local/bin/pi-new"), { description = "Terminal nueva con pi" })
-- Buzón de voz: escuchar los mensajes pendientes (SUPER+ALT+B).
hl.bind(main_mod .. " + ALT + B", hl.dsp.exec_cmd("~/.local/bin/voice play-inbox"))
-- OmniVoz ahora corre SIEMPRE (servicio omnivoz-listen). Se quitaron los
-- atajos que arrancaban una segunda instancia (peleaban por el micrófono y
-- abrían la píldora con foco exclusivo, trabando el teclado).
-- hl.bind(main_mod .. " + V", hl.dsp.exec_cmd("~/.local/bin/omnivoz-listen"))
-- hl.bind("F13", hl.dsp.exec_cmd("~/.local/bin/omnivoz-listen"))

-- Rescate de la píldora de Omar: cierra/reinicia y libera el teclado.
hl.bind(main_mod .. " + ALT + O", hl.dsp.exec_cmd("~/.local/bin/omar-pill-rescue"), { description = "Omar: rescatar teclado (reinicia píldora)" })
-- Alternativa push-to-talk explicita (deshabilitada: conflictúa con el servicio).
-- hl.bind(main_mod .. " + ALT + P", hl.dsp.exec_cmd("~/.local/bin/omnivoz listen --no-wake --once"))

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 3%+ && swayosd-client --output-volume raise"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%- && swayosd-client --output-volume lower"), { repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && swayosd-client --output-volume mute-toggle"))

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set +3% && swayosd-client --brightness raise"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 3%- && swayosd-client --brightness lower"), { repeating = true })

hl.bind("Print",           hl.dsp.exec_cmd("~/.local/bin/shot"))
hl.bind("SHIFT + Print",   hl.dsp.exec_cmd("~/.local/bin/shot full"))
hl.bind("CTRL + Print",    hl.dsp.exec_cmd("~/.local/bin/shot -s"))
hl.bind("CTRL + SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/shot -s full"))
hl.bind(main_mod .. " + Print",       hl.dsp.exec_cmd("~/.local/bin/shot active"))
hl.bind(main_mod .. " + SHIFT + Print", hl.dsp.exec_cmd("~/.local/bin/shot -e"))

hl.bind("mouse:275", hl.dsp.exec_cmd("wtype -M ctrl -M shift c -m shift -m ctrl"))
hl.bind("mouse:276", hl.dsp.exec_cmd("wtype -M ctrl -M shift v -m shift -m ctrl"))
hl.bind("mouse:274", hl.dsp.exec_cmd("~/.local/bin/middle-click.sh down"))
hl.bind("mouse:274", hl.dsp.exec_cmd("~/.local/bin/middle-click.sh up"), { release = true })

hl.bind("F7", hl.dsp.exec_cmd("handy --toggle-post-process"))

hl.bind("F5", hl.dsp.exec_cmd("~/.local/bin/notify-push-toggle.sh"))

hl.bind(main_mod .. " + I", hl.dsp.exec_cmd("handy --toggle-post-process"))

hl.bind("F8",  hl.dsp.exec_cmd("kitty --directory ~/dotfiles tmux new-session -A -s opencode opencode --agent dotfiles"))
hl.bind("F9",  hl.dsp.exec_cmd("~/.local/bin/tv-toggle.sh"))
hl.bind("F11", hl.dsp.exec_cmd("~/.local/bin/theme-toggle.sh toggle"))

hl.bind("F6", hl.dsp.exec_cmd(
    "omarchy-capture-screenrecording --stop-recording || omarchy-capture-screenrecording --fullscreen --with-desktop-audio"
), { description = "Grabar escritorio (toggle)" })

if variables.machine == "laptop" then
    hl.bind("F10", hl.dsp.exec_cmd("~/.local/bin/toggle-lid.sh"))
else
    hl.bind("F10", hl.dsp.exec_cmd(
        "omarchy-capture-screenrecording --stop-recording || omarchy-capture-screenrecording --fullscreen --with-desktop-audio"
    ), { description = "Grabar escritorio (toggle)" })
end

hl.bind(main_mod .. " + B", hl.dsp.exec_cmd("omarchy-hyprland-window-pop"))
hl.bind(main_mod .. " + O", hl.dsp.focus({ direction = "l" }))
hl.bind(main_mod .. " + U", hl.dsp.focus({ direction = "r" }))
hl.bind(main_mod .. " + ntilde", hl.dsp.focus({ direction = "u" }))
hl.bind(main_mod .. " + E", hl.dsp.focus({ direction = "d" }))

hl.bind(main_mod .. " + TAB", function() helpers.cycle_media(true) end)
hl.bind(main_mod .. " + SHIFT + TAB", function() helpers.cycle_media(false) end)

local function move_window(dir, dx, dy)
    local w = hl.get_active_window()
    if w ~= nil and w.floating then
        hl.dispatch(hl.dsp.window.move({ x = dx, y = dy, relative = true }))
    else
        hl.dispatch(hl.dsp.window.move({ direction = dir }))
    end
end
hl.bind(main_mod .. " + SHIFT + O",      function() move_window("left",  -50, 0) end, { repeating = true })
hl.bind(main_mod .. " + SHIFT + U",      function() move_window("right",  50, 0) end, { repeating = true })
hl.bind(main_mod .. " + SHIFT + ntilde", function() move_window("up",     0, -50) end, { repeating = true })
hl.bind(main_mod .. " + SHIFT + E",      function() move_window("down",   0, 50) end, { repeating = true })

hl.bind(main_mod .. " + left",  hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
hl.bind(main_mod .. " + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
hl.bind(main_mod .. " + up",    hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
hl.bind(main_mod .. " + down",  hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })

hl.bind(main_mod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.local/bin/ohm"), { description = "Ohm" })
hl.bind(main_mod .. " + SHIFT + Y", hl.dsp.exec_cmd("~/.local/bin/ohm https://youtube.com/"), { description = "Ohm: YouTube" })

return true
