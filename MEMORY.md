# MEMORY.md — Memoria persistente del agente dotfiles

Este archivo es la memoria del agente entre sesiones. Se lee al inicio de cada sesión y se actualiza al final.

## Patrones detectados

- **websockets v17+ API change**: `websockets.serve()` ahora requiere `async with` pattern, no `run_until_complete`. Usar `asyncio.new_event_loop()` en thread separado con `asyncio.Future()` para mantener vivo el loop.
- **WebSocket server en gesturecontrol**: LandmarkServer corre en thread separado con asyncio loop propio. `publish()` usa `run_coroutine_threadsafe()` para enviar desde el thread principal.

## Errores comunes y soluciones

- **gesturecontrol engine camera busy**: Proceso zombie retenía /dev/video0. Kill manual resolvió.
- **websockets RuntimeError: no running event loop**: API v17 cambió. Solución: `asyncio.new_event_loop()` + `run_until_complete(asyncio.Future())`.

## Configuraciones frecuentes

- `~/.config/gesturecontrol/triggers.toml` — config de triggers (pose, swipe, continuous, etc.)
- `~/.config/gesturecontrol/actions.toml` — mapeo de señales a acciones
- `~/.local/share/gesturecontrol/gestureControl.py` — engine parcheado (cv2.waitKey fix)
- **Bedtime timer**: desktop se apaga a las 21:00 (hora Colombia). `bedtime-skip.sh` crea flag `/run/bedtime-skip` para cancelar una noche.

## Skills creadas

_(Agente: listar skills creadas por auto-mejora)_

## Pendientes de mejora

_(agregar aqui pendientes activos)_

## Historial de sesiones (últimas 5)

### Sesión 2026-09-15: Migración NixOS → Omarchy (Arch)
- **Qué se hizo**: Eliminado todo el legacy NixOS/Ubuntu (nixos/, flake.nix/lock, setup-nixos.sh, setup-ubuntu.sh, migrate-to-ubuntu.sh, cuda-*, refind-check.sh, rebuild/sync*, auto-sync.sh, linux/bin/cuda-build-notify.sh, gdm/black.png). Repo remoto corregido a `github.com/estebaninfante/dotfiles.git`.
- **Symlinks**: Nuevo `scripts/link-dotfiles.sh` idempotente (inventario CONFIG_DIRS/CONFIG_FILES/HOME_FILES + lan-mouse machine-specific + bin con clobber=false para no pisar stubs de Omarchy). `~/.config` ahora son symlinks al repo; hypr incluido. `hyprctl reload` OK.
- **Refs NixOS runtime limpiadas**: `/run/current-system/...` y `/nix/var/...` reemplazados por rutas Arch (`/usr/bin/handy`, `shutil.which(...)`, `/usr/share/piper-voices`, `/usr/share/sounds/...`). Handy = `/usr/bin/handy`. Piper vendorizado en `/opt/piper-tts`.
- **Seguridad**: `EXPLABS_API_KEY` estaba hardcodeada en `.bashrc` trackeado → movida a `~/.config/dotfiles-secrets.sh` (chmod 600, fuera del repo).
- **IMPORTANTE**: existía `dotfiles-sync.timer` (systemd user) que auto-commiteaba cada 5 min. Detenido, deshabilitado y units eliminadas. No recrear (setup-omarchy ya no lo instala).
- **Lección**: Omarchy = Arch; nada de `/run/current-system` ni `nixos-rebuild`/`home-manager`. Paquetes con pacman/yay.

### Sesión 2026-09-15: SystemBar attempt + revert
- **Qué se hizo**: Intenté agregar CPU/GPU pills a la barra del custom quickshell de dotfiles. Descubrí que la barra visible era la de Omarchy (`/usr/share/omarchy/shell`), no la del dotfiles. Matar omarchy-launch-shell rompió la barra. Revertí todo.
- **Lección**: El usuario usa la barra de Omarchy, NO el custom quickshell de dotfiles. No confundir uno con el otro.
- **Acción**: Revertí DashboardService.qml, Bar.qml, eliminé SystemBar.qml. Restauré omarchy-launch-shell.

---
_Ultima actualización: 2026-09-15 (migración a Omarchy)_
