# dotfiles

Configuraciones personales y automatización de instalación para NixOS.
Este repositorio es la **única fuente de verdad** — todo se edita aquí y se aplica con un rebuild.

## Filosofía

Un solo flake y tu máquina queda exactamente como la tenías:

1. **`flake.nix`** → sistema completo declarativo (paquetes, servicios, drivers)
2. **`nixos/`** → configuración base, home-manager y hosts (laptop/desktop)
3. **Symlinks** → tus configs (`linux/config/`) apuntan al repo via home-manager
4. **`setup-nixos.sh`** → un comando para fresh install

## Estructura

```
dotfiles/
├── flake.nix                 # inputs (nixpkgs, home-manager) + hosts
├── nixos/
│   ├── configuration.nix     # base común (servicios, usuario, GDM, Hyprland)
│   ├── home.nix              # home-manager: symlinks a linux/config, linux/bin, units
│   ├── modules/              # packages.nix, keyboard.nix, sudoers.nix
│   └── hosts/                # laptop.nix, desktop.nix + hardware-config
├── linux/
│   ├── config/               # ~/.config/ (hypr, waybar, kitty, quickshell, nvim, etc.)
│   ├── home/                 # ~/.bashrc, ~/.gitconfig
│   ├── bin/                  # ~/.local/bin/ (scripts propios)
│   ├── xkb/                  # layout de teclado custom (dvk_prog)
│   ├── patches/              # patches (lan-mouse AltGr, waybar Lua dispatch)
│   └── system/               # configs de sistema (keyd, NetworkManager)
├── scripts/
│   ├── setup-nixos.sh        # fresh install en un comando
│   ├── detect-machine.sh     # detecta laptop/desktop por hardware
│   ├── publish.sh            # commit + push
│   └── sync-developing.sh    # sync manual legacy (Syncthing es automatico)
├── AGENTS.md
└── README.md
```

## Fresh install (NixOS)

```bash
# Tras instalar NixOS y clonar el repo:
bash ~/dotfiles/scripts/setup-nixos.sh

# O directamente desde cualquier sitio:
curl -fsSL https://raw.githubusercontent.com/estebaninfante/dotfiles/main/scripts/setup-nixos.sh | bash

# Override explícito (solo si la detección por hardware fallara):
MACHINE=desktop bash ~/dotfiles/scripts/setup-nixos.sh
```

Ver `nixos/README.md` para la guía de instalación completa.

## Uso diario

```bash
# Editar configs (siempre dentro de ~/dotfiles/)
vim ~/dotfiles/linux/config/hypr/hyprland.lua

# Aplicar cambios de sistema/paquetes; detecta host por hardware
nrb switch

# Publicar cambios (commit + push, con confirmación)
~/dotfiles/scripts/publish.sh
```

## Multi-máquina (laptop + desktop)

El flake define dos hosts (`#laptop` y `#desktop`). La detección de máquina
(`~/.config/machine-type`) la hace `scripts/detect-machine.sh` por **hardware**
(DMI, batería, backlight), nunca se asume `laptop` por defecto.

Los configs machine-specific (`hyprland.lua`, `hyprpaper-*.conf`, scripts de
laptop) usan condicionales por machine type. Ver `AGENTS.md` para el detalle.

`~/developing` se sincroniza en tiempo real entre laptop y desktop mediante
Syncthing, en ambas direcciones. El proyecto Next de la laptop queda accesible
por `http://192.168.1.240:3100/`.

Fuera de casa, Syncthing usa Tailscale. Ambos equipos deben estar encendidos;
si uno está apagado, cambios quedan pendientes y se aplican al volver a conectar.
Dependencias y builds generados (`node_modules`, `.next`, `dist`, caches y logs)
quedan locales mediante `.stignore`; código y lockfiles sí se sincronizan.

## Agregar una nueva configuración

1. Pon tus archivos en `linux/config/<app>/` o `linux/home/<archivo>`
2. Añade la entrada en `nixos/home.nix` (listas `configDirs`, `configFiles`, `homeFiles` o `allScripts`)
3. Si requiere paquetes, agrégalos a `nixos/modules/packages.nix`
4. `nrb switch`

## Lo que NO gestiona este repo

Caches, navegadores, IDEs, credenciales, tokens, claves privadas, datos de usuario,
ni ejecutables instalados por gestores de paquetes (Python, npm, etc.).

## Ver también

- `AGENTS.md` — instrucciones para asistentes de IA
- `nixos/README.md` — guía de instalación completa
