# dotfiles

Configuraciones personales y automatización de instalación para Fedora Linux.
Este repositorio es la **única fuente de verdad** — todo se edita aquí y se sincroniza mediante symlinks.

## Filosofía

Después de reinstalar Fedora varias veces, nació este sistema: un solo comando y tu máquina queda exactamente como la tenías.

1. **Manifiestos de paquetes** → qué instalar (DNF, Flatpak, Pip)
2. **Script de setup** → repos + paquetes + wallpapers
3. **Symlinks** → tus configs apuntan al repo
4. **Backup** → captura el estado actual antes de reinstalar

## Estructura

```
dotfiles/
├── linux/
│   ├── config/          # ~/.config/ (apps: hypr, waybar, kitty, rofi, nvim, etc.)
│   ├── home/            # ~/.bashrc, ~/.gitconfig
│   ├── bin/             # ~/.local/bin/ (scripts propios)
│   ├── packages/        # Manifiestos de paquetes
│   │   ├── repos.sh           # Agrega COPR, RPM Fusion, Brave, Chrome, Flathub
│   │   ├── dnf-packages.txt   # Paquetes RPM (uno por línea)
│   │   ├── flatpak-packages.txt  # Apps Flatpak (application ID)
│   │   └── wallpaper/         # Wallpapers default
│   ├── xkb/             # Layout de teclado personalizado
│   └── system/          # Archivos de sistema (/etc/) — futuro
├── scripts/
│   ├── install.sh             # Enlaza configs (symlinks)
│   ├── setup-packages.sh      # Instala repos + paquetes desde cero
│   ├── backup-packages.sh     # Captura paquetes actuales a manifiestos
│   └── publish.sh             # Commit + push
├── AGENTS.md            # Instrucciones para asistentes de IA
└── README.md            # Este archivo
```

## Fresh install (Fedora Workstation 44)

Después de instalar Fedora, abre una terminal y ejecuta:

```bash
# 1. Conectar a internet (si no lo hiciste durante la instalación)
sudo nmcli dev wifi connect <SSID> password <password>

# 2. Instalar git
sudo dnf install -y git

# 3. Clonar el repositorio
git clone <url-del-repo> ~/dotfiles

# 4. Instalar TODO: repos + paquetes + configs + wallpapers
cd ~/dotfiles
bash scripts/install.sh --packages --force

# 5. (Opcional) Configuraciones del sistema
sudo bash linux/bin/setup-gdm-dark.sh           # Fondo negro en pantalla de login
sudo ln -s ~/dotfiles/linux/xkb/dvk_prog /usr/share/X11/xkb/symbols/dvk_prog  # Layout de teclado

# 6. Recargar shell
exec bash
```

> **Nota:** `install.sh --packages` ejecuta `setup-packages.sh` automáticamente. Si solo quieres los paquetes sin enlazar configs, corre `setup-packages.sh` directamente.

### Lo que instala `--packages`

| Origen | Qué |
|--------|-----|
| `repos.sh` | RPM Fusion, COPR Hyprland, Brave, Chrome, Flathub |
| `dnf-packages.txt` | Hyprland ecosystem, neovim, kitty, waybar, rofi, navegadores, dev tools, multimedia, juegos |
| `flatpak-packages.txt` | WhatsApp (ZapZap), Teams (Portal for Teams), Firefox, VLC, OBS, Steam, Lutris |
| `wallpaper/` | Wallpapers copiados a `~/Imágenes/` |

## Uso diario

```bash
# Editar configs (siempre dentro de ~/dotfiles/)
vim ~/dotfiles/linux/config/hypr/hyprland.conf

# Refrescar symlinks
~/dotfiles/scripts/install.sh --force

# Publicar cambios (con confirmación antes de pushear)
~/dotfiles/scripts/publish.sh
```

## Backup (antes de reinstalar Fedora)

```bash
# Captura paquetes DNF, Flatpak y Pip actuales a linux/packages/
bash ~/dotfiles/scripts/backup-packages.sh

# Revisa los archivos, elimina lo que no necesites, edita lo que falte
vim ~/dotfiles/linux/packages/dnf-packages.txt
vim ~/dotfiles/linux/packages/flatpak-packages.txt

# Haz commit y push
~/dotfiles/scripts/publish.sh
```

## Agregar una nueva configuración

1. Pon tus archivos en `linux/config/<app>/` o `linux/home/<archivo>`
2. Añade una entrada en `scripts/install.sh` (arrays `CONFIG_DIRS`, `CONFIG_FILES` o `HOME_FILES`)
3. Si requiere paquetes, agrégalos a `linux/packages/dnf-packages.txt` o `flatpak-packages.txt`
4. Ejecuta `install.sh --force`

## Lo que NO gestiona este repo

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario, ni ejecutables instalados por gestores de paquetes (Python, npm, dnf, etc.).

## Ver también

- `AGENTS.md` — instrucciones detalladas para asistentes de IA y colaboradores