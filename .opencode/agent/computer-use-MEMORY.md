# MEMORY.md — Memoria persistente del agente computer-use

Este archivo es la memoria del agente entre sesiones. Se lee al inicio de cada sesión y se actualiza al final.

## Patrones detectados

- **2026-09-09**: La sintaxis clásica `hyprctl dispatch` NO funciona en Lua mode (≥0.55). Usar `hypr-lua.sh` wrapper (nunca `hyprctl eval` directo — quoting rompe).

## Errores comunes y soluciones

### hyprctl dispatch falla silenciosamente en Lua mode
- **Error**: `hyprctl dispatch exec "[workspace N silent] app"` no hace nada, errores de parseo Lua
- **Causa**: Desde Hyprland 0.55, el parser convierte `hyprctl dispatch exec "cmd"` → `hl.dispatch(exec "cmd")` (Lua inválido)
- **Solución**: Usar `hypr-lua.sh exec "comando"` (wrapper maneja quoting internamente)
- **Para focus**: `hypr-lua.sh focus-pid PID` o `hypr-lua.sh focus-address 0x...`
- **Para move**: `hypr-lua.sh move N` (primero focus, luego move)
- **Para abrir en workspace**: `hypr-lua.sh open-in-workspace "cmd" N class`
- **Binario brave**: Se llama `brave`, no `brave-browser`
- **Opciones window**: `pid:12345` ✓, `address:0x...` ✓, `class-regex` ✗ (no funciona desde eval)

### Secuencia óptima para abrir app en workspace
```bash
# Usar hypr-lua.sh (maneja todo internamente)
hypr-lua.sh open-in-workspace "brave --app=https://web.whatsapp.com" 7 brave
```

## Mapeos frecuentes

| Voz | Comando |
|-----|---------|
| abrir app | `hypr-lua.sh exec "app"` |
| cerrar | `hypr-lua.sh close` |
| workspace N | `hypr-lua.sh workspace N` |
| mover a workspace | `hypr-lua.sh move N` |
| fullscreen | `hypr-lua.sh fullscreen` |
| float toggle | `hypr-lua.sh float` |
| layout | `hyprctl keyword general:layout monocle` |

## Skills creadas

- **hyprland-lua**: CLI control + Lua config ( ~/.config/opencode/skills/hyprland-lua/)

## Pendientes de mejora

- ~~Crear script helper `hypr-lua.sh`~~ ✅ Ya existe en `linux/bin/hypr-lua.sh`

## Historial de sesiones (últimas 5)

### 2026-09-09 — Segunda sesión
- Se actualizó computer-use.md para usar `hypr-lua.sh` en vez de `hyprctl eval` directo
- Se actualizó skill hyprland-lua con sección CLI Control
- Resultado: agente ahora usa wrapper, quoting issues eliminados

### 2026-09-09 — Primera sesión
- Se creó el agente computer-use (rename desde voice-use)
- Se corrigió la sintaxis hyprctl dispatch → hyprctl eval para Lua mode
- Aprendizaje: Lua mode requiere `hyprctl eval` + API Lua, nunca `hyprctl dispatch`

---
_Ultima actualización: 2026-09-09_
