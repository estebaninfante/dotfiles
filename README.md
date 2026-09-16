# dotfiles

Configuraciones personales y automatización para **Omarchy (Arch Linux)**.
Este repositorio es la **única fuente de verdad** — todo se edita aquí y se
aplica en la máquina mediante symlinks.

> Migrado desde NixOS. El setup declarativo anterior quedó en el historial de
> git; ya no se usa `nixos-rebuild`, `home-manager` ni flakes.

## Filosofía

1. **`linux/config/`** → `~/.config/` (symlink directo al repo)
2. **`linux/bin/`** → `~/.local/bin/` (symlink directo al repo)
3. **`linux/home/`** → `~/.bashrc`, `~/.gitconfig` (symlink)
4. **`scripts/link-dotfiles.sh`** → aplica todo el inventario de symlinks
5. **`scripts/setup-omarchy.sh`** → fresh install sobre Omarchy (un comando)

Todo se edita dentro de `~/dotfiles/`; los cambios en configs symlinkeadas se
aplican al instante.

## Estructura

```
dotfiles/
├── linux/
│   ├── config/          # ~/.config/ (hypr, waybar, kitty, quickshell, nvim, ...)
│   ├── home/            # ~/.bashrc, ~/.gitconfig
│   ├── bin/             # ~/.local/bin/ (scripts propios)
│   ├── voice/           # TTS daemon + Chatterbox server
│   ├── xkb/             # layout de teclado custom (dvk_prog)
│   ├── patches/         # patches (lan-mouse AltGr, waybar Lua dispatch)
│   └── system/          # configs de sistema (keyd, NetworkManager, libinput)
├── scripts/
│   ├── setup-omarchy.sh # fresh install en un comando
│   ├── link-dotfiles.sh # aplica symlinks (idempotente)
│   ├── detect-machine.sh# detecta laptop/desktop por hardware
│   ├── setup-secrets.sh # configura/verifica claves y secrets
│   ├── setup-tts.sh     # TTS
│   └── publish.sh       # commit + push con confirmación
├── .opencode/           # agentes + skills del proyecto
├── AGENTS.md
└── README.md
```

## Fresh install (Omarchy)

```bash
# Tras instalar Omarchy y clonar el repo:
bash ~/dotfiles/scripts/setup-omarchy.sh

# Override explícito de máquina (solo si la detección por hardware fallara):
MACHINE=desktop bash ~/dotfiles/scripts/setup-omarchy.sh
```

El script instala paquetes (pacman + yay/AUR), aplica los symlinks, configura
keyd, servicios systemd de usuario y verifica el resultado.

## Uso diario

```bash
# Editar configs (siempre dentro de ~/dotfiles/)
vim ~/dotfiles/linux/config/hypr/hyprland.lua

# Reaplicar symlinks (idempotente) tras añadir/renombrar configs
bash ~/dotfiles/scripts/link-dotfiles.sh

# Publicar cambios (commit + push, con confirmación)
~/dotfiles/scripts/publish.sh
```

## Agregar una nueva configuración

1. Pon tus archivos en `linux/config/<app>/` o `linux/home/<archivo>`
2. Añade la entrada al inventario de `scripts/link-dotfiles.sh`
   (`CONFIG_DIRS`, `CONFIG_FILES`, `HOME_FILES` o el loop de `linux/bin`)
3. Si requiere paquetes, agrégalos a `scripts/setup-omarchy.sh`
4. `bash ~/dotfiles/scripts/link-dotfiles.sh`

## Multi-máquina (laptop + desktop)

Las configs machine-specific (`hyprland.lua`, `hyprpaper-*.conf`) usan
condicionales por machine type (`~/.config/machine-type`), detectado por
**hardware** (DMI, batería, backlight) con `scripts/detect-machine.sh`.

`~/developing` se sincroniza en tiempo real entre laptop y desktop mediante
Syncthing (Tailscale fuera de casa). Ver `AGENTS.md` para el detalle.

## Secrets

Las claves/tokens viven en `~/.config/dotfiles-secrets.sh` (fuera del repo,
`sourced` por `~/.bashrc`). `scripts/setup-secrets.sh` los verifica e informa.

## Lo que NO gestiona este repo

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de
usuario, ni ejecutables instalados por gestores de paquetes.

## Ver también

- `AGENTS.md` — instrucciones para asistentes de IA
