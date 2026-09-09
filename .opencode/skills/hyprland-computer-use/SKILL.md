---
name: hyprland-computer-use
description: Computer use agent for Hyprland. Full desktop control: windows, workspaces, apps, layout, gaps, mouse, keyboard, screenshots. Use when user asks to manipulate windows, switch workspaces, manage layouts, control mouse/keyboard, take screenshots, or interact with desktop elements.
---

# Hyprland Computer Use

Computer use completo bajo Hyprland: ventanas, workspaces, layouts, mouse, teclado, capturas.

## Herramientas

### hyprctl (ventanas/workspaces)
```bash
hyprctl clients -j              # Ventanas (JSON)
hyprctl workspaces -j           # Workspaces
hyprctl activewindow -j         # Ventana activa
hyprctl dispatch movetoworkspace <id>
hyprctl dispatch focuswindow <address>
hyprctl dispatch closewindow <address>
hyprctl dispatch togglefloating <address>
hyprctl dispatch fullscreen <address>
hyprctl dispatch workspace <id>
hyprctl dispatch movefocus <dir>
hyprctl dispatch resizeactive <w> <h>
hyprctl keyword general:layout <layout>
hyprctl dispatch exec "[workspace N silent] app"
```

### xdotool (mouse/teclado)
```bash
xdotool mousemove <x> <y>       # Mover mouse
xdotool click 1/2/3             # Clicks
xdotool type "texto"            # Escribir
xdotool key ctrl+c              # Atajos
xdotool search --name "App" windowactivate
```

### grim + slurp (capturas)
```bash
grim /tmp/shot.png                    # Pantalla completa
grim -g "$(slurp)" /tmp/shot.png      # Área selectiva
grim -g "$(slurp)" - | wl-copy        # Copiar al clipboard
```

### wtype (teclado Wayland)
```bash
wtype "texto"
wtype -M ctrl c
```

## Patrones

1. **Click en coordenada:**
   ```bash
   xdotool mousemove 500 300 && xdotool click 1
   ```

2. **App en workspace:**
   ```bash
   hyprctl dispatch exec "[workspace 5 silent] firefox"
   ```

3. **Cerrar workspace:**
   ```bash
   hyprctl clients -j | jq -r '.[] | select(.workspace.id == 5) | .address' | xargs -I {} hyprctl dispatch closewindow {}
   ```

4. **Capturar pantalla:**
   ```bash
   grim -g "$(slurp)" /tmp/selection.png
   ```

## Reglas

1. Verificar estado antes (hyprctl clients -j)
2. Usar JSON output
3. Reportar resultados
4. Manejar errores
