#!/usr/bin/env bash
# setup-plymouth-luks.sh — Prompt de desbloqueo LUKS gráfico (estilo Fedora/NixOS)
#
# Omarchy usa el hook clásico `encrypt` + stack udev: el password del disco se
# pide como texto crudo en la tty (aunque plymouth ya esté corriendo). Fedora
# muestra el prompt como diálogo gráfico sobre el splash: usa el stack systemd
# (`systemd` + `sd-encrypt` + `sd-vconsole`), que habla con plymouth.
# Este script migra /etc/mkinitcpio.conf.d/omarchy_hooks.conf:
#
#   udev → systemd            (stack de early-userspace)
#   encrypt → sd-encrypt      (el prompt del LUKS pasa a ser gráfico)
#   keymap consolefont → sd-vconsole  (equivalente systemd; lee /etc/vconsole.conf
#                                      que el bloque bundling del drop-in ya
#                                      incluye para tu layout dvorak)
#
# La contraseña del disco NO cambia. Rollback: este archivo con --rollback,
# o los pasos manuales de arriba en cualquier sesión/ISO que bootee.
#
# Uso:    bash ~/dotfiles/linux/system/firmware/setup-plymouth-luks.sh
#         bash ~/dotfiles/linux/system/firmware/setup-plymouth-luks.sh --rollback

set -euo pipefail

info()  { printf '\033[1;34m  ==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ok \033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m warn\033[0m %s\n' "$*"; }

DROPIN="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
CRYPTTAB_INIT="/etc/crypttab.initramfs"

rollback() {
    warn "Ejecutando rollback..."
    bak=$(sudo bash -c "ls -1t $DROPIN.bak.* 2>/dev/null | head -1")
    if [[ -n "$bak" ]]; then
        sudo cp "$bak" "$DROPIN"
        ok "Drop-in restaurado desde $bak"
    else
        warn "No hay backup del drop-in"
    fi
    sudo rm -f "$CRYPTTAB_INIT"
    sudo mkinitcpio -P
    ok "Rollback completo: tu boot vuelve a ser como era (consola cruda + password)."
    exit 0
}

# ── 0. Detectar el UUID del disco cifrado ────────────────────────────────────
LUKS_UUID=$(cat /proc/cmdline | /usr/bin/grep -oE "cryptdevice=UUID=[0-9a-f-]+" | head -1 | /usr/bin/grep -oE "[0-9a-f-]{36}")
MAPNAME=$(cat /proc/cmdline | /usr/bin/grep -oE "cryptdevice=UUID=[0-9a-f-]+:[A-Za-z0-9_-]+" | head -1 | /usr/bin/grep -oE ":[A-Za-z0-9_-]+$" | tr -d ':')
if [[ -n "$LUKS_UUID" ]]; then
    ok "LUKS detectado: UUID=$LUKS_UUID, mapper=/$MAPNAME"
else
    warn "No detecté el UUID del LUKS en /proc/cmdline. Aborto sin tocar nada."
    exit 1
fi

# ── Modo rollback ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--rollback" ]]; then
    rollback
fi

# ── 1. Plymouth instalado ─────────────────────────────────────────────────────
if pacman -Q plymouth &>/dev/null; then
    ok "plymouth ya está instalado"
else
    info "Instalando plymouth..."
    sudo pacman -S --needed --noconfirm plymouth
fi

# ── 2. Migrar drop-in de hooks ────────────────────────────────────────────────
if /usr/bin/grep -q "sd-encrypt" "$DROPIN" 2>/dev/null; then
    ok "El drop-in ya usa sd-encrypt"
else
    info "Migrando $DROPIN: stack udev/encrypt → systemd/sd-encrypt..."
    info "Se pide tu password de sudo."

    # Backup SIEMPRE antes de tocar (timestamp por si se corre dos veces)
    sudo cp "$DROPIN" "$DROPIN.bak.$(date +%s)"

    # Mismo drop-in oficial de Omarchy con SOLO tres cambios en la línea HOOKS:
    # udev→systemd, keymap consolefont→sd-vconsole, encrypt→sd-encrypt.
    # El bloque condicional NVIDIA y el bundling de vconsole.conf quedan 1:1.
    sudo tee "$DROPIN.new" >/dev/null <<'EOF'
HOOKS=(base systemd plymouth sd-vconsole autodetect microcode modconf kms block sd-encrypt filesystems fsck btrfs-overlayfs)

# The proprietary NVIDIA driver does early KMS itself: nvidia.conf (written by
# install/hardware/nvidia.sh, sourced before this file) early-loads nvidia_drm
# with modeset=1. Keeping the kms hook on such a system makes autodetect pull
# in nouveau — and ~100 MB of its GSP firmware — for a driver that never runs.
# Drop kms only when nvidia_drm is early-loaded and NVIDIA owns every display
# controller. Hybrid systems keep kms: their iGPU still needs it for early
# KMS at the LUKS prompt. So does anything unexpected, like a PCI tree that
# cannot be read.
#
# This reads MODULES midway through mkinitcpio's drop-in sourcing, so a
# later-sorting drop-in that resets MODULES outright — surface_device_modules.conf
# does — would strip nvidia_drm after kms was already dropped. Every machine
# Omarchy writes such a file for carries an Intel iGPU, which keeps kms here
# through the scan below; keep it that way.
if [[ " ${MODULES[*]:-} " == *" nvidia_drm "* ]]; then
  _omarchy_nvidia_gpu=0
  _omarchy_other_gpu=0
  for _omarchy_pci in "${OMARCHY_PCI_DEVICES_PATH:-/sys/bus/pci/devices}"/*; do
    if [[ ! -r $_omarchy_pci/class || ! -r $_omarchy_pci/vendor ]]; then
      # An unreadable device could be another GPU. Inconclusive keeps kms.
      _omarchy_other_gpu=1
      continue
    fi
    [[ $(<"$_omarchy_pci/class") == "0x03"* ]] || continue
    if [[ $(<"$_omarchy_pci/vendor") == "0x10de" ]]; then
      _omarchy_nvidia_gpu=1
    else
      _omarchy_other_gpu=1
    fi
  done
  if ((_omarchy_nvidia_gpu && !_omarchy_other_gpu)); then
    _omarchy_hooks=()
    for _omarchy_hook in "${HOOKS[@]}"; do
      [[ $_omarchy_hook == "kms" ]] || _omarchy_hooks+=("$_omarchy_hook")
    done
    HOOKS=("${_omarchy_hooks[@]}")
  fi
  unset _omarchy_nvidia_gpu _omarchy_other_gpu _omarchy_pci _omarchy_hooks _omarchy_hook
fi

# Bundle vconsole.conf so Plymouth uses the configured keyboard layout at the
# LUKS prompt, but only when that layout types Latin letters. Passphrases are
# Latin characters, so bundling a Hebrew/Greek/Cyrillic/Arabic layout would
# make the correct passphrase untypeable and lock the user out.
if [[ -f /etc/vconsole.conf ]]; then
  case $(. /etc/vconsole.conf && echo "${XKBLAYOUT%%,*}") in
    af | am | ara | bd | bg | by | et | ge | gr | il | in | iq | ir | kg | kh | kz | la | lk | mk | mm | mn | mv | np | rs | ru | sy | th | tj | ua) ;;
    *) FILES+=(/etc/vconsole.conf) ;;
  esac
fi
EOF
    sudo mv "$DROPIN.new" "$DROPIN"
    ok "Drop-in migrado (backup: $DROPIN.bak.*)"
fi

# ── 3. crypttab.initramfs (sd-encrypt lo lee por UUID) ─────────────────────────
if sudo test -s "$CRYPTTAB_INIT" 2>/dev/null && sudo /usr/bin/grep -q "UUID=$LUKS_UUID" "$CRYPTTAB_INIT" 2>/dev/null; then
    ok "$CRYPTTAB_INIT ya existe con el UUID correcto"
else
    info "Creando $CRYPTTAB_INIT..."
    sudo cp "$CRYPTTAB_INIT" "$CRYPTTAB_INIT.bak.$(date +%s)" 2>/dev/null || true
    sudo tee "$CRYPTTAB_INIT" >/dev/null <<EOF
# Desbloqueo del disco en el initramfs (stack systemd/sd-encrypt, prompt via plymouth)
$MAPNAME UUID=$LUKS_UUID none luks,discard
EOF
fi

# ── 4. Regenerar initramfs ────────────────────────────────────────────────────
info "Regenerando initramfs..."
if sudo mkinitcpio -P; then
    ok "Initramfs regenerado con la pila systemd"
else
    warn "mkinitcpio FALLÓ. Las imágenes viejas no se tocaron. Rollback:"
    warn "  bash ~/dotfiles/linux/system/firmware/setup-plymouth-luks.sh --rollback"
    exit 1
fi

ok "Hecho. Reiniciá y el prompt del disco debe ser gráfico, estilo Fedora."
warn "Contraseña del disco: LA MISMA de siempre. Solo cambió cómo se muestra."
warn "Si el boot llega a quedar mal (no bootea):"
warn "  1. Bootear una ISO de Arch/Omarchy por USB"
warn "  2. cryptsetup open /dev/nvme0n1p8 root; mount /dev/mapper/root /mnt"
warn "  3. cp /mnt/etc/mkinitcpio.conf.d/omarchy_hooks.conf.bak.* /mnt/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
warn "  4. rm /mnt/etc/crypttab.initramfs"
warn "  5. arch-chroot /mnt mkinitcpio -P && reboot"
warn "Nota: el drop-in viene del paquete omarchy — un `omarchy update` puede"
warn "reescribirlo con el stack clásico (encrypt). Si la consola cruda vuelve"
warn "después de un update, re-corré este script."
