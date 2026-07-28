# AGENTS.md — Dotfiles

## Principio fundamental

**El repositorio (`~/dotfiles/`) es la única fuente de verdad.**

Todas las configuraciones gestionadas viven aquí. Los archivos en `~/.config/`, `~/.bashrc`, etc. son meros enlaces simbólicos que apuntan a este repositorio.

## Reglas para el agente

1. **Editar siempre dentro de `~/dotfiles/`.** Nunca modificar directamente `~/.config/`, `~/.bashrc` u otros destinos enlazados, salvo casos excepcionales justificados (ej: archivos del sistema fuera de control del repo).

2. **Toda nueva configuración debe añadirse a `install.sh`.** Si se agrega un nuevo archivo o directorio a `linux/config/`, `linux/home/`, `linux/bin/`, etc., hay que registrar su enlace simbólico en `install.sh`.

3. **Toda nueva configuración debe documentarse** en `docs/` o en este AGENTS.md, indicando ubicación, propósito y dependencias.

4. **Cambios mínimos.** No reescribir archivos completos sin necesidad. Usar `edit` con precisión quirúrgica.

5. **Antes de modificar una configuración existente, revisar el repositorio primero.** Respetar personalizaciones existentes del usuario.

6. **Configuraciones del sistema (`/etc/`, `/usr/share/`, etc.).** Si un archivo requiere instalación fuera del home, incluir la lógica necesaria en `install.sh` (con avisos de sudo cuando corresponda).

## Estructura del repositorio

```
dotfiles/
├── common/         # Configs multiplataforma (futuro)
├── linux/
│   ├── config/     # ~/.config/ (symlinkeado)
│   ├── home/       # ~/.bashrc, ~/.gitconfig, etc.
│   ├── bin/        # ~/.local/bin/ (scripts propios del usuario)
│   ├── xkb/        # Layout de teclado XKB (requiere sudo)
│   └── system/     # Archivos de sistema (/etc/, /usr/share/) — futuro
├── windows/        # Futuro
├── macos/          # Futuro
├── scripts/        # Scripts auxiliares generales
├── docs/           # Documentación adicional
├── install.sh      # Instalador idempotente (symlinks)
├── publish.sh      # Commit + push con confirmación
├── AGENTS.md       # Este archivo
└── README.md       # Visión general
```

## Inventario de configuraciones gestionadas

### Linux config (`linux/config/`)

| App/Archivo | Ruta destino | Tipo |
|-------------|-------------|------|
| hypr | `~/.config/hypr/` | directorio completo |
| waybar | `~/.config/waybar/` | directorio completo |
| kitty | `~/.config/kitty/` | directorio completo |
| rofi | `~/.config/rofi/` | directorio completo |
| nvim | `~/.config/nvim/` | directorio completo |
| kanata | `~/.config/kanata/` | directorio completo |
| fastfetch | `~/.config/fastfetch/` | directorio completo |
| mako | `~/.config/mako/config` | archivo suelto |
| swayosd | `~/.config/swayosd/` | directorio completo |
| avizo | `~/.config/avizo/` | directorio completo |
| btop | `~/.config/btop/btop.conf` | archivo suelto |
| gh | `~/.config/gh/` | directorio completo |
| libinput-gestures.conf | `~/.config/libinput-gestures.conf` | archivo suelto |
| mimeapps.list | `~/.config/mimeapps.list` | archivo suelto |
| user-dirs.dirs | `~/.config/user-dirs.dirs` | archivo suelto |
| user-dirs.locale | `~/.config/user-dirs.locale` | archivo suelto |

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

## Flujo de trabajo

1. Editar archivos dentro de `~/dotfiles/`.
2. Ejecutar `~/dotfiles/install.sh` para refrescar enlaces.
3. Ejecutar `~/dotfiles/publish.sh` para commitear (y pushear con confirmación).

## Lo que NO se gestiona

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes (Python, npm, dnf, etc.).