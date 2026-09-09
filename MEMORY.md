# MEMORY.md — Memoria persistente del agente dotfiles

Este archivo es la memoria del agente entre sesiones. Se lee al inicio de cada sesión y se actualiza al final.

## Patrones detectados

- **gesturecontrol venv + NixOS**: Usar `--system-site-packages` para heredar numpy/opencv del sistema. pip install solo para mediapipe y dependencias no disponibles en nixpkgs.
- **websockets v17+ API change**: `websockets.serve()` ahora requiere `async with` pattern, no `run_until_complete`. Usar `asyncio.new_event_loop()` en thread separado con `asyncio.Future()` para mantener vivo el loop.
- **WebSocket server en gesturecontrol**: LandmarkServer corre en thread separado con asyncio loop propio. `publish()` usa `run_coroutine_threadsafe()` para enviar desde el thread principal.

## Errores comunes y soluciones

- **libstdc++.so.6 wrong ELF class**: Python de pip buscaba lib 32-bit en NixOS. Solución: usar python3.withPackages con numpy/opencv4 de nixpkgs + venv --system-site-packages.
- **gesturecontrol engine camera busy**: Proceso zombie retenía /dev/video0. Kill manual resolvió.
- **websockets RuntimeError: no running event loop**: API v17 cambió. Solución: `asyncio.new_event_loop()` + `run_until_complete(asyncio.Future())`.

## Configuraciones frecuentes

- `~/.config/gesturecontrol/triggers.toml` — config de triggers (pose, swipe, continuous, etc.)
- `~/.config/gesturecontrol/actions.toml` — mapeo de señales a acciones
- `~/.local/share/gesturecontrol/gestureControl.py` — engine parcheado (cv2.waitKey fix)

## Skills creadas

_(Agente: listar skills creadas por auto-mejora)_

## Pendientes de mejora

- WebSocket landmark server necesita `websockets` en venv (ya instalado) y en packages.nix (ya añadido).
- Considerar añadir `websockets` a `linux/bin/gesturecontrol-landmarks` wrapper si se usa standalone.

## Historial de sesiones (últimas 5)

### Sesión 2026-09-09: WebSocket Landmark Server
- **Qué se hizo**: Modificar gesturecontrol engine para exponer 21 landmarks por mano vía WebSocket (puerto 7072)
- **Cambios**:
  - `gestureControl.py`: Añadido `LandmarkServer` class, modificado `processFrame` para incluir landmarks en hands dict, añadidos args `--landmark-port` y `--no-landmarks`
  - `packages.nix`: Añadido `websockets` a python3.withPackages
  - `home.nix`: Añadido `gesturecontrol-landmarks` a allScripts
  - Nuevo script: `linux/bin/gesturecontrol-landmarks` — cliente WebSocket con 3 modos (print, raw JSON, curses 3D)
- **Qué funcionó**: Compilación OK, rebuild OK, server inicia correctamente
- **Pendiente**: Test con cámara real (en este contexto no hay cámara física)

---
_Ultima actualización: 2026-09-09_
