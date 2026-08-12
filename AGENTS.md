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
│   ├── sync-developing.sh # rsync laptop → desktop (~/developing)
│   ├── sync.sh          # (legacy)
│   ├── setup-tts.sh     # TTS
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
| `detect-machine.sh` | Detecta `laptop`/`desktop` por **hardware** (DMI chassis_type, batería, backlight). NO lee `machine-type`. Usado por `setup-nixos.sh` para no asumir laptop por defecto |
| `setup-nixos.sh` | **Un comando** en NixOS: clona repo + hardware-config + `nixos-rebuild` + Hermes. Detecta máquina por hardware; valida que el hardware-config coincida con el root UUID de la máquina actual |
| `sync-developing.sh` | rsync unidireccional laptop → desktop de `~/developing/` |
| `setup-tts.sh` | Instala/configura TTS |
| `publish.sh` | Commit + push con confirmacion |

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Para cambios de configs symlinkeadas (hypr, waybar, nvim, etc.), se aplican al instante (symlink directo al repo).
3. Para cambios de sistema/paquetes/home-manager: `sudo nixos-rebuild switch --flake ~/dotfiles#laptop` (o `#desktop`).
4. Ejecutar `~/dotfiles/scripts/publish.sh` para commitear (y pushear con confirmacion).

### Fresh install (NixOS)

```bash
# 1. Clonar el repo
git clone <url> ~/dotfiles

# 2. Un comando: hardware-config + paquetes + servicios + symlinks + Hermes
bash ~/dotfiles/scripts/setup-nixos.sh

# 3. Configurar Hermes
hermes setup

# 4. Recargar shell
exec bash
```

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
- `developing-sync.service` + `developing-sync.timer` → solo laptop (home.nix)

### Sync de ~/developing (laptop → desktop)

La laptop es la fuente de verdad de `~/developing/` (proyectos, datos de usuario,
NO gestionado por dotfiles). `developing-sync.timer` corre rsync unidireccional
laptop → desktop cada 10 min.

- Script: `scripts/sync-developing.sh` (rsync -az --delete a `desktop:~/developing/`)
- Units: `nixos/home.nix` (`lib.mkIf (machineType == "laptop")`)
- Desktop NixOS necesita SSH: `services.openssh` + authorized key de la laptop en
  `nixos/configuration.nix` (firewall: puerto 22 solo en `tailscale0`)
- Requiere llave SSH de la laptop autorizada en el desktop y `~/.ssh/config`
  (local, no se commitea) con `Host desktop` → IP tailscale

### Sync entre máquinas

Servicio systemd user (`dotfiles-sync.timer`) ejecuta `git pull --ff-only` cada 5 minutos.

Para subir cambios desde una máquina:
```bash
bash ~/dotfiles/scripts/publish.sh
```

La otra máquina recibe los cambios automáticamente.

### Reglas para AI (opencode)

1. **Nunca modificar bloques `if machine == "X"` sin preguntar.** Esos bloques son machine-specific.
2. **Configs compartidas** (keybinds, appearance, animations, window rules) se pueden editar libremente.
3. **Al agregar un script machine-specific**, añadirlo a `laptopScripts` en `nixos/home.nix`.
4. **Al agregar una unit systemd**, añadirla en `nixos/home.nix` (`systemd.user.services`).

## Handy (Speech-to-Text)

Handy es una app de speech-to-text. En NixOS se instala desde nixpkgs (`handy`).

**Uso:**
- `handy --start-hidden` — inicia minimizado (en autostart de Hyprland)
- `handy --toggle-transcription` — alterna transcripción on/off (keybind `F7`)
- `handy --toggle-post-process` — alterna post-procesamiento
- `handy --cancel` — cancela operación actual

**Autostart en hyprland.lua:**
```lua
hl.exec_cmd("handy --start-hidden")
```

**Keybind:**
```lua
hl.bind("F7", hl.dsp.exec_cmd("handy --toggle-transcription"))
```

## Notificaciones al celular (ntfy.sh)

`linux/config/opencode/plugins/notify-sound/plugin.js` notifica en dos canales cuando opencode trabaja:

1. **Sonido local** (`paplay`) en `session.idle` y `permission.asked`.
2. **Push al celular** vía ntfy.sh:
   - `session.idle` → "Sesion terminada" (prioridad 3)
   - `permission.asked` → "Pide permiso: <comando>" (prioridad 4)

Usa `fetch` nativo de Bun (sin curl). Tópico en `TOPIC` (`opencode-laptop`).

**Suscripción:** abrir `https://ntfy.sh/opencode-laptop` o la app ntfy (Android/iOS) y agregar el tópico.

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
- `nixos/hosts/hardware-configuration.*.nix` — placeholders, generar con `nixos-generate-config`

**Reglas:**
1. Al añadir un paquete, añadirlo a `nixos/modules/packages.nix`.
2. Al añadir un config nuevo, añadirlo al inventario de `nixos/home.nix`.
3. Los `hardware-configuration.*.nix` son por-máquina y NO se commitean con datos reales de particiones (se generan en instalación).
4. Los scripts de `linux/bin/` se symlinkean via `allScripts`; los laptop-only siguen la lista `laptopScripts`.
5. Comandos: `sudo nixos-rebuild switch --flake ~/dotfiles#laptop` (o `#desktop`).

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
