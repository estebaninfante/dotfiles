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
│   ├── xkb/             # Layout de teclado XKB (requiere sudo)
│   └── system/          # Archivos de sistema (/etc/, /usr/share/) — futuro
├── windows/             # Futuro
├── macos/               # Futuro
├── scripts/
│   ├── install.sh       # Instalador idempotente basado en inventarios
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

Todos los scripts propios de `~/.local/bin/` (excluye ejecutables instalados por Python o paquetes del sistema).

### XKB (`linux/xkb/`)

| Archivo | Ruta destino |
|---------|-------------|
| dvk_prog | `/usr/share/xkeyboard-config-2/symbols/dvk_prog` (requiere sudo) |
| dvk_prog | `/usr/share/X11/xkb/symbols/dvk_prog` (fallback) |

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Ejecutar `~/dotfiles/scripts/install.sh` (o `--force`) para refrescar enlaces.
3. Ejecutar `~/dotfiles/scripts/publish.sh` para commitear (y pushear con confirmacion).

## Lo que NO se gestiona

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes (Python, npm, dnf, etc.).