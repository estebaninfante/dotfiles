# AGENTS.md — Dotfiles

## Principio fundamental

**El repositorio (`~/dotfiles/`) es la unica fuente de verdad.**

Todas las configuraciones gestionadas viven aqui. Los archivos en `~/.config/`, `~/.bashrc`, etc. son enlaces simbolicos que apuntan a este repositorio (via home-manager `mkOutOfStoreSymlink`).

## Reglas permanentes

1. **Editar siempre dentro de `~/dotfiles/`.** Nunca modificar directamente `~/.config/`, `~/.bashrc` u otros destinos enlazados. Excepcion: migraciones puntuales o emergencias justificadas.

2. **Toda nueva configuracion debe anadirse al inventario de `nixos/home.nix`.** No hay excepcion. Anadir una entrada a la lista correspondiente (`configDirs`, `configFiles`, `homeFiles`, `allScripts`, `laptopScripts`) y el symlink se genera solo en el siguiente rebuild.

3. **Antes de crear un script nuevo, comprobar si uno existente puede reutilizarse o extenderse.** No duplicar funcionalidad.

4. **Evitar duplicar logica.** Si un patron se repite, abstraerlo en una funcion.

5. **Usar cambios minimos.** No reescribir archivos completos sin necesidad. Usar `edit` con precision quirurgica.

6. **Antes de modificar una configuracion existente, revisar el repositorio primero.** Respetar personalizaciones existentes del usuario.

7. **Al anadir un paquete, anadirlo a `nixos/modules/packages.nix`.**

8. **Configuraciones del sistema** (`services.*`, `environment.etc`, drivers, etc.) van declarativas en `nixos/configuration.nix` o `nixos/hosts/*.nix`. Nada de copiar a `/etc/` a mano.

## Estructura del repositorio

```
dotfiles/
├── flake.nix            # inputs (nixpkgs, home-manager) + hosts laptop/desktop
├── nixos/
│   ├── configuration.nix # base comun (servicios, usuario, GDM, Hyprland, keyd)
│   ├── home.nix          # home-manager: symlinks a linux/config, linux/bin, units
│   ├── modules/          # packages.nix, keyboard.nix, sudoers.nix
│   └── hosts/            # laptop.nix, desktop.nix + hardware-configuration.*.nix
├── linux/
│   ├── config/          # ~/.config/ (symlinkeado por home.nix)
│   ├── home/            # ~/.bashrc, ~/.gitconfig
│   ├── bin/             # ~/.local/bin/ (scripts propios)
│   ├── xkb/             # Layout de teclado XKB (fuente de verdad: dvk_prog)
│   ├── patches/         # patches (lan-mouse AltGr, waybar Lua dispatch)
│   └── system/          # keyd, NetworkManager dispatcher
├── scripts/
│   ├── setup-nixos.sh   # Un comando en NixOS: clona + hardware-config + rebuild + Hermes
│   ├── detect-machine.sh# Detecta laptop/desktop por hardware
│   ├── sync-developing.sh # sync manual legacy; Syncthing sincroniza ~/developing
│   ├── sync.sh          # (legacy)
│   ├── setup-tts.sh     # TTS
│   ├── setup-secrets.sh # Configura/verifica claves y secrets post-install
│   └── publish.sh       # Commit + push con confirmacion
├── AGENTS.md
└── README.md
```

## Inventario de configuraciones gestionadas

### Linux config (`linux/config/`) — directorios completos

Gestionados por `nixos/home.nix` (`configDirs`):

| App | Ruta destino |
|-----|-------------|
| hypr | `~/.config/hypr/` |
| waybar | `~/.config/waybar/` |
| kitty | `~/.config/kitty/` |
| rofi | `~/.config/rofi/` |
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

### Linux config — archivos sueltos

| Archivo | Ruta destino |
|---------|-------------|
| libinput-gestures.conf | `~/.config/libinput-gestures.conf` |
| mimeapps.list | `~/.config/mimeapps.list` |
| user-dirs.dirs | `~/.config/user-dirs.dirs` |
| user-dirs.locale | `~/.config/user-dirs.locale` |

### Lan-mouse (`linux/config/lan-mouse/`)

| Archivo | Descripción |
|---------|-------------|
| `lan-mouse.pem` | PEM compartido entre máquinas |
| `config.laptop.toml` / `config.desktop.toml` | Config por máquina; se copia a `~/.config/lan-mouse/config.toml` (writable, lan-mouse guarda estado) |

### Home (`linux/home/`)

| Archivo | Ruta destino |
|---------|-------------|
| .bashrc | `~/.bashrc` |
| .gitconfig | `~/.gitconfig` |

### Scripts (`linux/bin/`)

Todos los scripts propios de `~/.local/bin/` (excluye ejecutables instalados por paquetes). Gestionados por `nixos/home.nix` (`allScripts` + `laptopScripts`).

### XKB (`linux/xkb/`)

`dvk_prog` es la fuente de verdad. Lo consume `nixos/modules/keyboard.nix` para TTY, X11/GDM y Wayland (no requiere symlink manual).

### keyd (`linux/system/keyd/default.conf`)

Config de keyd (Caps Lock como Super, overload leftalt→numpad, capa nav, composite control+numpad). El servicio lo define `nixos/configuration.nix` (`services.keyd`).

## Scripts (`scripts/`)

| Script | Descripción |
|--------|-------------|
| `detect-machine.sh` | Detecta `laptop`/`desktop` por **hardware** (DMI chassis_type, batería, backlight). NO lee `machine-type`. Usado por `setup-nixos.sh` y `rebuild.sh` para no asumir laptop por defecto |
| `rebuild.sh` | **Wrapper OBLIGATORIO de `nixos-rebuild`**: detecta máquina por hardware + valida root UUID contra `hardware-configuration.<machine>.nix`; aborta si no coinciden. Uso: `bash ~/dotfiles/scripts/rebuild.sh [switch|boot|test|build|dry-build]` |
| `setup-nixos.sh` | **Un comando** en NixOS: clona repo + hardware-config + `nixos-rebuild` + Hermes. Detecta máquina por hardware; valida que el hardware-config coincida con el root UUID de la máquina actual |
| `sync-developing.sh` | sync manual legacy; `~/developing/` usa Syncthing bidireccional |
| `setup-tts.sh` | Instala/configura TTS |
| `setup-secrets.sh` | Configura/verifica claves y secrets post-install (SSH host trust, tailscale auth, sunshine creds, gh auth, syncthing, handy Groq, machine-type). Idempotente, no destructivo |
| `publish.sh` | Commit + push con confirmacion |

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Para cambios de configs symlinkeadas (hypr, waybar, nvim, etc.), se aplican al instante (symlink directo al repo).
3. Para cambios de sistema/paquetes/home-manager: `bash ~/dotfiles/scripts/rebuild.sh` (detecta la máquina, valida el hardware-config y ejecuta `nixos-rebuild switch`). **PROHIBIDO** pasar el host a mano (`#laptop`/`#desktop`) — un host equivocado genera una generación con hardware de otra máquina y rompe el boot (emergency mode). Esto ya pasó: gen 72 inservible en desktop.
4. Ejecutar `~/dotfiles/scripts/publish.sh` para commitear (y pushear con confirmacion).

### Fresh install (NixOS)

```bash
# 1. Clonar el repo
git clone <url> ~/dotfiles

# 2. Un comando: hardware-config + paquetes + servicios + symlinks + Hermes
bash ~/dotfiles/scripts/setup-nixos.sh

# 3. Configurar Hermes
hermes setup

# 4. Claves/secrets pendientes (tailscale auth, sunshine creds, gh auth,
#    syncthing pairing, ssh host trust...) — idempotente, pide solo lo que falte.
bash ~/dotfiles/scripts/setup-secrets.sh

# 5. Recargar shell
exec bash
```

### Secrets y llaves tras fresh install

`scripts/setup-secrets.sh` configura/verifica todo lo que necesita claves o
estado local (SSH host trust, tailscale auth, sunshine creds, gh auth,
syncthing pairing, handy Groq key, machine-type). Idempotente y no destructivo:
solo pide los secrets que faltan y reporta PASS/SKIP/MANUAL por item.

Para configurarlo rápido con opencode: **«corre scripts/setup-secrets.sh y dime
qué falta»** — el agente lo ejecuta y resuelve cada item.

Ver `nixos/README.md` para la guia de instalacion completa.

## Multi-máquina (laptop + desktop)

### Detección

El archivo `~/.config/machine-type` contiene `laptop` o `desktop`. No se commitea al repo (es local a cada máquina).

`setup-nixos.sh` lee este archivo al inicio. **Si no existe, NO asume `laptop`**: lo detecta por hardware con `scripts/detect-machine.sh` (DMI chassis_type, batería, backlight). Esto evita el bug de instalar el desktop como laptop.

`setup-nixos.sh` además valida que `nixos/hosts/hardware-configuration.<machine>.nix` coincida con el **root UUID de la máquina actual** (`findmnt -no UUID /`). Si el archivo contiene hardware de otra máquina, lo regenera automáticamente en vez de montar particiones ajenas.

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

**`hyprpaper`** tiene dos configs:
- `hyprpaper-laptop.conf` → monitor eDP-2
- `hyprpaper-desktop.conf` → monitor DP-1

El autostart en hyprland.lua carga la correcta:
```lua
hl.exec_cmd("hyprpaper --config ~/.config/hypr/hyprpaper-" .. machine .. ".conf")
```

**Scripts machine-specific** (solo se enlazan en laptop, `laptopScripts` en home.nix):
- `toggle-lid.sh`
- `lid-inhibit-waybar.sh`
- `waybar-battery-top`
- `trackpad-dwt-daemon`
- `reload-hyprpaper.sh`
- `gpu-mode.sh` → toggle manual NVIDIA (ahorro batería vs gaming)

### GPU NVIDIA (laptop híbrida)

**Caso:** iGPU AMD (amdgpu) maneja el display; dGPU NVIDIA (RTX 4060) solo para juegos.

**`gpu-mode.sh`** controla la NVIDIA via Runtime PM:
- `gpu-mode.sh battery` → `power/control=auto`: GPU en D3cold cuando inactiva → máximo ahorro de batería
- `gpu-mode.sh gaming` → `power/control=on` + `nvidia-smi -pm 1`: GPU activa y lista
- `gpu-mode.sh toggle` / `status`

Accesible desde `rofi-power-mode.sh` (menú "Modo Energia"). Requiere sudo NOPASSWD (definido en `nixos/modules/sudoers.nix`):
- `tee /sys/bus/pci/devices/*/power/control`
- `nvidia-smi`

Config NVIDIA en `nixos/hosts/laptop.nix` (`prime.offload`, `powerManagement.enable = false`).

**Systemd units:**
- `trackpad-dwt.service` → solo laptop (home.nix)
- `dotfiles-sync.service` + `dotfiles-sync.timer` → ambas máquinas (home.nix)
- Syncthing `developing` → ambas máquinas (configuration.nix)

### Sync de ~/developing (laptop ↔ desktop)

`~/developing/` usa Syncthing bidireccional en tiempo real. NixOS configura ambos
dispositivos y carpeta `developing` tipo `sendreceive`, con watcher de filesystem
y versionado simple de cinco versiones. Puertos LAN: TCP/UDP 22000 y UDP 21027.
También anuncia IPs Tailscale para sincronizar fuera de casa cuando ambos equipos
están encendidos. Si un equipo está apagado, Syncthing conserva cambios locales
y los entrega al reconectar; no existe sincronización mientras equipo está apagado.
`.stignore` excluye `node_modules`, `.next`, `dist`, builds, caches y logs; se
regeneran localmente con `pnpm install` o scripts del proyecto.

`scripts/sync-developing.sh` queda como herramienta manual legacy; no existe timer
rsync para evitar carreras y borrados unidireccionales.

### Sync entre máquinas

Servicio systemd user (`dotfiles-sync.timer`) ejecuta `git pull --ff-only` cada 5 minutos.

Para subir cambios desde una máquina:
```bash
bash ~/dotfiles/scripts/publish.sh
```

La otra máquina recibe los cambios automáticamente.

### IPs LAN estáticas (fuera del pool DHCP)

Para lan-mouse/syncthing ambas máquinas usan IP fija **fuera del pool DHCP**
(el router nunca las asignará a otro equipo):

- Laptop: `192.168.1.240` · Desktop: `192.168.1.241`
- Configuradas via `nmcli` en los perfiles de red de casa (`ipv4.method=manual`,
  `802-11-wireless.powersave=2` y `bssid` pineado al router para minimizar
  stalls de KVM). Los perfiles NM
  viven en `/etc/NetworkManager/system-connections/` (local a cada máquina,
  NO gestionados por el repo).
- ⚠️ Lag de lan-mouse en WiFi: el router usa canal 5GHz DFS (112/5560MHz) y hay
  un repetidor propio co-canal (`74:93:da:a1:0f:1a`, IP .48). Ráfagas de
  100-200ms incluso hacia el gateway. Fix real: fijar router a canal 5GHz
  no-DFS (36-48) — pendiente del usuario en el router.
- Referencias hardcodeadas: `linux/config/lan-mouse/config.*.toml`,
  syncthing en `nixos/configuration.nix`, docs.
- Dispatcher `90-lan-mouse` (instalado via `networking.networkmanager.dispatcherScripts`):
  reinicia lan-mouse al conectar a red de casa + watchdog que detecta conflicto
  ARP/IP no configurable y avisa por ntfy (`opencode-laptop`).

### SSH entre máquinas

Ambas máquinas tienen `services.openssh` habilitado (solo llave pública, sin
password, puerto 22 únicamente en la interfaz tailscale). Para conectarse:

```bash
# desde la laptop hacia el desktop
ssh eztvn@desktop

# desde el desktop hacia la laptop
ssh eztvn@laptop
```

- `desktop` / `laptop` se resuelven vía tailscale MagicDNS (solo cuando la
  otra máquina está online en la tailnet).
- IPs tailscale: desktop `100.118.58.7`; laptop ver con `tailscale ip -4 laptop`.
- La llave de la laptop está autorizada en el desktop
  (`users.users.eztvn.openssh.authorizedKeys.keys` en `configuration.nix`).
  Para el sentido inverso (desktop → laptop) hay que autorizar la llave del
  desktop en la laptop.

### Reglas para AI (opencode)

1. **Nunca modificar bloques `if machine == "X"` sin preguntar.** Esos bloques son machine-specific.
2. **Configs compartidas** (keybinds, appearance, animations, window rules) se pueden editar libremente.
3. **Al agregar un script machine-specific**, añadirlo a `laptopScripts` en `nixos/home.nix`.
4. **Al agregar una unit systemd**, añadirla en `nixos/home.nix` (`systemd.user.services`).
5. **NUNCA ejecutar `sudo nixos-rebuild` con host hardcodeado** (`#laptop`/`#desktop`). SIEMPRE `bash ~/dotfiles/scripts/rebuild.sh`, que detecta la máquina por hardware y valida el root UUID. Un rebuild con host equivocado rompe el boot (ya ocurrió: gen 72 inservible en desktop).

## Handy (Speech-to-Text)

Handy es una app de speech-to-text. En NixOS se instala desde el flake
upstream `github:cjpais/Handy` (v0.9.5+, no nixpkgs que va atrasado en 0.9.1).

**Uso:**
- `handy --start-hidden` — inicia minimizado (en autostart de Hyprland)
- `handy --toggle-post-process` — transcribe SIEMPRE con post-procesado (keybind `F7`)
- `handy --toggle-transcription` — transcribe texto plano (sin post-procesado)
- `handy --cancel` — cancela operación actual

**Post-procesado:** provider Groq + modelo `openai/gpt-oss-120b`. Config
persistente en `~/.local/share/com.pais.handy/settings_store.json`
(prompts custom con variable `${output}`). El prompt activo "Personalizado"
corrige ortografía, quita muletillas, convierte dictado en texto escrito
natural y soporta comandos dictados ("coma", "nueva línea", "haz una lista"...).

**Autostart en hyprland.lua:**
```lua
hl.exec_cmd("handy --start-hidden")
```

**Keybind:**
```lua
hl.bind("F7", hl.dsp.exec_cmd("handy --toggle-post-process"))
```

## Sunshine (Moonlight)

Sunshine = host de streaming Moonlight. Instalado en AMBAS máquinas via el
módulo NixOS `services.sunshine` (`nixos/configuration.nix`).

```nix
services.sunshine = {
  enable = true;
  openFirewall = true;   # abre puertos TCP/UDP de Moonlight
  autoStart = false;     # ver gotcha abajo
  capSysAdmin = false;   # captura via Wayland (portal), no KMS
};
```

**Paquete por máquina:**
- Desktop (`nixos/hosts/desktop.nix`): `services.sunshine.package = pkgs.sunshine.override { cudaSupport = true; }` → NVENC (RTX 3070) para jugar en streaming.
- Laptop: paquete plain (software) → suficiente para solo ver. La laptop usa dGPU híbrida; software evita depender de `gpu-mode`.

**Gotcha (IMPORTANTE, causó cuelgue de login):**
- `autoStart=false` es OBLIGATORIO. Con `Linger=yes` + el servicio
  `graphical-session-holder` (WantedBy=default.target + Wants=graphical-session.target),
  `graphical-session.target` se activa al BOOT (antes del login). Si sunshine
  tiene `wantedBy=graphical-session.target` arranca al boot sin compositor
  Wayland → captura via KMS → agarra `/dev/dri/card1` → GDM "No GPUs found"
  → login colgado.
- Sunshine se arranca post-login desde `hyprland.lua`:
  `hl.exec_cmd("sleep 8 && systemctl --user start sunshine")`.

**⚠️ Build NVENC:** `sunshine.override { cudaSupport = true; }` recompila
sunshine desde fuente. Compilar con paralelismo default (`max-jobs=24`, sin
swap) OOM y congela el sistema. Usar SIEMPRE paralelismo controlado (solo
ejecutar EN el desktop):
`sudo env NIX_CONFIG="max-jobs = 2"$'\n'"cores = 8" nixos-rebuild switch --flake ~/dotfiles#desktop`.

**Web UI + credenciales:**
- Web UI: `https://localhost:47990` (usuario `eztvn`, password en
  `~/.config/sunshine/.webui-password` — local, NO en el repo).
- `sunshine --creds eztvn <pass>` setea credenciales sin navegador.
- Estado (cert, apps, pairings) vive en `~/.config/sunshine/` (dir real, no
  symlink al repo). NO sincronizar `sunshine_state.json` entre máquinas:
  cada host tiene su propio certificado/pairing.

**Pairing Moonlight (celular):**
- App Moonlight → añadir host (IP LAN o tailscale) → PIN → emparejar.
- Desktop: LAN `192.168.1.241` · tailscale `100.118.58.7`.
- Laptop: LAN `192.168.1.240` · ver `tailscale ip -4 laptop`.
- Encoder NVENC ya auto-detectado en desktop (`h264_nvenc`/`hevc_nvenc`); AV1
  no soportado por RTX 3070.

## Notificaciones fin de sesión (notify-sound)

`linux/config/opencode/plugins/notify-sound/plugin.js` (registrado en
`linux/config/opencode/opencode.json`) notifica al terminar cada sesión:

1. **Campana local** (`pw-play complete.oga` del tema freedesktop) en `session.idle`.
2. **Resumen**: lee la transcripción via SDK y si existe key Groq
   (`llama-3.1-8b-instant`) genera UNA frase en español técnico simple
   (qué se hizo y si funcionó). Sale por `notify-send`; por voz solo con
   el toggle VOZ activo (comando `voice speak`). Sin key → fallback
   "Sesión <título> terminada".
3. **Push al celular** vía ntfy.sh (`fetch` nativo de Bun, sin curl):
   - `session.idle` → "Sesion terminada — <resumen>" (prioridad 3)
   - `permission.updated` → "Pide permiso: <detalle>" (prioridad 4)

**Toggles** (estado local, escritos por la sección NOTIFICACIONES de
quickshell; ausente = comportamiento indicado):

| Archivo (`~/.local/state/opencode/`) | Valor |
|--------------------------------------|-------|
| `notify-sound-enabled` | `'0'` = sin campana |
| `notify-voice-enabled` | `'1'` = hablar resumen (default apagado) |
| `notify-push-enabled` | `'0'` = sin push ntfy |

Key Groq: `~/.local/state/opencode/notify-groq-key` (chmod 600, NUNCA en
el repo). Privacidad: sin key, la conversación no sale de la máquina.

Plugins anidados NO se autodescubren: todo plugin en subdirectorio de
`~/.config/opencode/plugins/` debe registrarse en `opencode.json`
(`"plugin": ["file:///..."]`). Eventos: idle llega como `session.idle`
derivado Y como `session.status` crudo (dedup interno); permisos como
`permission.updated`.

**Suscripción push:** abrir `https://ntfy.sh/opencode-laptop` o la app
ntfy (Android/iOS) y agregar el tópico.

## Higiene de sueño (apagado 21:00)

Ambas máquinas se apagan solas a las 21:00 (hora Colombia, `time.timeZone = "America/Bogota"`).

- Timer systemd de sistema `bedtime.timer` (compartido en
  `nixos/configuration.nix`): dispara `bedtime.service` a las **20:55** →
  aviso (`notify-send` + `wall`) + gracia 5 min → `poweroff` a las 21:00.
- `Persistent = true`: si la máquina estaba apagada a las 21:00 y se enciende
  después (ej. 11PM), el trigger perdido compensa al boot → avisa y apaga igual.
- Escape puntual: **`bedtime-skip`** crea flag `/run/bedtime-skip` con fecha de
  hoy; cancela el apagado de esa noche incluso durante los 5 min de gracia.
  Muere al reboot (la noche siguiente vuelve el apagado).
- Fuente de verdad del script: `linux/bin/bedtime.sh` (ambos scripts en
  `allScripts`, `nixos/home.nix`). Servicio corre como root con PATH de sistema.

## Lo que NO se gestiona

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes (Python, npm, etc.).

## NixOS (`nixos/` + `flake.nix`)

El repo es la unica fuente de verdad: home-manager crea symlinks directos
a `linux/config/`, `linux/home/` y `linux/bin/` via `mkOutOfStoreSymlink`.

- `flake.nix` — inputs (nixpkgs, home-manager) y hosts `laptop`/`desktop`
- `nixos/configuration.nix` — base comun (servicios, fuentes, usuario, GDM, Hyprland, keyd)
- `nixos/home.nix` — home-manager: symlinks a linux/config, linux/bin, units
- `nixos/modules/packages.nix` — paquetes del sistema (nixpkgs)
- `nixos/modules/keyboard.nix` — layout dvk_prog en TTY, X11/GDM y Wayland
- `nixos/modules/sudoers.nix` — NOPASSWD (gpu-mode.sh)
- `nixos/hosts/laptop.nix` — NVIDIA hybrid, keyd
- `nixos/hosts/desktop.nix` — NVIDIA RTX 3070 (dGPU unica)
- `nixos/hosts/hardware-configuration.*.nix` — hardware REAL por máquina (generado con `nixos-generate-config`), commiteado. `setup-nixos.sh` lo regenera si el root UUID no coincide con la máquina actual

**Reglas:**
1. Al añadir un paquete, añadirlo a `nixos/modules/packages.nix`.
2. Al añadir un config nuevo, añadirlo al inventario de `nixos/home.nix`.
3. Los `hardware-configuration.*.nix` son por-máquina y se commitean con el hardware real de cada una (`nixos-generate-config`). Excepción a la regla de no commitear datos de máquina: el hardware-config es necesario para fresh installs; `setup-nixos.sh` valida por root UUID y regenera si la máquina difiere. **Lo que NO se commitea**: claves, tokens, passwords ni datos de usuario.
4. Los scripts de `linux/bin/` se symlinkean via `allScripts`; los laptop-only siguen la lista `laptopScripts`.
5. Comandos: SIEMPRE via `bash ~/dotfiles/scripts/rebuild.sh [switch|boot|test|build|dry-build]`. Nunca invocar `nixos-rebuild` con `--flake ~/dotfiles#laptop|#desktop` hardcodeado: el script detecta la máquina por hardware y valida el root UUID contra `hardware-configuration.<machine>.nix`; aborta si no coinciden.

Ver `nixos/README.md` para la guía de instalación completa.

## Autonomía de ejecución

Cuando modifiques archivos de configuración relacionados con Linux (Hyprland, Waybar, Hyprpaper, PipeWire, systemd, keyd, GDM, GTK, Qt, shell, etc.), no te detengas después de editar.

Después de cada modificación:

1. Ejecuta automáticamente todos los comandos necesarios para aplicar los cambios (recargar servicios, reiniciar procesos, ejecutar scripts, `nixos-rebuild switch`, etc.).
2. Verifica que los cambios se hayan aplicado correctamente mediante los comandos de validación apropiados.
3. Si aparece un error, investiga la causa e intenta solucionarlo de forma autónoma antes de pedirme ayuda.
4. Repite el ciclo de editar → aplicar → verificar hasta que el problema quede resuelto o ya no puedas avanzar sin intervención humana.
5. Siempre que sea posible, realiza tú mismo las acciones necesarias. No me pidas que ejecute comandos manualmente si puedes hacerlo tú.

Solo solicita confirmación para operaciones potencialmente destructivas o de alto impacto, como:

- Eliminar archivos o directorios.
- Reinstalar o desinstalar paquetes.
- Sobrescribir datos importantes.
- Reiniciar o apagar el sistema.
- Cambios irreversibles o con riesgo de pérdida de datos.

Los reinicios de aplicaciones, recargas de servicios, validaciones de configuración, consultas con `journalctl`, ejecución de scripts del repositorio y demás operaciones rutinarias **no requieren confirmación**.
