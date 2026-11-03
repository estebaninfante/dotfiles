#!/usr/bin/env bash
# setup-tpm2-unlock.sh — Auto-unlock del disco LUKS con el chip TPM2 (estilo BitLocker)
#
# Hoy el boot pide la contraseña del disco antes de que el sistema exista
# (initramfs). Windows no la pide porque BitLocker la sella en el TPM de la
# máquina: el chip suelta la clave al kernel en cada boot de esa máquina física.
# Este script hace exactamente eso con systemd-cryptenroll:
#
#   1. Instala systemd-cryptsetup (necesario para el hook sd-encrypt)
#   2. Migra la pila de mkinitcpio drop-in de Omarchy a systemd-stack
#      (udev→systemd, keymap consolefont→sd-vconsole, encrypt→sd-encrypt,
#      conservando 1:1 la lógica NVIDIA y el bundling de vconsole.conf)
#   3. Crea /etc/crypttab.initramfs con tpm2-device=auto
#   4. Sellá (enroll) la clave del LUKS en el TPM (PCR 7, default systemd)
#   5. Regenera el initramfs
#
# La contraseña del disco NO se borra: queda como slot de recuperación
# (booteo por USB, repairs, etc.). TPM falla en un boot raro → cae al prompt
# de password normalmente, no te traba.
#
# Tradeoff (mismo que BitLocker TPM-only): laptop robada APAGADA se descifra
# sin password, porque el TPM viaja adentro. Endurecimiento real después:
# activar Secure Boot y re-enrollar.
#
# El autologin de SDDM queda como está (desktop directo en boot). Si en el
# futuro querés "login con huella" estilo Windows Hello, es un cambio aparte.
#
# Uso:      bash ~/dotfiles/linux/system/firmware/setup-tpm2-unlock.sh
# Rollback: bash ~/dotfiles/linux/system/firmware/setup-tpm2-unlock.sh --rollback

set -euo pipefail

info()  { printf '\033[1;34m  ==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ok \033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m warn\033[0m %s\n' "$*"; }

DROPIN="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
CRYPTTAB_INIT="/etc/crypttab.initramfs"
DEV_MAPPER_NAME=""   # set below

# ── 0. Detectar disco + TPM ───────────────────────────────────────────────────
LUKS_UUID=$(cat /proc/cmdline | /usr/bin/grep -oE "cryptdevice=UUID=[0-9a-f-]+" | head -1 | /usr/bin/grep -oE "[0-9a-f-]{36}")
MAPNAME=$(cat /proc/cmdline | /usr/bin/grep -oE "cryptdevice=UUID=[0-9a-f-]+:[A-Za-z0-9_-]+" | head -1 | /usr/bin/grep -oE ":[A-Za-z0-9_-]+$" | tr -d ':')
if [[ -z "$LUKS_UUID" ]]; then
    warn "No detecté el UUID del LUKS en /proc/cmdline. Aborto sin tocar nada."
    exit 1
fi
DEV="/dev/mapper/$MAPNAME"
ok "LUKS: UUID=$LUKS_UUID, mapper=$DEV"

if [[ ! -e /dev/tpm0 && ! -e /dev/tpmrm0 ]]; then
    warn "No hay dispositivo TPM2 (/dev/tpm0). Aborto."
    exit 1
fi
ok "TPM2 presente"

# Sanity: el mapper debe estar activo (estamos corriendo por él)
if [[ ! -e "$DEV" ]]; then
    warn "$DEV no está activo — imposible enrollar. Aborto."
    exit 1
fi

# ── 1. Dependencias ───────────────────────────────────────────────────────────
if pacman -Q systemd-cryptsetup &>/dev/null; then
    ok "systemd-cryptsetup instalado"
else
    info "Instalando systemd-cryptsetup (necesario para sd-encrypt)..."
    sudo pacman -S --needed --noconfirm systemd-cryptsetup
fi

# ── Modo rollback ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--rollback" ]]; then
    warn "Ejecutando rollback..."
    bak=$(sudo bash -c "ls -1t $DROPIN.bak.* 2>/dev/null | head -1")
    if [[ -n "$bak" ]]; then
        sudo cp "$bak" "$DROPIN"
        ok "Drop-in restaurado desde $bak"
    else
        warn "No hay backup del drop-in — revisalo a mano"
    fi
    if sudo cryptsetup luksDump "$DEV" 2>/dev/null | /usr/bin/grep -q "tpm2"; then
        info "Borrando slot TPM2 del LUKS..."
        sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEV"
    fi
    sudo rm -f "$CRYPTTAB_INIT"
    sudo mkinitcpio -P
    ok "Rollback completo: volvés a pedir el password del disco como siempre."
    exit 0
fi

# ── 2. Migrar drop-in de hooks (requisito: sd-encrypt) ────────────────────────
if /usr/bin/grep -q "sd-encrypt" "$DROPIN" 2>/dev/null; then
    ok "El drop-in ya usa sd-encrypt (stack systemd)"
else
    info "Migrando $DROPIN: stack udev/encrypt → systemd/sd-encrypt..."
    info "Se pide tu password de sudo."
    sudo cp "$DROPIN" "$DROPIN.bak.$(date +%s)"
    # Mismo drop-in oficial de Omarchy con SOLO cambios en la línea HOOKS.
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

# ── 3. crypttab.initramfs con TPM ─────────────────────────────────────────────
if sudo test -s "$CRYPTTAB_INIT" 2>/dev/null && sudo /usr/bin/grep -q "UUID=$LUKS_UUID" "$CRYPTTAB_INIT" 2>/dev/null; then
    info "Actualizando $CRYPTTAB_INIT (agrega tpm2-device=auto y discard)..."
    sudo cp "$CRYPTTAB_INIT" "$CRYPTTAB_INIT.bak.$(date +%s)"
else
    info "Creando $CRYPTTAB_INIT..."
fi
sudo tee "$CRYPTTAB_INIT" >/dev/null <<EOF
# Desbloqueo del disco en el initramfs. El TPM libera la clave si el boot es
# íntegro; si falla, cryptsetup cae al prompt de password (slot de recuperación).
$MAPNAME UUID=$LUKS_UUID none luks,tpm2-device=auto,discard
EOF

# ── 4. Enroll de la clave en el TPM ───────────────────────────────────────────
if sudo cryptsetup luksDump "$DEV" 2>/dev/null | /usr/bin/grep -q "systemd-tpm2"; then
    info "Ya hay token TPM2 — re-sellando por si cambió algo..."
    sudo systemd-cryptenroll --wipe-slot=tpm2 "$DEV"
fi
info "Sellando clave del LUKS en el TPM (PCR 7)..."
sudo systemd-cryptenroll --tpm2-device=auto "$DEV"
ok "Clave sellada en el TPM"
# Sanity: el token quedó en el header del LUKS
sudo cryptsetup luksDump "$DEV" | /usr/bin/grep -A6 "Tokens" || true

# ── 5. Regenerar initramfs ────────────────────────────────────────────────────
info "Regenerando initramfs..."
if sudo mkinitcpio -P; then
    ok "Initramfs regenerado con la pila systemd + TPM"
else
    warn "mkinitcpio FALLÓ. Las imágenes viejas intactas. Rollback:"
    warn "  bash ~/dotfiles/linux/system/firmware/setup-tpm2-unlock.sh --rollback"
    exit 1
fi

echo
ok "LISTO. Reiniciá: el disco se desbloquea solo y llegás al escritorio."
warn "Contraseña del disco: INTACTA — queda como slot de recuperación."
warn "Si un boot raro el TPM no libera la clave → pedirá el password de siempre."
warn "ROLLBACK completo: bash ~/dotfiles/linux/system/firmware/setup-tpm2-unlock.sh --rollback"
warn "(o por ISO: restaurar $DROPIN.bak.*, rm $CRYPTTAB_INIT,"
warn " systemd-cryptenroll --wipe-slot=tpm2 $DEV, mkinitcpio -P)"
