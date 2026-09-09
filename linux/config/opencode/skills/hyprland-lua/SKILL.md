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
- Dynamic bind example:
  ```lua
  hl.bind("SUPER, Return", function()
      hl.exec_cmd(terminal)
  end, { description = "Terminal" })
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

## Dynamic Rules & Bind Dispatchers
- Use bind dispatcher to switch layouts dynamically:
  ```lua
  hl.bind("SUPER, Space", function()
      hl.config("general:layout", "dwindle")
  end)
  ```
- Advanced rule toggling via Lua:
  ```lua
  hl.bind("SUPER, r", function()
      hl.config("windowrule", { "float", "class:^(kitty)$" })
  end)
  ```

## Tips
- Prefer `hl.bind(...)` for keybind logic; allows full Lua closures.
- Use `hl.config(...)` to read or set config values at runtime.
- Keep logic modular: split complex binds/functions into separate `.lua` files under Hypr config dir.

## References
- https://wiki.hypr.land/0.55.0/Configuring/Start
- https://wiki.hypr.land/configuring/core/advanced-configuration/lua-utilities/
- https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua
