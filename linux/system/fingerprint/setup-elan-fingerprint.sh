#!/usr/bin/env bash
# setup-elan-fingerprint.sh — Huella digital en el sensor ELAN 04f3:0c4b
#
# El driver open-source de libfprint ("claima" soportar 04f3:0c4b pero habla
# un protocolo viejo: enroll muere con enroll-disconnected / "protocol error
# with the device"). La solución probada es el driver propietario TOD de
# Lenovo: https://github.com/Abishek-Pechiappan/libfprint-elan-04f3-0c4b-tod
#
# Este script hace TODO (idempotente; pedir contraseña de sudo unas veces):
#   1. Verifica que el sensor 04f3:0c4b esté presente
#   2. Remueve libfprint / libfprint-git (entran en conflicto con TOD)
#   3. Instala libfprint-tod + driver ELAN (clona el repo del fix)
#   4. Configura PAM estilo Omarchy: sudo, polkit y pantalla de bloqueo
#   5. Ofrece inscribir la huella (índice derecho)
#
# NOTAS:
#   - NO re-correr `omarchy setup security fingerprint` después: reinstala
#     libfprint-git (--ask 4) y pisa el driver TOD.
#   - El blob es binario cerrado de Lenovo (el mismo de sus ISOs Ubuntu).
#   - Tras actualizar fprintd/libfprint en pacman, si la huella deja de
#     funcionar: volver a correr este script.
#
# Uso: bash ~/dotfiles/linux/system/fingerprint/setup-elan-fingerprint.sh

set -euo pipefail

info()  { printf '\033[1;34m  ==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ok \033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m warn\033[0m %s\n' "$*"; }

TOD_REPO_DIR="$HOME/elan-fingerprint-fix"
TOD_REPO_URL="https://github.com/Abishek-Pechiappan/libfprint-elan-04f3-0c4b-tod"
SENSOR_USB_ID="04f3:0c4b"

# ── 1. Sensor presente ────────────────────────────────────────────────────────
if lsusb | grep -qi "$SENSOR_USB_ID"; then
    ok "Sensor $SENSOR_USB_ID detectado"
else
    warn "No hay sensor $SENSOR_USB_ID — este script es solo para ese modelo."
    warn "(Si tenés otro ELAN, mirá docs del repo del fix u otros drivers TOD)"
    exit 1
fi

# ── 2/3. Driver TOD ──────────────────────────────────────────────────────────
if pacman -Q libfprint-tod-git &>/dev/null; then
    ok "libfprint-tod-git ya está instalado"
else
    for pkg in libfprint-git libfprint; do
        if pacman -Q "$pkg" &>/dev/null; then
            info "Removiendo $pkg (conflicto con TOD; fprintd queda sin driver hasta el paso 3)..."
            sudo pacman -Rdd --noconfirm "$pkg"
        fi
    done

    if [[ ! -d "$TOD_REPO_DIR" ]]; then
        info "Clonando repo del fix..."
        git clone --depth 1 "$TOD_REPO_URL" "$TOD_REPO_DIR"
    else
        ok "Repo del fix ya clonado en $TOD_REPO_DIR"
    fi

    info "Instalando libfprint-tod + driver ELAN (build de unos minutos)..."
    bash "$TOD_REPO_DIR/scripts/install.sh"
fi

# ── 4. PAM estilo Omarchy ────────────────────────────────────────────────────
# Gate para tapa cerrada: el reader es inaccesible con la laptop cerrada, así
# que la línea salta la huella y cae directo al prompt de password.
# (Lógica replicada de omarchy-setup-security-fingerprint — no usar ese porque
# reinstala libfprint-git y pisa el driver TOD.)
configure_pam() {
    local gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed"

    if ! grep -q pam_fprintd.so /etc/pam.d/sudo; then
        info "Configurando sudo con huella..."
        sudo sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/sudo
    fi
    if ! grep -q 'omarchy-hw-laptop-closed' /etc/pam.d/sudo; then
        sudo sed -i "/pam_fprintd\.so/i $gate" /etc/pam.d/sudo
    fi

    if [[ -f /etc/pam.d/polkit-1 ]] && grep -q '^auth' /etc/pam.d/polkit-1; then
        if ! grep -q pam_fprintd.so /etc/pam.d/polkit-1; then
            info "Configurando polkit con huella..."
            sudo sed -i '1i auth      sufficient pam_fprintd.so' /etc/pam.d/polkit-1
        fi
        if ! grep -q 'omarchy-hw-laptop-closed' /etc/pam.d/polkit-1; then
            sudo sed -i "/pam_fprintd\.so/i $gate" /etc/pam.d/polkit-1
        fi
    else
        if ! grep -q pam_fprintd.so /etc/pam.d/polkit-1 2>/dev/null; then
            info "Creando /etc/pam.d/polkit-1 con huella..."
            sudo tee /etc/pam.d/polkit-1 >/dev/null <<EOF
$gate
auth      sufficient pam_fprintd.so
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
        fi
    fi

    if [[ ! -f /etc/pam.d/omarchy-lock-fingerprint ]]; then
        info "Configurando huella para pantalla de bloqueo..."
        sudo tee /etc/pam.d/omarchy-lock-fingerprint >/dev/null <<'EOF'
#%PAM-1.0
auth       required                    pam_fprintd.so
account    include                     system-local-login
EOF
    fi
    ok "PAM configurado (sudo + polkit + lock screen)"
}
configure_pam

# ── 5. Inscripción ───────────────────────────────────────────────────────────
FINGERS=$(fprintd-list "$USER" 2>/dev/null | grep -E "^ +-" | sed 's/.*: //' || true)
if [[ -n "$FINGERS" ]]; then
    ok "Ya hay huellas inscritas: $(echo "$FINGERS" | tr '\n' '; ')"
else
    echo
    read -rp "¿Inscribir huella ahora (índice derecho)? [y/N] " ans
    case "$ans" in
        [yY]*)
            info "Apoyá el dedo en el sensor varias veces hasta completar..."
            sudo fprintd-enroll "$USER" -f right-index-finger
            info "Verificando (apoyá el dedo una vez más)..."
            fprintd-verify
            ok "Huella inscrita y verificada"
            ;;
        *) warn "Salteado. Podés hacerla después con: sudo fprintd-enroll \"\$USER\" -f right-index-finger" ;;
    esac
fi

# ── Estado final ──────────────────────────────────────────────────────────────
echo
ok "Setup de huella completo. Test:"
echo "    sudo -k && sudo true    # pedí huella al pedir password"
echo "    fprintd-verify          # apoyá el dedo"
echo "    omarchy system lock     # desbloqueá con la huella (Super+Ctrl+L)"
echo
warn "No re-corras 'omarchy setup security fingerprint': reinstala libfprint-git y pisa el driver TOD."
