# AGENTS.md — Dotfiles

## Principio fundamental

**El repositorio (`~/dotfiles/`) es la unica fuente de verdad.**

Todas las configuraciones gestionadas viven aqui. Los archivos en `~/.config/`, `~/.bashrc`, etc. son enlaces simbolicos que apuntan a este repositorio.

**El usuario esta en Omarchy (Arch Linux), NO en NixOS.** El setup declarativo con NixOS se elimino del repo (queda solo en el historial de git): NO existe `flake.nix`, `nixos-rebuild`, `home-manager` ni specialisations. Paquetes con `pacman` + `yay` (AUR).

## Reglas permanentes

1. **Editar siempre dentro de `~/dotfiles/`.** Nunca modificar directamente `~/.config/`, `~/.bashrc` u otros destinos enlazados. Excepcion: migraciones puntuales o emergencias justificadas.

2. **Antes de crear un script nuevo, comprobar si uno existente puede reutilizarse o extenderse.** No duplicar funcionalidad.

3. **Evitar duplicar logica.** Si un patron se repite, abstraerlo en una funcion.

4. **Usar cambios minimos.** No reescribir archivos completos sin necesidad. Usar `edit` con precision quirurgica.

5. **Antes de modificar una configuracion existente, revisar el repositorio primero.** Respetar personalizaciones existentes del usuario.

6. **Nada de NixOS.** No crear `flake.nix`, ni ejecutar `nixos-rebuild`/`home-manager`. Todo va directo a `~/.config/` o `~/.local/bin/` via symlink al repo.

## Estructura del repositorio

```
dotfiles/
├── linux/
│   ├── config/          # ~/.config/ (symlinked)
│   ├── home/            # ~/.bashrc, ~/.gitconfig
│   ├── bin/             # ~/.local/bin/ (scripts propios)
│   ├── voice/           # TTS daemon + Chatterbox server
│   ├── xkb/             # Layout de teclado XKB
│   ├── patches/         # patches (lan-mouse AltGr, waybar Lua dispatch)
│   └── system/          # keyd, NetworkManager dispatcher
├── scripts/
│   ├── setup-omarchy.sh # fresh install en un comando
│   ├── link-dotfiles.sh # aplica el inventario de symlinks (idempotente)
│   ├── detect-machine.sh# detecta laptop/desktop por hardware
│   ├── omarchy-sync.sh  # export/import config del shell Omarchy (barra/plugins)
│   ├── setup-tts.sh     # TTS
│   ├── setup-secrets.sh # Configura/verifica claves y secrets
│   └── publish.sh       # Commit + push con confirmacion
├── AGENTS.md
└── README.md
```

Los secrets locales viven en `~/.config/dotfiles-secrets.sh` (FUERA del repo,
sourced por `~/.bashrc`). Nunca commitear claves.

## Inventario de configuraciones gestionadas

### Linux config (`linux/config/`) — directorios completos

| App | Ruta destino |
|-----|-------------|
| hypr | `~/.config/hypr/` |
| waybar | `~/.config/waybar/` |
| kitty | `~/.config/kitty/` |
| nvim | `~/.config/nvim/` |
| kanata | `~/.config/kanata/` |
| fastfetch | `~/.config/fastfetch/` |
| mako | `~/.config/mako/` |
| swaync | `~/.config/swaync/` |
| swayosd | `~/.config/swayosd/` |
| avizo | `~/.config/avizo/` |
| btop | `~/.config/btop/` |
| gh | `~/.config/gh/` |
| opencode | `~/.config/opencode/` |
| quickshell | `~/.config/quickshell/` (bar + menus + launcher) |
| tmux | `~/.config/tmux/` |
| gesturecontrol | `~/.config/gesturecontrol/` |
| voice | `~/.config/voice/` (config TTS) |
| input-remapper-2 | `~/.config/input-remapper-2/` (copiado, no symlink) |

### VS Code (caso especial)

Solo se enlazan `settings.json` y `keybindings.json` (el resto de `~/.config/Code/User/`
lo reescribe el editor). Fuente: `linux/config/vscode/User/`. Extensiones: VSCodeVim,
Live Server, Rosé Pine. Config: vim-style (leader espacio), UI minimalista, Live Server en 8080.

### Omarchy shell (`linux/config/omarchy/` — copiado, no symlink)

La barra activa es la de **Omarchy**, no la de dotfiles. Su config vive en
`~/.config/omarchy/` y se versiona aqui: `shell.json` (barra `eztvn.bar`, layout,
`centerAnchor`), `shell.toml` (fuente/scrim), `bar/modules/services.qml`,
`branding/`, `extensions/omarchy-menu.jsonc`, `backgrounds/` (fondos propios),
`hooks/*.hook` y los plugins locales (`plugins/eztvn.*`, `omnivoz.status`,
`talk-command.status`). Los plugins/temas instalados por git NO se copian (peso
+ `.git`): sus id+url viven en `plugins-git.txt` / `themes-git.txt` y se
reinstalan con `omarchy plugin add` / `omarchy theme install`.

`scripts/omarchy-sync.sh export` (maquina personalizada) y `import`
(laptop/fresh) replican. `setup-omarchy.sh` Fase 10.5 corre `import`
automaticamente. No symlinkear `~/.config/omarchy`: Omarchy escribe ahi en vivo.

**Auto-sync (para que no se desincronice):** `scripts/dotfiles-sync.sh` (timer
`dotfiles-sync.timer`, cada ~5 min en ambas maquinas) corre `git pull` y, tras
un pull exitoso, `omarchy-sync.sh import`. Flujo:

1. Personalizas en una maquina -> `omarchy-sync.sh export` (o `publish.sh`, que
   exporta solo) -> commit + push.
2. La otra maquina hace pull por el timer e **importa** la shell automaticamente.

Al terminar de personalizar en cualquier maquina, **exporta antes de que el
timer pise** tus cambios locales con el repo. Verificacion: `omarchy-sync.sh
status` (o `verify auto ~/.config/omarchy/shell.json`) reporta `DRIFT` si el
live difiere del repo. Machine-specific: `shell.<machine>.json` (laptop/desktop)
gana sobre `shell.json` si existe; hoy no se usa (layout unico).

### Linux config — archivos sueltos

| Archivo | Ruta destino |
|---------|-------------|
| libinput-gestures.conf | `~/.config/libinput-gestures.conf` |
| mimeapps.list | `~/.config/mimeapps.list` |
| user-dirs.dirs | `~/.config/user-dirs.dirs` |
| user-dirs.locale | `~/.config/user-dirs.locale` |

### Home (`linux/home/`)

| Archivo | Ruta destino |
|---------|-------------|
| .bashrc | `~/.bashrc` |
| .gitconfig | `~/.gitconfig` |

### Scripts (`linux/bin/`)

Todos los scripts propios de `~/.local/bin/` (excluye ejecutables instalados por paquetes).

### Voice (`linux/voice/`)

| Archivo | Descripcion |
|---------|-------------|
| daemon.py | Daemon TTS con FIFO queue, administra chatterbox server |
| engine.py | Config/estado TTS (engines, idiomas, toggles) |
| chatterbox_server.py | Server persistente Chatterbox (model in GPU memory) |
| chatterbox_synth.py | Wrapper legacy (subprocess mode, fallback) |

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Para cambios de configs symlinkeadas (hypr, waybar, nvim, etc.), se aplican al instante (symlink directo al repo).
3. Para scripts: guardar en `linux/bin/`; el inventario de `scripts/link-dotfiles.sh` los enlaza.
4. Al anadir/renombrar una config, agregarla al inventario de `scripts/link-dotfiles.sh` y correrlo.
5. Ejecutar `~/dotfiles/scripts/publish.sh` para commitear (y pushear con confirmacion).

## Multi-maquina (laptop + desktop)

### Configs machine-specific

**`hyprland.lua`** usa condicionales por machine type:

```lua
local f = io.open(os.getenv("HOME") .. "/.config/machine-type", "r")
local machine = f and f:read("*a"):match("^%s*(.-)%s*$") or "laptop"
if f then f:close() end

if machine == "laptop" then
    -- monitores, touchpad, device, lid
end

if machine == "desktop" then
    -- monitores desktop
end

-- Shared: keybinds, appearance, autostart, etc.
```

**`hyprpaper`** tiene dos configs (la ruta `path =` la reescribe
`sync-wallpaper.sh`, no editarla a mano):
- `hyprpaper.conf` -> monitor `DP-2` (desktop)
- `hyprpaper-laptop.conf` -> monitor `eDP-1` (laptop)

**hyprexpo (overview `SUPER+Y`)**: la grilla 3D/fisheye es un parche local del
plugin (`linux/patches/hyprexpo-local.patch`) que **corre igual en laptop y
desktop**. `setup-omarchy.sh` lo compila/instala con `linux/bin/hyprexpo-rebuild.sh`
en `/var/cache/hyprpm/$USER/hyprexpo/hyprexpo.so`. `hyprland.lua` lo carga por
`hl.plugin.load(...)`. Tras `hyprpm update` hay que re-ejecutar el rebuild.
`EXPO_3D = true` en `hyprland.lua` (ver `linux/config/hypr/hyprexpo-changes.md`).

**Wallpaper (una sola fuente)**: el fondo canónico vive en el symlink de Omarchy
`~/.local/state/omarchy/current/background` (lo escribe `omarchy theme bg set`).
El hook `theme-set` -> `linux/bin/sync-wallpaper.sh` lo propaga a
`hyprpaper.conf` + recarga Hyprland (refresca hyprexpo). **Nunca** setear el fondo
con `hyprctl hyprpaper` directo: dejaría el symlink y la grilla desincronizados.
`setup-omarchy.sh` instala el hook (`omarchy hook install theme-set ...`).

### IPs LAN estaticas (fuera del pool DHCP)

- Laptop: `192.168.1.240` · Desktop: `192.168.1.241`
- Configuradas via `nmcli` en los perfiles de red
- IPs KVM flotante + ruta simetrica para lan-mouse

### SSH entre maquinas

```bash
ssh eztvn@desktop  # desde laptop
ssh eztvn@laptop   # desde desktop
```

- Resolucion via tailscale MagicDNS
- IPs tailscale: desktop `100.118.58.7`

### Reglas para AI (opencode)

1. **Nunca modificar bloques `if machine == "X"` sin preguntar.** Esos bloques son machine-specific.
2. **Configs compartidas** (keybinds, appearance, animations, window rules) se pueden editar libremente.
3. **Nada de NixOS.** El setup anterior se elimino; no recrear `flake.nix` ni ejecutar herramientas de NixOS.
4. **Al agregar un script**, guardarlo en `linux/bin/` y correr `scripts/link-dotfiles.sh` (no clobbea archivos reales de Omarchy).

## TTS (Text-to-Speech)

Sistema TTS con daemon + Chatterbox (Resemble AI).

**Motor principal:** Chatterbox Multilingual V3 (0.5B params, ~3GB VRAM RTX 3070)
- Soporta 23+ idiomas incluyendo espanol
- Server persistente (`chatterbox_server.py`) mantiene modelo en GPU
- Latencia: ~0.75-0.86s synth (post-carga inicial de ~9s)
- RTF: 0.80-0.94 (mas rapido que tiempo real)

**Uso:**
```bash
voice speak "hola mundo"          # español (default)
voice lang en && voice speak "hello"  # ingles
tts "hola"                        # bash function: voice lang + voice speak
tts -en "hello world"             # ingles via bash function
```

**Toggles:**
```bash
voice on/off        # enable/disable TTS
voice status        # estado completo
voice engine X lang # cambiar motor (chatterbox/piper/espeak)
```

**Chain de fallback:** chatterbox → piper → espeak

**Archivos:**
- `linux/voice/daemon.py` — daemon principal
- `linux/voice/chatterbox_server.py` — server persistente
- `linux/voice/engine.py` — config/estado
- `linux/home/.bashrc` — funcion `tts()`

## Handy (Speech-to-Text)

Handy es una app de speech-to-text.

**Uso:**
- `handy --start-hidden` — inicia minimizado (en autostart de Hyprland)
- `handy --toggle-post-process` — transcribe con post-procesado (keybind `F7`)
- `handy --toggle-transcription` — transcribe texto plano
- `handy — cancel` — cancela operacion actual

**Post-procesado:** provider Groq + modelo `openai/gpt-oss-120b`.

## Sunshine (Moonlight)

Sunshine = host de streaming Moonlight. Instalado en ambas maquinas.

**Gotcha importante:**
- `autoStart=false` es OBLIGATORIO. Con `Linger=yes`, graphical-session.target se activa al boot antes del login → sunshine arranca sin compositor Wayland → login colgado.
- Sunshine se arranca post-login desde `hyprland.lua`:
  `hl.exec_cmd("sleep 8 && systemctl --user start sunshine")`.

**Web UI:** `https://localhost:47990` (usuario `eztvn`, password en `~/.config/sunshine/.webui-password`).

**Pairing Moonlight (celular):**
- App Moonlight → anadir host (IP LAN o tailscale) → PIN → emparejar.
- Desktop: LAN `192.168.1.241` · tailscale `100.118.58.7`.

## Notificaciones fin de sesion (notify-sound)

`linux/config/opencode/plugins/notify-sound/plugin.js` notifica al terminar cada sesion:

1. **Campana local** (`pw-play complete.oga`) en `session.idle`.
2. **Resumen**: genera frase en espanol via Groq. Sin key → fallback "Sesion terminada".
3. **Push al celular** via ntfy.sh:
   - `session.idle` → "Sesion terminada — <resumen>" (prioridad 3)
   - `permission.updated` → "Pide permiso: <detalle>" (prioridad 4)

**Toggles** (estado local en `~/.local/state/opencode/`):

| Archivo | Valor |
|---------|-------|
| `notify-sound-enabled` | `'0'` = sin campana |
| `notify-voice-enabled` | `'1'` = hablar resumen (default apagado) |
| `notify-push-enabled` | `'0'` = sin push ntfy |

## Higiene de sueno (apagado 21:00)

Ambas maquinas se apagan solas a las 21:00 (hora Colombia).

- Timer systemd `bedtime.timer`: dispara `bedtime.service` a las **20:55** → aviso + gracia 5 min → `poweroff` a las 21:00.
- `Persistent = true`: compensa triggers perdidos.
- Escape: **`bedtime-skip`** crea flag `/run/bedtime-skip` (muere al reboot).
- Fuente de verdad: `linux/bin/bedtime.sh`.

## Modo consola (gamepad → interfaz)

Experiencia consola en PC: el gamepad controla el escritorio y la UI.

- **`input-remapper`**: daemon de sistema que re-emite teclado virtual desde pad.
- **Mapeos**: dpad → flechas, A/B → Enter/Esc, X → SUPER+SPACE, Y → SUPER+A, L = SUPER, R = SUPER+RETURN.
- **Auto modo juego**: `linux/bin/gamepad-watch.sh` detecta conexion/desconexion de pads → `game-mode.sh` / `exit`.
- **Evitar doble input**: `linux/bin/hypr-input-bridge.sh` escucha Hyprland socket y para/input-remapper segun foco.

## Lo que NO se gestiona

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes.

## Autonomia de ejecucion

Cuando modifiques archivos de configuracion relacionados con Linux (Hyprland, Waybar, Hyprpaper, PipeWire, systemd, keyd, GTK, Qt, shell, etc.), no te detengas despues de editar.

Despues de cada modificacion:

1. Ejecuta automaticamente todos los comandos necesarios para aplicar los cambios.
2. Verifica que los cambios se hayan aplicado correctamente.
3. Si aparece un error, investiga la causa e intenta solucionarlo.
4. Repite el ciclo de editar → aplicar → verificar hasta que el problema quede resuelto.

Solo solicita confirmacion para operaciones potencialmente destructivas:
- Eliminar archivos o directorios.
- Reinstalar o desinstalar paquetes.
- Sobrescribir datos importantes.
- Reiniciar o apagar el sistema.

Los reinicios de aplicaciones, recargas de servicios, validaciones de configuracion y operaciones rutinarias **no requieren confirmacion**.
