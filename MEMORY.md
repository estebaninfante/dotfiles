# MEMORY.md — Memoria persistente del agente dotfiles

Este archivo es la memoria del agente entre sesiones. Se lee al inicio de cada sesión y se actualiza al final.

## Patrones detectados

- **websockets v17+ API change**: `websockets.serve()` ahora requiere `async with` pattern, no `run_until_complete`. Usar `asyncio.new_event_loop()` en thread separado con `asyncio.Future()` para mantener vivo el loop.
- **WebSocket server en gesturecontrol**: LandmarkServer corre en thread separado con asyncio loop propio. `publish()` usa `run_coroutine_threadsafe()` para enviar desde el thread principal.
- **opencode en Omarchy = backend aqua de mise (unico dueno)**: la config `~/.config/mise/config.toml` (hoy versionada en `linux/config/mise/config.toml`) fija `opencode = "1.19.0"`. El binario vive autocontenido en `~/.local/share/mise/installs/opencode/1.19.0/opencode`. El lanzador `linux/bin/opencode` hace `exec mise x opencode@1.19.0 -- opencode "$@"` (NUNCA `mise use -g`). Nada de pacman `opencode-bin` ni npm global `opencode-ai`.

## Errores comunes y soluciones

- **gesturecontrol engine camera busy**: Proceso zombie retenía /dev/video0. Kill manual resolvió.
- **websockets RuntimeError: no running event loop**: API v17 cambió. Solución: `asyncio.new_event_loop()` + `run_until_complete(asyncio.Future())`.
- **Nautilus "no abre" (Files)**: el servicio D-Bus `dbus-:1.1-org.gnome.Nautilus@0.service` (`nautilus --gapplication-service`) se queda wedged → `gtk-launch org.gnome.Nautilus.desktop` retorna exit 0 pero no crea ventana. Diagnóstico: `systemctl --user status 'dbus-:1.1-org.gnome.Nautilus@0.service'` (RSS >1GB, decenas de tasks) + `coredumpctl list | grep nautilus`. Fix: `pkill -x nautilus` (el servicio D-Bus lo relanza limpio en el próximo launch). Causa raíz: fuga de thumbnailers glycin (`glycin-image-rs` en bwrap) que nunca salen y revientan el proceso con SEGV. Si reaparece: limpiar bwrap huérfanos y considerar desactivar thumbnails nautilus.
- **opencode lentísimo al arrancar (>25s, cuelga)**: causa = `mise use -g --quiet opencode` dentro del lanzador (golpea el registro/red en cada arranque). Fix: fijar `opencode = "1.19.0"` en la config de mise y ejecutar `mise x opencode@1.19.0 -- opencode` (overhead ~0.02s; el binario aqua tarda ~0.70s por sí solo).
- **Backend npm de mise no corre postinstall**: `mise exec -- opencode` falla con `opencode-ai's postinstall script was not run`; el empaquetador (aube) ignora scripts. Evitarlo usando el backend aqua. Si se insiste en npm: `cd .../node_modules/opencode-ai && node postinstall.mjs`.
- **`pkill -f '<patrón>'` se auto-matchea** y mata la propia shell si el patrón aparece en el comando (p.ej. `pkill -f 'mise use'`). Filtrar por PID.
- **`grep` en la shell de opencode resuelve a BusyBox** (no soporta `-A`/`-B`): usar `/usr/bin/grep`.

## Configuraciones frecuentes

- `~/.config/gesturecontrol/triggers.toml` — config de triggers (pose, swipe, continuous, etc.)
- `~/.config/gesturecontrol/actions.toml` — mapeo de señales a acciones
- `~/.local/share/gesturecontrol/gestureControl.py` — engine parcheado (cv2.waitKey fix)
- **Bedtime timer**: desktop se apaga a las 21:00 (hora Colombia). `bedtime-skip.sh` crea flag `/run/bedtime-skip` para cancelar una noche.
- **opencode**: `~/.config/mise/config.toml` (→ `linux/config/mise/config.toml`), `~/.local/bin/opencode` (→ `linux/bin/opencode`), skill/plugins en `~/.config/opencode/` (→ `linux/config/opencode/`). `rtk` v1.0.0 en `~/.local/bin/rtk` (instalador oficial, ver `scripts/`). El plugin `plugins/rtk.ts` reescribe comandos bash via `rtk rewrite` cuando `rtk` esta en PATH.

## Skills creadas

_(Agente: listar skills creadas por auto-mejora)_

## Pendientes de mejora

_(agregar aqui pendientes activos)_

## Historial de sesiones (últimas 5)

### Sesión 2026-10-13: Ticket MACHINE-OPENCODE-RTK — opencode 1.19.0 (dueño único) + rtk
- **Pedido**: actualizar opencode a "la 2.0", arreglar el aviso "rtk not found in PATH" y el arranque lento.
- **Hallazgo (delta)**: OpenCode 2 SÍ existe y es GA/estable (`@opencode/cli` 2.0.28, docs `opencode.ai/v2`, tag v2.0.28 del 13-oct), NO es preview. Pero su breaking change #1 deja fuera los plugins V1: los ~10 plugins locales (no-comments, verify-hook, qml-ux-lint, app-arch-lint, voice, caveman, notify-sound, herdr-agent-state, rtk, btw) dejarían de correr hasta portarlos. Con 15 sillas vivas y 7 tickets in-progress se abre ticket aparte y se pregunta antes de migrar.
- **Opencode 1.19.0, dueño único**: se quitó `opencode-bin` de pacman (`sudo pacman -Rns`), el npm global del node de mise y el install npm de mise; queda SOLO el backend aqua de mise con `opencode = "1.19.0"` en `~/.config/mise/config.toml` (versionado en `linux/config/mise/config.toml`). Lanzador versionado `linux/bin/opencode`: `exec mise x opencode@1.19.0 -- opencode "$@"` (sin `mise use -g`).
- **Arranque**: antes `opencode --version` por el lanzador viejo se colgaba >25s (había colgado >120s); después ~0,77s (binario aqua ~0,70s + overhead mise ~0,02s).
- **rtk**: instalado con el instalador oficial (`github.com/rtk-ai/rtk`), v1.0.0 en `~/.local/bin/rtk`; `rtk gain` OK y `rtk rewrite "git status"` devuelve `rtk git status` (exit 3 = ask, el plugin lo acepta). El aviso de startup de `plugins/rtk.ts` desaparece cuando rtk está en PATH (requiere reiniciar opencode: no hay hot-reload). Honestidad: el aviso era ruido; la lentitud era `mise use -g`.
- **Colateral `gh` colgaba**: `~/.local/bin/gh` era un wrapper real con `mise use -g --quiet gh` → `gh auth token` colgaba → `git push` colgaba. Reemplazado por `linux/bin/gh` versionado (`exec mise x gh@2.101.0 -- gh "$@"`). Push OK: `df45bcd..42d26d8` (18 commits de backlog).
- **Evidencia**: `verify run packages` PASS; `opencode --version` = 1.19.0; `rtk --version` = 1.0.0; `rtk gain` OK.

### Sesión 2026-10-13: Ticket rig-focus — rig spawn enfoca el herdr
- **Síntoma**: `rig spawn` creaba workspace+tab herdr sin foco → el usuario (kitty) no veía la silla aparecer.
- **Fix (`~/dotfiles/linux/bin/rig`)**: nuevo helper `herdr_focus_seat <ws> <tid>` (workspace focus + tab focus, best-effort). `cmd_spawn`: foco ON por defecto (`focus_flag="${RIG_FOCUS:-1}"`), flags `--focus`/`--no-focus`. `work_new`: pasa `--focus`/`--no-focus` a spawn (`--spawn`). Uso actualizado en las 3 usage strings + help herdr.
- **Bug colateral arreglado**: `work_finish` (línea 1107) llamaba `verify auto ... --quiet`; este `verify` exige `--quiet` ANTES del subcomando → `unrecognized arguments: --quiet` → `rig work finish` fallaba siempre. Cambiado a `verify --quiet auto ...`.
- **Verifier**: `verifiers/rig.sh` nuevo check `herdr-focus` (grep `herdr_focus_seat` + `--help` con `--no-focus`).
- **Evidencia**: `verify run rig` PASS; test real spawn enfocó ws+tab (limpiado); `rig work finish rig-focus --no-close-seat` → `commit c1993c3`, ticket done `verify:PASS`.
- **Gotcha**: el worktree NO contenía `linux/bin/rig` — rig vive UNTRACKED solo en `~/dotfiles` (árbol sucio, ~116 archivos). El verifier hardcodea `$HOME/dotfiles/...`, así que `verify run rig` siempre prueba el árbol principal. Copiar rig+verifier al worktree para commitear.

### Sesión 2026-10-08: Nautilus "no abre"
- **Síntoma**: `gtk-launch org.gnome.Nautilus.desktop` (menú Omarchy) salía exit 0 sin ventana.
- **Causa**: servicio D-Bus `dbus-:1.1-org.gnome.Nautilus@0.service` wedged (PID 1406306, 1.4G RSS, 101 tasks, 2h vivo). `gdbus Activate` respondía `()` pero no abría ventana. A las 17:13:46 el proceso hizo SEGV (`coredumpctl` presente, stack en `g_signal_emit` desde `g_application_run`); hilos glycin-lib en el coredump.
- **Fix**: `pkill -x nautilus` → servicio D-Bus relanzó limpio → `gtk-launch` abre ventana en workspace activo (verificado 2 veces: 1ª creación + 2ª con servicio vivo). Tambien matados 3 `bwrap`/`glycin-image-rs` huérfanos de 4h45 (padre `nm-applet`).
- **Nota**: nautilus 50.3.1, glycin-loaders = thumbnailers sandbox en bwrap. Fuga conocida del estilo. Recurrencia → desactivar thumbnails o actualizar paquete.
- **Diagnostic**: no confiar en "exit 0" de launchers D-Bus; verificar ventana con `hyprctl clients -j`.

### Sesión 2026-09-25: Terminar migración desktop → laptop (fresh install)
- **hyprexpo**: upstream borró el pin `e95ef2e` (historial reescrito, 404 en GitHub) y `master` cambió a layout `src/`. Rebaseado a `5891014c` = pin oficial de `hyprpm.toml` para Hyprland 0.56.2. Parche regenerado (mismos 16 archivos), verificado en sesión anidada (grilla 3D OK en PNG). Hunk de live-refresh descartado (esa función upstream no existe en el nuevo pin; expo = snapshots + damage, como stock). `.so` instalado en `/var/cache/hyprpm/eztvn/hyprexpo/` vía pkexec; aplica al próximo login. PIN actualizado en `hyprexpo-rebuild.sh`, `hyprexpo-verify-3d.sh` y SKILL.md. Nota en `hyprexpo-changes.md`.
- **Lección (skill hyprland-plugin-safety)**: ante pin muerto, leer `commit_pins` del `hyprpm.toml` upstream para la versión de Hyprland en ejecución, NO usar `HEAD`.
- **setup-secrets.sh**: peer se elegía por `hostname` (laptopmarchy → peer erróneo "laptop"). Ahora usa `~/.config/machine-type` con fallback a hostname.
- **Paquetes**: tailscale + syncthing NO estaban en setup-omarchy (FASE 9 los esperaba). Instalados vía pacman+pkexec, servicios habilitados (`tailscaled` activo; `syncthing@eztvn` habilitado, arranque manual descartado por usuario). Agregados a EXTRA_PKGS del setup para futuros installs.
- **SSH**: key `ed25519` creada en laptop (`eztvn@laptopmarchy`). Falta: autorizarla en desktop + `tailscale up --authkey` + `gh auth login` + copiar secrets/sunshine-pass (desktop offline durante la sesión).
- **`reverse_rows`**: `hyprland.lua` lo seteaba pero la clave no existía en ningún parche (venía de árbol sucio del desktop). Implementado en el fork (flag en computeTileLayout/tileIndexAtPoint, default 0), test headless 9/9, parche v2 (18 archivos). `.so` con reverse compilado en `~/.cache/hyprexpo-src/` — falta `sudo install` (polkit bloqueado con pantalla lockeada) + relogin.
- **Ojo**: `pkill -f <patrón>` se suicida si el patrón aparece en tu propio comando. Matar nested solo por PID. Los `make test` del plugin tienen 4 FAILs preexistentes de selección (no-layout) en este pin.

### Sesión 2026-09-15: Migración NixOS → Omarchy (Arch)
- **Qué se hizo**: Eliminado todo el legacy NixOS/Ubuntu (nixos/, flake.nix/lock, setup-nixos.sh, setup-ubuntu.sh, migrate-to-ubuntu.sh, cuda-*, refind-check.sh, rebuild/sync*, auto-sync.sh, linux/bin/cuda-build-notify.sh, gdm/black.png). Repo remoto corregido a `github.com/estebaninfante/dotfiles.git`.
- **Symlinks**: Nuevo `scripts/link-dotfiles.sh` idempotente (inventario CONFIG_DIRS/CONFIG_FILES/HOME_FILES + lan-mouse machine-specific + bin con clobber=false para no pisar stubs de Omarchy). `~/.config` ahora son symlinks al repo; hypr incluido. `hyprctl reload` OK.
- **Refs NixOS runtime limpiadas**: `/run/current-system/...` y `/nix/var/...` reemplazados por rutas Arch (`/usr/bin/handy`, `shutil.which(...)`, `/usr/share/piper-voices`, `/usr/share/sounds/...`). Handy = `/usr/bin/handy`. Piper vendorizado en `/opt/piper-tts`.
- **Seguridad**: `EXPLABS_API_KEY` estaba hardcodeada en `.bashrc` trackeado → movida a `~/.config/dotfiles-secrets.sh` (chmod 600, fuera del repo).
- **IMPORTANTE**: existía `dotfiles-sync.timer` (systemd user) que auto-commiteaba cada 5 min. Detenido, deshabilitado y units eliminadas. No recrear (setup-omarchy ya no lo instala).
- **Lección**: Omarchy = Arch; nada de `/run/current-system` ni `nixos-rebuild`/`home-manager`. Paquetes con pacman/yay.

---
_Ultima actualización: 2026-10-13 (ticket MACHINE-OPENCODE-RTK: opencode 1.19.0 dueño único via mise + rtk 1.0.0)_
