# MEMORY.md — Memoria persistente del agente computer-use

Este archivo es la memoria del agente entre sesiones. Se lee al inicio de cada sesión y se actualiza al final.

## Patrones detectados

- **2026-09-09**: La sintaxis clásica `hyprctl dispatch` NO funciona en Lua mode (≥0.55). SIEMPRE usar `hyprctl eval` + API Lua.

## Errores comunes y soluciones

### hyprctl dispatch falla silenciosamente en Lua mode
- **Error**: `hyprctl dispatch exec "[workspace N silent] app"` no hace nada, errores de parseo Lua
- **Causa**: Desde Hyprland 0.55, el parser convierte `hyprctl dispatch exec "cmd"` → `hl.dispatch(exec "cmd")` (Lua inválido)
- **Solución**: Usar `hyprctl eval 'hl.exec_cmd("comando")'` para ejecutar
- **Para focus**: `hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'pid:PID' }))"`
- **Para move**: `hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = N }))"` (primero focus, luego move)
- **Binario brave**: Se llama `brave`, no `brain-browser`
- **Opciones window**: `pid:12345` ✓, `address:0x...` ✓, `class-regex` ✗ (no funciona desde eval)

### Secuencia óptima para abrir app en workspace
```bash
# 1. Ejecutar app
hyprctl eval 'hl.exec_cmd("brave --app=https://web.whatsapp.com")'
sleep 3
# 2. Buscar PID
PID=$(hyprctl clients -j | python3 -c "import sys,json;[print(c['pid']) for c in json.load(sys.stdin) if 'whatsapp' in c.get('class','').lower()]")
# 3. Focus + mover
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'pid:$PID' }))"
hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = 7 }))"
```

## Mapeos frecuentes

| Voz | Comando |
|-----|---------|
| abrir app | `hyprctl eval 'hl.exec_cmd("app")'` |
| cerrar | `hyprctl eval "hl.dispatch(hl.dsp.window.close())"` |
| workspace N | `hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = N }))"` |
| mover a workspace | focus + `hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = N }))"` |
| fullscreen | `hyprctl eval "hl.dispatch(hl.dsp.window.fullscreen())"` |
| float toggle | `hyprctl eval "hl.dispatch(hl.dsp.window.float({ action = 'toggle' }))"` |
| layout | `hyprctl keyword general:layout monocle` |

## Skills creadas

_(Agente: listar skills creadas por auto-mejora)_

## Pendientes de mejora

- Crear script helper `hypr-lua.sh` para comandos comunes (abrir, cerrar, workspace, etc.)

## Historial de sesiones (últimas 5)

### 2026-09-09 — Primera sesión
- Se creó el agente computer-use (rename desde voice-use)
- Se corrigió la sintaxis hyprctl dispatch → hyprctl eval para Lua mode
- Aprendizaje: Lua mode requiere `hyprctl eval` + API Lua, nunca `hyprctl dispatch`

---
_Ultima actualización: 2026-09-09_
