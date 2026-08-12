# Migración a NixOS — Guía

Este kit replica tu entorno Fedora en NixOS con la **misma filosofía** que ya
tienes: el repo `~/dotfiles` es la única fuente de verdad. Los configs no se
reescriben en Nix — home-manager crea **symlinks directos al repo** (igual que
`scripts/install.sh`), así que editar en el repo sigue aplicando al instante.

## ¿Qué se conserva 1:1?

| Tu entorno Fedora | Equivalente NixOS |
|---|---|
| `scripts/install.sh` (symlinks a configs) | `home-manager` con `mkOutOfStoreSymlink` (`nixos/home.nix`) |
| `dnf-packages.txt` | `nixos/modules/packages.nix` (mapeo a nixpkgs) |
| `flatpak-packages.txt` | nixpkgs nativo (zapzap, teams, spotify, obsidian...) + `services.flatpak` para lo que no está |
| `linux/xkb/dvk_prog` | `services.xserver.xkb.extraLayouts.dvk_prog` |
| `linux/system/keyd/default.conf` | `environment.etc."keyd/default.conf"` + servicio |
| `linux/system/tuned/ppd.conf` | `services.power-profiles-daemon` (misma API `UPower.PowerProfiles` que usa `power-mode.sh`) |
| `linux/system/sudoers/dotfiles` | `nixos/modules/sudoers.nix` (NOPASSWD para gpu-mode.sh) |
| `gpu-mode.sh` (runtime PM NVIDIA) | funciona igual; `hardware.nvidia.prime.offload` + `powerManagement.enable = false` |
| `dotfiles-sync.service/timer` | `systemd.user` en home.nix (git pull del repo) |
| `trackpad-dwt.service` (laptop) | `systemd.user.services.trackpad-dwt` (solo laptop) |
| `~/.config/machine-type` | `home.file.".config/machine-type"` (desde flake) |
| GDM oscuro (`setup-gdm-dark.sh`) | `services.displayManager.gdm.settings` |
| Scripts de `linux/bin/` | symlinks a `~/.local/bin/` (solo laptop los de laptop) |
| `.bashrc`, `.gitconfig` | symlinks directos del repo |

## Estructura

```
flake.nix                      # inputs (nixpkgs + home-manager) y hosts
nixos/
├── configuration.nix          # base comun (servicios, fuentes, usuario, GDM, Hyprland)
├── home.nix                   # home-manager: symlinks a linux/config, linux/bin, units
├── modules/
│   ├── packages.nix           # dnf-packages.txt → nixpkgs
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
# 0. Desde Fedora: respalda tus datos
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
configs apuntando al repo (igual que install.sh), y deja Hermes instalado.
Solo queda `hermes setup` una vez para configurar el provider/modelo.

Después del primer boot:

```bash
# Los bus IDs de NVIDIA ya estan resueltos para esta laptop (Lenovo 82Y5):
#   amdgpuBusId = "PCI:5:0:0"  (AMD Phoenix1, 05:00.0)
#   nvidiaBusId = "PCI:1:0:0"  (RTX 4060, 01:00.0)
# Si algo cambia de maquina, verificar con: lspci | grep -E 'VGA|3D'

# Aplicar cambios (igual que publish.sh pero para el sistema):
sudo nixos-rebuild switch --flake ~/dotfiles#laptop
```

## Flujo diario (igual que con publish.sh)

```bash
# Editas en el repo → los symlinks ya apuntan ahí → se aplica al instante
# Para cambios de sistema/paquetes:
sudo nixos-rebuild switch --flake ~/dotfiles#laptop
# Para subir cambios:
bash ~/dotfiles/scripts/publish.sh   # commit + push (igual que antes)
```

## Gaps y decisiones (importantes)

1. **`handy` (speech-to-text)**: YA está en nixpkgs (0.9.1). El RPM 0.9.5
   vive en `~/Descargas/` (no en el repo git — GitHub limita >100MB) y se
   instala en Fedora via `scripts/install-rpms.sh`. En NixOS usa el de
   nixpkgs (0.9.1, funciona sin fricción).
2. **NVIDIA**: se usa `prime.offload` (iGPU AMD maneja display, dGPU bajo
   demanda) que es exactamente tu setup actual. `gpu-mode.sh` sigue
   funcionando igual (mismos sysfs). Bus IDs ya resueltos para esta laptop
   (Lenovo 82Y5): amdgpu `PCI:5:0:0`, nvidia `PCI:1:0:0`.
3. **Flatpak**: quedan fuera de nixpkgs → `stremio`, `gearlever`,
   `protonplus`. `services.flatpak.enable` ya está activo para ellos.
4. **`urserver`**: no está en nixpkgs; el autostart de hyprland.lua lo
   invoca. Puede fallar silenciosamente (es solo optimización de recursos).
5. **`waybar`/`swaync`**: ya están en tu repo y se symlinkean igual.
6. **GTK/iconos/cursor**: el theme "AOSP Cursors" y wallpapers no se
   gestionan vía nix (igual que ahora: `linux/packages/wallpaper/`).
7. **Portales**: hyprland.lua lanza los portales con rutas `/usr/libexec/`
   (Fedora). En NixOS los portales los gestiona `xdg.portal`; el fallo del
   exec es silencioso y no rompe nada.
8. **opencode + rstudio**: en nixpkgs (`opencode`, `opencode-desktop`,
   `rstudio`) → se instalan con el sistema. Los RPMs (en `~/Descargas/`,
   para Fedora) no se usan en NixOS.
9. **Hermes**: no está en nixpkgs → lo instala `scripts/setup-nixos.sh`
   (paso 5, instalador oficial) en el primer boot.

## Diferencia conceptual (la única real)

En Fedora el sistema es mutable y el repo solo gestiona configs. En NixOS
**todo el sistema** es declarativo: paquetes, servicios, drivers, unidades
systemd. Tu repo sigue siendo la fuente de verdad de las configs, pero la
"instalación" ya no es un script que enlaza — es `nixos-rebuild switch`.

Lo demás (editar configs, los scripts, el flujo git) es idéntico.
