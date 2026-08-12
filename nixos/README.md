# NixOS — Guía de instalación

El repo `~/dotfiles` es la única fuente de verdad. Los configs no se reescriben
en Nix — home-manager crea **symlinks directos al repo** (`mkOutOfStoreSymlink`),
así que editar en el repo aplica al instante sin rebuild.

## Estructura

```
flake.nix                      # inputs (nixpkgs + home-manager) y hosts
nixos/
├── configuration.nix          # base comun (servicios, fuentes, usuario, GDM, Hyprland)
├── home.nix                   # home-manager: symlinks a linux/config, linux/bin, units
├── modules/
│   ├── packages.nix           # paquetes del sistema (nixpkgs)
│   ├── keyboard.nix           # layout dvk_prog en TTY, X11/GDM y Wayland
│   └── sudoers.nix            # NOPASSWD (gpu-mode.sh)
└── hosts/
    ├── laptop.nix             # NVIDIA hybrid, XKB dvk_prog, keyd
    ├── desktop.nix            # NVIDIA RTX 3070 (dGPU unica)
    ├── hardware-configuration.laptop.nix   # ⚠️ placeholder
    └── hardware-configuration.desktop.nix  # hardware REAL (generado)
```

> **hardware-configuration.desktop.nix** contiene ya el hardware real del
> desktop (Ryzen 9 5900X + RTX 3070, btrfs). **hardware-configuration.laptop.nix**
> es placeholder a propósito: `setup-nixos.sh` lo regenera con el hardware de
> la laptop real y valida que coincida con el root UUID de la máquina actual.

## Instalación (fresh install)

```bash
# 0. Respalda tus datos
# 1. Bootea el instalador de NixOS, particiona
# 2. Monta y genera el hardware-config:
mount /dev/nvme0n1p2 /mnt
nixos-generate-config --root /mnt
# 3. Clona el repo DENTRO del instalador y copia el hardware-config
#    (usa el nombre de archivo de TU maquina):
git clone <url> /tmp/dotfiles
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/dotfiles/nixos/hosts/hardware-configuration.laptop.nix   # o .desktop.nix
# 4. Instala:
cd /tmp/dotfiles
nixos-install --flake .#laptop   # o .#desktop
# 5. Contraseña del usuario:
nixos-enter --root /mnt
passwd eztvn
exit
# 6. Reinicia
reboot
```

### Primer boot — UN comando y todo listo

```bash
# El script hace todo: clona el repo si falta, detecta la maquina POR
# HARDWARE (DMI/bateria/backlight), genera/valida el hardware-config contra
# el root UUID actual, nixos-rebuild switch (paquetes + servicios + dotfiles),
# enlaza opencode, e instala Hermes.
bash ~/dotfiles/scripts/setup-nixos.sh

# O directamente desde cualquier sitio (si el repo no esta clonado):
curl -fsSL https://raw.githubusercontent.com/estebaninfante/dotfiles/main/scripts/setup-nixos.sh | bash

# Override explicito (solo si la deteccion fallara):
MACHINE=desktop bash ~/dotfiles/scripts/setup-nixos.sh
```

Eso instala los ~300 paquetes (incluye nvim, opencode, handy, rstudio),
levanta Hyprland/GDM/keyd/tailscale/etc., crea los symlinks de todas tus
configs apuntando al repo, y deja Hermes instalado.
Solo queda `hermes setup` una vez para configurar el provider/modelo.

Después del primer boot:

```bash
# Los bus IDs de NVIDIA ya estan resueltos para esta laptop (Lenovo 82Y5):
#   amdgpuBusId = "PCI:5:0:0"  (AMD Phoenix1, 05:00.0)
#   nvidiaBusId = "PCI:1:0:0"  (RTX 4060, 01:00.0)
# Si algo cambia de maquina, verificar con: lspci | grep -E 'VGA|3D'

# Aplicar cambios:
sudo nixos-rebuild switch --flake ~/dotfiles#laptop
```

## Flujo diario

```bash
# Editas en el repo → los symlinks ya apuntan ahí → se aplica al instante
# Para cambios de sistema/paquetes:
sudo nixos-rebuild switch --flake ~/dotfiles#laptop
# Para subir cambios:
bash ~/dotfiles/scripts/publish.sh   # commit + push
```

## Gaps y decisiones (importantes)

1. **`handy` (speech-to-text)**: nixpkgs va atrasado (0.9.1). Si necesitas una
   versión más reciente, añade el flake upstream (`github:cjpais/Handy`).
2. **NVIDIA**: se usa `prime.offload` (iGPU AMD maneja display, dGPU bajo
   demanda). `gpu-mode.sh` controla el runtime PM (mismos sysfs).
3. **Flatpak**: quedan fuera de nixpkgs → `stremio`, `gearlever`,
   `protonplus`. `services.flatpak.enable` ya está activo para ellos.
4. **`urserver`**: no está en nixpkgs; el autostart de hyprland.lua lo
   invoca. Puede fallar silenciosamente (es solo optimización de recursos).
5. **GTK/iconos/cursor**: el theme "AOSP Cursors" y wallpapers no se
   gestionan vía nix (`linux/packages/wallpaper/`).
6. **Portales**: hyprland.lua lanza los portales con rutas `/usr/libexec/`.
   En NixOS los portales los gestiona `xdg.portal`; el fallo del exec es
   silencioso y no rompe nada.
7. **Hermes**: no está en nixpkgs → lo instala `scripts/setup-nixos.sh`
   (instalador oficial) en el primer boot.

## Diferencia conceptual

Todo el sistema es declarativo: paquetes, servicios, drivers, unidades systemd.
Tu repo sigue siendo la fuente de verdad de las configs, pero la "instalación"
no es un script que enlaza — es `nixos-rebuild switch`.
