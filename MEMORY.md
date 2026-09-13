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
- **Bedtime timer**: desktop se apaga a las 21:00 (hora Colombia). `bedtime-skip.sh` crea flag `/run/bedtime-skip` para cancelar una noche. IMPORTANTE: builds largos (CUDA) necesitan skip o se interrumpen.
- **CUDA rebuild**: `scripts/cuda-rebuild.sh` con retry loop (5 intentos). Logs en `~/.local/state/dotfiles/cuda-rebuild.{log,error,status}`. Paralelismo: `NIX_CONFIG="max-jobs=2, cores=8"`.

## Skills creadas

_(Agente: listar skills creadas por auto-mejora)_

## Migración NixOS → Omarchy (Arch Linux)

**Estado**: Script creado (`scripts/setup-omarchy.sh`), listo para ejecutar.

**Un solo comando post-install de Omarchy**:
```bash
bash ~/dotfiles/scripts/setup-omarchy.sh
```

**Qué hace el script (15 fases)**:
1. Detecta Omarchy/Arch, clona repo si falta
2. Instala yay (AUR helper)
3. Instala paquetes extra (hyprpaper, kitty, tmux, starship, zoxide, etc.)
4. Copia hyprland.lua (reemplaza defaults de Omarchy)
5. Deshabilita omarchy-shell, symlinkea nuestro quickshell custom
6. Symlink configs (kitty, nvim, kanata, fastfetch, btop, gh, opencode, tmux, voice)
7. Enlaza scripts a ~/.local/bin (excluye NixOS-specific: cuda-*, refind-check)
8. Configura keyd (copia default.conf, habilita servicio)
9. Systemd user services (quickshell, lan-mouse, clipboard-sync, voice-daemon, etc.)
10. Servicios de sistema (syncthing, tailscale, input-remapper)
11. Configs especiales (lan-mouse, input-remapper: copy, no symlink)
12. PATH en .bashrc
13. Fonts
14. NVIDIA drivers (detecta y instala)
15. AI/ML stack (PyTorch + CUDA via pip)

**Diferencias clave NixOS → Omarchy**:
- Paquetes: pacman + yay (AUR) en vez de nix-env/nixpkgs
- No hay home-manager: symlinks directos al repo
- No hay nixos-rebuild: configs se aplican via symlink + systemctl
- Omarchy shell deshabilitado: usamos nuestro quickshell custom
- keyd desde AUR en vez de módulo NixOS
- Paths multi-distro: scripts fixeados para funcionar sin /run/current-system

**Fixes multi-distro aplicados**:
- `ac-idle-handler.sh`: systemctl sin path NixOS
- `lid-close-handler.sh`: systemctl suspend sin path NixOS
- `speak`: piper-voices search con fallbacks multi-distro
- `voice`: piper-voices search con fallbacks multi-distro
- `gpu-mode.sh`: warning en Arch (NVIDIA switching no soportado)
- `setup-omarchy.sh`: excluye cuda-* y refind-check (NixOS-specific)

**Pendiente**: Ejecutar en Omarchy fresco, probar Hyprland + quickshell + keyd.

## Pendientes de mejora

- WebSocket landmark server necesita `websockets` en venv (ya instalado) y en packages.nix (ya añadido).
- Considerar añadir `websockets` a `linux/bin/gesturecontrol-landmarks` wrapper si se usa standalone.

## Historial de sesiones (últimas 5)

### Sesión 2026-09-13: Migración a Omarchy
- **Qué se hizo**: Investigé Omarchy (Arch + Hyprland + Quickshell). Creé `scripts/setup-omarchy.sh` (15 fases, un solo comando). Fix paths NixOS en scripts multi-distro.
- **Decisión**: Migrar a Omarchy (no Ubuntu). Omarchy ya trae Hyprland + Quickshell, nuestro custom quickshell reemplaza omarchy-shell.
- **Archivos modificados**: `scripts/setup-omarchy.sh` (nuevo), `linux/bin/ac-idle-handler.sh`, `linux/bin/lid-close-handler.sh`, `linux/bin/speak`, `linux/bin/voice`, `linux/bin/gpu-mode.sh`, `MEMORY.md`.
- **Pendiente**: Ejecutar en Omarchy fresco, probar todo.

### Sesión 2026-09-10 (tarde): Migración NixOS → Ubuntu
- **Qué se hizo**: Analicé viabilidad de migración a Ubuntu. Fix 2 paths NixOS en quickshell. Creé `scripts/migrate-to-ubuntu.sh`.
- **Decisión**: Migrar a Ubuntu 24.04 LTS. CUDA pre-compilado (pip wheels) resuelve el problema de builds OOM.
- **Archivos modificados**: `cards/NotifCard.qml` (sound path multi-distro), `menus/PowerMenu.qml` (systemctl path), `scripts/migrate-to-ubuntu.sh` (nuevo), `MEMORY.md`.
- **Pendiente**: Ejecutar en máquina fresca, testear Hyprland + quickshell + CUDA.

### Sesión 2026-09-10: CUDA rebuild interrumpido + reinicio
- **Qué se hizo**: Activar CUDA en desktop.nix (RTX 3070), crear cuda-rebuild.sh con retry loop, limpiar 43GB de store
- **Qué falló**: Build interrumpido por bedtime timer (21:00). El build estaba compilando opencv/magma/cudnn cuando la máquina se apagó.
- **Acción tomada**: `bedtime-skip.sh` para saltar apagado, limpieza de store (43.1 GiB), reinicio del build
- **Pendiente**: Verificar que el build CUDA complete (varias horas). Then: cachear para laptop, probar CUIDA
- **Lección**: SIEMPRE saltar bedtime para builds CUDA largos (`bash ~/dotfiles/linux/bin/bedtime-skip.sh`)

### Sesión 2026-09-09: CUDA preparation + WebSocket Landmark Server
- **Qué se hizo**: 
  1. Activar CUDA en desktop.nix (uncomment cudaSupport + sunshine override)
  2. Crear `scripts/cuda-rebuild.sh` (retry loop, logging, NIX_CONFIG controlado)
  3. Dry-build: 101 derivaciones, ~14GB unpacked (torch ×2, cudnn, magma, opencv)
  4. Modificar gesturecontrol engine para landmarks WebSocket (puerto 7072)
- **Cambios**: desktop.nix, cuda-rebuild.sh (nuevo), packages.nix, gestureControl.py
- **Pendiente**: Build CUDA completo, test CUIDA, cachear para laptop

---
_Ultima actualización: 2026-09-13_
