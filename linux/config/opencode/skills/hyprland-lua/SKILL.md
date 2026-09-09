---
name: hyprland-lua
description: Guide for configuring Hyprland in Lua mode (≥0.55). Covers migration from hyprlang, Lua core configuration via hl module, bind dispatchers, dynamic rules, timers, and advanced event hooks.
---

# Hyprland Lua Skill

## Migration (hyprlang -> Lua)
- Since Hyprland 0.55, hyprlang deprecated in favor of Lua config: `$XDG_CONFIG_HOME/hypr/hyprland.lua`.
- Use `hl.config(section.key)` for value expansion instead of `${section:key}`.
- Bind logic moves into Lua functions; complex scripting can live in `*.lua` files under Hypr config.
- LSP stubs shipped in repo `meta/`; installed at `/usr/share/hypr/stubs/`.

## Core Configuration Basics
- `monitor` / `input` / `general` etc. configured via table passed to `hl.config(key)`.
- Example:
  ```lua
  local monitors = hl.config("monitor")
  -- or using explicit key: hl.config("input:touchdevice:enabled")
  ```

## Programs & Autostart
- Define reusable variables:
  ```lua
  local terminal    = "kitty"
  local fileManager = "dolphin"
  local menu        = "hyprlauncher"
  ```
- Autostart via event hook:
  ```lua
  hl.on("hyprland.start", function()
      hl.exec_cmd(terminal)
      hl.exec_cmd("nm-applet")
      hl.exec_cmd("waybar & hyprpaper & firefox")
  end)
  ```

## Environment Variables
```lua
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
```

## Keybinds & Dispatchers
- Bind to exec command:
  ```lua
  hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
  ```
- Close window:
  ```lua
  hl.bind(mainMod .. " + C", hl.dsp.window.close())
  ```
- Float toggle:
  ```lua
  hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
  ```
- Pseudo tiling:
  ```lua
  hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
  ```
- Layout toggle (dwindle only):
  ```lua
  hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
  ```

## Focus & Workspace Navigation
- Focus direction:
  ```lua
  hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
  hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
  hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
  hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
  ```
- Switch workspace:
  ```lua
  for i = 1, 10 do
      local key = i % 10
      hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  end
  ```
- Move window to workspace:
  ```lua
  for i = 1, 10 do
      local key = i % 10
      hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
  end
  ```

## Special Workspaces (scratchpad)
```lua
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
```

## Mouse Bindings
- Scroll workspaces:
  ```lua
  hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
  hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
  ```
- Move/resize windows with drag:
  ```lua
  hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
  hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
  ```

## Multimedia & Laptop Keys
```lua
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })
```

## Advanced Lua Scripting
- Timer usage:
  ```lua
  hl.timer(1000, function() print("tick") end)
  ```
- Event hook example:
  ```lua
  hl.on("hyprland.start", function()
      hl.exec_cmd(terminal)
  end)
  ```
- Dispatching advanced actions:
  ```lua
  hl.dsp.exec_cmd("somecommand")
  ```

## Window Rules & Dynamic Toggles
- Named rule toggling via Lua:
  ```lua
  hl.bind("SUPER + r", function()
      local rules = hl.config("windowrule")
      if rules then
          rules:add({ rule = "float", class = "^(kitty)$" })
      end
  end)
  ```
- Anonymous rule toggle (read state then dispatch):
  ```lua
  local floating = hl.config("windowrulev2") and hl.config("windowrulev2"):find(...)
  ```

## Convenience Functions
- `hl.bind(key, callback, opts)` — keybind with description and flags
- `hl.exec_cmd(cmd)` — run shell command
- `hl.timer(ms, callback)` — repeating timer
- `hl.on(event, callback)` — event hook
- `hl.get_active_window()` — returns {address, title, class, ...}
- `hl.get_config(key)` — returns current config value (read-only helper)

## Dispatcher Objects
- `hl.dsp.exec_cmd(cmd)` — execute command
- `hl.dsp.window.close()` — close active window
- `hl.dsp.window.float({ action = "toggle" })` — toggle floating
- `hl.dsp.window.pseudo()` — pseudo tiling
- `hl.dsp.window.drag()` — start window drag
- `hl.dsp.window.resize()` — start window resize
- `hl.dsp.window.move({ workspace = n })` — move to workspace
- `hl.dsp.focus({ direction = "left/right/up/down" })` — focus direction
- `hl.dsp.focus({ workspace = n })` — switch workspace
- `hl.dsp.layout("togglesplit")` — toggle split (dwindle)
- `hl.dsp.workspace.toggle_special("name")` — toggle scratchpad

## Tips
- Prefer `hl.bind(...)` for keybind logic; allows full Lua closures.
- Use `hl.config(...)` to read or set config values at runtime.
- Keep logic modular: split complex binds/functions into separate `.lua` files under Hypr config dir.
- Use `hl.dsp.window.float(...)` for advanced dispatching.

## References
- https://wiki.hypr.land/0.55.0/Configuring/Start
- https://wiki.hypr.land/configuring/core/advanced-configuration/lua-utilities/
- https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua
