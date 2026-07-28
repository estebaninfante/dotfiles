#!/bin/bash
# ==========================================================
# setup-fingerprint.sh
# Instala y configura soporte para huella dactilar en
# Fedora 44 con fprintd + PAM.
#
# USO:
#   ./setup-fingerprint.sh          # Modo interactivo (pregunta antes de cada paso)
#   ./setup-fingerprint.sh --apply  # Ejecutar cambios directamente
#   ./setup-fingerprint.sh --status # Solo mostrar estado actual
#
# IDEMPOTENTE: Puede ejecutarse múltiples veces sin romper nada.
# SEGURO: No modifica PAM si ya está configurado.
# ==========================================================

set -euo pipefail

# ─── Configuración ──────────────────────────────────────────
PAM_FILES=(
    "/etc/pam.d/sudo"
    "/etc/pam.d/su"
    "/etc/pam.d/polkit-1"
    "/etc/pam.d/gdm-password"
    "/etc/pam.d/swaylock"
)

PAM_FPRINT_LINE="auth       sufficient   pam_fprintd.so"

REQUIRED_PKGS=(
    fprintd
    fprintd-pam
)

# ─── Funciones ──────────────────────────────────────────────

info()    { echo -e "  [INFO] $*"; }
ok()      { echo -e "  [OK]   $*"; }
warn()    { echo -e "  [WARN] $*"; }
error()   { echo -e "  [ERROR] $*"; }

check_packages() {
    local missing=()
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        else
            ok "Paquete $pkg ya instalado"
        fi
    done
    echo "${missing[@]}"
}

check_device() {
    if lsusb 2>/dev/null | grep -qiE "fingerprint|biometric|synaptics|elan|goodix|validity"; then
        ok "Dispositivo de huella detectado por lsusb"
        return 0
    fi
    if ls /sys/bus/usb/devices/*/driver 2>/dev/null | grep -qi "vfs"; then
        ok "Controlador vfs(susb) detectado"
        return 0
    fi
    warn "No se detectó dispositivo de huella. ¿Está conectado/soportado?"
    return 1
}

check_fprintd_service() {
    if systemctl is-active --quiet fprintd 2>/dev/null; then
        ok "Servicio fprintd activo"
        return 0
    fi
    warn "Servicio fprintd no activo"
    return 1
}

check_pam_configured() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 1
    fi
    grep -q "^$PAM_FPRINT_LINE" "$file" 2>/dev/null
}

backup_pam() {
    local file="$1"
    local backup="$file.bak.fprint.$(date +%Y%m%d_%H%M%S)"
    cp -v "$file" "$backup"
    ok "Backup creado: $backup"
}

add_pam_line() {
    local file="$1"
    local auth_line="$PAM_FPRINT_LINE"

    info "Modificando $file ..."

    if [ ! -f "$file" ]; then
        warn "Archivo no encontrado: $file. Saltando."
        return
    fi

    if check_pam_configured "$file"; then
        ok "fprint ya configurado en $file. Saltando."
        return
    fi

    backup_pam "$file"

    # Insertar después de la primera línea "auth" o "auth       substack"
    sed -i '0,/^auth/ s/^auth.*/'"$auth_line"'\n&/' "$file"
    ok "Línea añadida a $file"
}

show_status() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "  Estado del sistema de huella"
    echo "═══════════════════════════════════════"
    echo ""
    echo "--- Paquetes ---"
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            ok "$pkg: $(rpm -q "$pkg")"
        else
            warn "$pkg: NO INSTALADO"
        fi
    done
    echo ""
    echo "--- Servicio ---"
    systemctl status fprintd 2>/dev/null | head -5 || warn "fprintd no encontrado"
    echo ""
    echo "--- Dispositivo ---"
    check_device || true
    echo ""
    echo "--- Configuración PAM ---"
    for f in "${PAM_FILES[@]}"; do
        if [ -f "$f" ]; then
            check_pam_configured "$f" && ok "fprint activo en $f" || echo "  [--] $f: sin fprint"
        else
            warn "$f: no existe"
        fi
    done
    echo ""
    echo "--- Huellas registradas ---"
    fprintd-list 2>/dev/null || echo "  (ejecutar 'fprintd-list' como root si hay errores)"
}

# ─── Main ───────────────────────────────────────────────────

MODE="${1:-}"
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  setup-fingerprint.sh — Fedora 44    ║"
echo "╚══════════════════════════════════════╝"
echo ""

case "$MODE" in
    --status|-s)
        show_status
        exit 0
        ;;
    --apply|-a)
        APPLY=true
        ;;
    --help|-h)
        echo "Uso: $0 [--status|--apply|--help]"
        echo ""
        echo "  (sin flag)  Modo interactivo: pregunta antes de cada paso"
        echo "  --status    Solo mostrar estado actual"
        echo "  --apply     Ejecutar cambios sin preguntar"
        echo "  --help      Mostrar esta ayuda"
        exit 0
        ;;
    *)
        APPLY=false
        ;;
esac

# ─── Paso 1: Verificar paquetes ─────────────────────────────
echo "── Paso 1: Paquetes ──"
MISSING=$(check_packages)
if [ -n "$MISSING" ]; then
    echo ""
    echo "  Paquetes faltantes: $MISSING"
    if [ "$APPLY" = true ]; then
        echo "  Instalando..."
        sudo dnf5 install -y $MISSING
        ok "Paquetes instalados"
    else
        echo "  Para instalar: sudo dnf5 install $MISSING"
    fi
else
    ok "Todos los paquetes necesarios están instalados"
fi
echo ""

# ─── Paso 2: Verificar dispositivo ──────────────────────────
echo "── Paso 2: Dispositivo ──"
check_device && DEVICE_OK=true || DEVICE_OK=false
echo ""

# ─── Paso 3: Verificar e iniciar servicio fprintd ──────────
echo "── Paso 3: Servicio fprintd ──"
if check_fprintd_service; then
    ok "Servicio funcionando"
else
    if [ "$APPLY" = true ]; then
        sudo systemctl enable --now fprintd
        ok "Servicio iniciado y habilitado"
    else
        echo "  Para iniciar: sudo systemctl enable --now fprintd"
    fi
fi
echo ""

# ─── Paso 4: Configurar PAM ─────────────────────────────────
echo "── Paso 4: PAM ──"
if [ "$APPLY" = true ]; then
    for pam_file in "${PAM_FILES[@]}"; do
        add_pam_line "$pam_file"
    done
else
    echo "  Archivos PAM a modificar:"
    for pam_file in "${PAM_FILES[@]}"; do
        if check_pam_configured "$pam_file"; then
            ok "Ya configurado: $pam_file"
        else
            echo "  [PENDIENTE] $pam_file"
        fi
    done
    echo ""
    echo "  Para aplicar: sudo $0 --apply"
    echo "  O editar manualmente cada archivo en /etc/pam.d/"
fi
echo ""

# ─── Resumen final ──────────────────────────────────────────
echo "═══════════════════════════════════════"
echo "  Resumen"
echo "═══════════════════════════════════════"
if [ "$APPLY" = false ] && [ -z "$MODE" ]; then
    echo ""
    echo "  Para registrar una huella después de la configuración:"
    echo "    fprintd-enroll"
    echo ""
    echo "  Para verificar el estado después de aplicar:"
    echo "    $0 --status"
elif [ "$APPLY" = true ]; then
    echo ""
    echo "  Configuración aplicada. Para registrar huella:"
    echo "    fprintd-enroll"
    echo ""
    echo "  Para verificar: fprintd-verify"
fi
echo ""

exit 0