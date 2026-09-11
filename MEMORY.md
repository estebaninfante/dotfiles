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

## Migración NixOS → Ubuntu 24.04 LTS

**Estado**: Script creado, pendiente de ejecutar en máquina fresca.

**Archivos migration script**: `scripts/migrate-to-ubuntu.sh`
**Fixes quickshell**: `cards/NotifCard.qml` (sound path), `menus/PowerMenu.qml` (systemctl path) — ambos ahora multi-path compatible.

**Stack Ubuntu**:
- Hyprland via PPA oficial (`ppa:hyprland/release`)
- NVIDIA via `ubuntu-drivers install` + `nvidia-cuda-toolkit`
- PyTorch CUDA pre-compilado: `pip install torch --index-url https://download.pytorch.org/whl/cu128`
- keyd desde GitHub (make install)
- quickshell desde fuente o AppImage
- Configs: symlinks directos al repo (sin home-manager)
- Snap: quitado y bloqueado

**Pendiente**: Ejecutar en máquina fresca, probar Hyprland, testear CUDA/torch.

## Pendientes de mejora

- WebSocket landmark server necesita `websockets` en venv (ya instalado) y en packages.nix (ya añadido).
- Considerar añadir `websockets` a `linux/bin/gesturecontrol-landmarks` wrapper si se usa standalone.

## Historial de sesiones (últimas 5)

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
_Ultima actualización: 2026-09-10_
