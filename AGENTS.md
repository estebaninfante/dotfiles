# AGENTS.md — Dotfiles

## Principio fundamental

**El repositorio (`~/dotfiles/`) es la unica fuente de verdad.**

Todas las configuraciones gestionadas viven aqui. Los archivos en `~/.config/`, `~/.bashrc`, etc. son enlaces simbolicos que apuntan a este repositorio.

## Reglas permanentes

1. **Editar siempre dentro de `~/dotfiles/`.** Nunca modificar directamente `~/.config/`, `~/.bashrc` u otros destinos enlazados. Excepcion: migraciones puntuales o emergencias justificadas.

2. **Toda nueva configuracion debe anadirse al inventario de `scripts/install.sh`.** No hay excepcion. Anadir una entrada al array correspondiente (`CONFIG_DIRS`, `CONFIG_FILES`, `HOME_FILES`, etc.) y la logica se ejecuta sola.

3. **Antes de crear un script nuevo, comprobar si uno existente puede reutilizarse o extenderse.** No duplicar funcionalidad.

4. **Evitar duplicar logica.** Si un patron se repite, abstraerlo en una funcion.

5. **Usar cambios minimos.** No reescribir archivos completos sin necesidad. Usar `edit` con precision quirurgica.

6. **Antes de modificar una configuracion existente, revisar el repositorio primero.** Respetar personalizaciones existentes del usuario.

7. **Mantener `scripts/install.sh` idempotente.** Ejecucion multiple no debe romper nada.

8. **Configuraciones del sistema (`/etc/`, `/usr/share/`, etc.).** Incluir la logica en `install.sh` con avisos de sudo. Preferir symlinks sobre copias.

## Estructura del repositorio

```
dotfiles/
├── common/              # Configs multiplataforma (futuro)
├── linux/
│   ├── config/          # ~/.config/ (symlinkeado)
│   ├── home/            # ~/.bashrc, ~/.gitconfig, etc.
│   ├── bin/             # ~/.local/bin/ (scripts propios del usuario)
│   ├── packages/        # Manifiestos de paquetes (repos, dnf, flatpak, wallpapers)
│   ├── xkb/             # Layout de teclado XKB (requiere sudo)
│   └── system/          # Archivos de sistema (/etc/, /usr/share/) — futuro
├── windows/             # Futuro
├── macos/               # Futuro
├── scripts/
│   ├── install.sh       # Instalador idempotente basado en inventarios
│   ├── setup-packages.sh# Instala repos + dnf + flatpak + wallpapers desde cero
│   ├── backup-packages.sh # Captura estado actual del sistema a manifiestos
│   └── publish.sh       # Commit + push con confirmacion
├── docs/                # Documentacion adicional
├── AGENTS.md            # Este archivo
└── README.md            # Vision general
```

## Inventario de configuraciones gestionadas

### Linux config (`linux/config/`) — directorios completos

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
| swayosd | `~/.config/swayosd/` |
| avizo | `~/.config/avizo/` |
| btop | `~/.config/btop/` |
| gh | `~/.config/gh/` |

### Flatpak config (`linux/config/`) — flatpak apps

| App | Ruta destino |
|-----|-------------|
| obs-studio | `~/.var/app/com.obsproject.Studio/config/obs-studio/` |

### GDM (login screen) — configuración manual con sudo

| Archivo | Descripción |
|---------|-------------|
| `linux/config/gdm/black.png` | Fondo negro 1x1 para pantalla de login GDM |
| `linux/bin/setup-gdm-dark.sh` | Script que configura GDM (fondo negro, tema oscuro, cursor) |

Ejecutar `setup-gdm-dark.sh` requiere sudo. Usa dconf override (método oficial Fedora): crea `/etc/dconf/db/gdm.d/01-dark-background` y compila la base de datos. No modifica archivos del usuario `gdm`.

### Linux config — archivos sueltos

| Archivo | Ruta destino |
|---------|-------------|
| libinput-gestures.conf | `~/.config/libinput-gestures.conf` |
| mimeapps.list | `~/.config/mimeapps.list` |
| user-dirs.dirs | `~/.config/user-dirs.dirs` |
| user-dirs.locale | `~/.config/user-dirs.locale` |
| gdm/black.png | `~/.config/gdm/black.png` |

### Home (`linux/home/`)

| Archivo | Ruta destino |
|---------|-------------|
| .bashrc | `~/.bashrc` |
| .gitconfig | `~/.gitconfig` |

### Scripts (`linux/bin/`)

Todos los scripts propios de `~/.local/bin/` (excluye ejecutables instalados por Python o paquetes del sistema).

### XKB (`linux/xkb/`)

| Archivo | Ruta destino |
|---------|-------------|
| dvk_prog | `/usr/share/xkeyboard-config-2/symbols/dvk_prog` (requiere sudo) |
| dvk_prog | `/usr/share/X11/xkb/symbols/dvk_prog` (fallback) |

## Paquetes (`linux/packages/`)

| Archivo | Descripción |
|---------|-------------|
| `repos.sh` | Agrega COPR, RPM Fusion, Brave, Chrome, Flathub |
| `dnf-packages.txt` | Lista de paquetes RPM (uno por línea, `#` para comentarios) |
| `flatpak-packages.txt` | Lista de apps Flatpak (application ID, uno por línea) |
| `pip-packages.txt` | Paquetes pip (opcional) |
| `wallpaper/` | Wallpapers default, se copian a `~/Imágenes/` |

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Ejecutar `~/dotfiles/scripts/install.sh` (o `--force`) para refrescar enlaces.
   - Opción `--packages`: ejecuta `setup-packages.sh` antes de enlazar configs.
3. Ejecutar `~/dotfiles/scripts/publish.sh` para commitear (y pushear con confirmacion).

### Fresh install (después de instalar Fedora)

```bash
# 1. Clonar el repo
git clone <url> ~/dotfiles

# 2. Instalar TODO: repos + paquetes + configs + wallpapers
bash ~/dotfiles/scripts/install.sh --packages --force

# 3. (Opcional) Configuraciones del sistema
sudo bash ~/dotfiles/linux/bin/setup-gdm-dark.sh
# XKB manual:
sudo ln -s ~/dotfiles/linux/xkb/dvk_prog /usr/share/X11/xkb/symbols/dvk_prog

# 4. Recargar shell
exec bash
```

### Backup (antes de reinstalar)

```bash
bash ~/dotfiles/scripts/backup-packages.sh
# Revisa los archivos en linux/packages/ y edita lo que necesites
# Luego haz commit y push
```

## Multi-máquina (laptop + desktop)

### Detección

El archivo `~/.config/machine-type` contiene `laptop` o `desktop`. No se commitea al repo (es local a cada máquina).

`install.sh` lee este archivo al inicio. Si no existe, asume `laptop`.

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

**Scripts machine-specific** (solo se enlazan en laptop):
- `toggle-lid.sh`
- `lid-inhibit-waybar.sh`
- `waybar-battery-top`
- `trackpad-dwt-daemon`
- `reload-hyprpaper.sh`

**Systemd units:**
- `trackpad-dwt.service` → solo laptop
- `dotfiles-sync.service` + `dotfiles-sync.timer` → ambas máquinas

### Sync entre máquinas

Servicio systemd user (`dotfiles-sync.timer`) ejecuta `git pull --ff-only` cada 5 minutos.

Para subir cambios desde una máquina:
```bash
bash ~/dotfiles/scripts/publish.sh
```

La otra máquina recibe los cambios automáticamente (o al reiniciar: `systemctl --user daemon-reload && systemctl --user enable --now dotfiles-sync.timer`).

### Reglas para AI (opencode)

1. **Nunca modificar bloques `if machine == "X"` sin preguntar.** Esos bloques son machine-specific.
2. **Configs compartidas** (keybinds, appearance, animations, window rules) se pueden editar libremente.
3. **Al agregar un script machine-specific**, añadirlo a `LAPTOP_SCRIPTS` o crear un array `DESKTOP_SCRIPTS` en install.sh.
4. **Al agregar una unit systemd**, añadirla a `SYSTEMD_UNITS` en install.sh.

## Lo que NO se gestiona

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes (Python, npm, dnf, etc.).

## Autonomía de ejecución

Cuando modifiques archivos de configuración relacionados con Linux (Hyprland, Waybar, Hyprpaper, PipeWire, systemd, keyd, GDM, GTK, Qt, shell, etc.), no te detengas después de editar.

Después de cada modificación:

1. Ejecuta automáticamente todos los comandos necesarios para aplicar los cambios (recargar servicios, reiniciar procesos, ejecutar scripts, etc.).
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
