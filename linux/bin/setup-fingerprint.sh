#!/bin/bash
# ==========================================================
# setup-fingerprint.sh
# Instala y configura soporte para huella dactilar en
# Fedora con fprintd + authselect.
#
# USO:
#   ./setup-fingerprint.sh          # Modo interactivo
#   ./setup-fingerprint.sh --apply  # Ejecutar cambios directamente
#   ./setup-fingerprint.sh --status # Solo mostrar estado actual
#
# IDEMPOTENTE: Puede ejecutarse múltiples veces sin romper nada.
# ==========================================================

set -euo pipefail

# ─── Configuración ──────────────────────────────────────────
REQUIRED_PKGS=(
    fprintd
    fprintd-pam
    hyprpolkitagent
)

# ─── Funciones ──────────────────────────────────────────────

info()    { echo -e "  [INFO] $*"; }
ok()      { echo -e "  [OK]   $*"; }
warn()    { echo -e "  [WARN] $*"; }
error()   { echo -e "  [ERROR] $*"; }

check_packages() {
    local missing=()
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            ok "$pkg ya instalado"
        else
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "${missing[@]}"
    fi
}

check_device() {
    if fprintd-list 2>/dev/null | grep -q "devices\|Device"; then
        ok "Dispositivo de huella detectado"
        return 0
    fi
    warn "No se detectó dispositivo de huella"
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

check_authselect() {
    local profile
    profile=$(authselect current 2>/dev/null | grep "Profile ID:" | awk '{print $NF}')
    if [ -z "$profile" ]; then
        warn "authselect no configurado"
        return 1
    fi
    if authselect current 2>/dev/null | grep -q "with-fingerprint"; then
        ok "authselect: with-fingerprint ya habilitado"
        return 0
    fi
    warn "authselect: with-fingerprint NO habilitado (perfil: $profile)"
    return 1
}

check_fingers_enrolled() {
    local user
    user=$(whoami)
    if fprintd-list "$user" 2>/dev/null | grep -q "Finger\|finger"; then
        ok "Huellas registradas para $user"
        return 0
    fi
    warn "Sin huellas registradas para $user"
    return 1
}

check_polkit_agent() {
    if systemctl --user is-active --quiet hyprpolkitagent 2>/dev/null; then
        ok "Agente polkit (hyprpolkitagent) activo"
        return 0
    fi
    warn "Agente polkit NO activo (fprintd-enroll requiere autenticación polkit)"
    return 1
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
    echo "--- Authselect ---"
    authselect current 2>/dev/null || warn "authselect no disponible"
    echo ""
    echo "--- Agente polkit ---"
    check_polkit_agent || true
    echo ""
    echo "--- Huellas registradas ---"
    fprintd-list "$(whoami)" 2>/dev/null || warn "Sin huellas"
    echo ""
    echo "--- Archivos PAM (hyprlock) ---"
    if [ -f /etc/pam.d/hyprlock ]; then
        ok "/etc/pam.d/hyprlock existe:"
        cat /etc/pam.d/hyprlock
    else
        warn "/etc/pam.d/hyprlock no existe"
    fi
    echo ""
}

# ─── Main ───────────────────────────────────────────────────

MODE="${1:-}"
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  setup-fingerprint.sh — Fedora       ║"
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

# ─── Paso 4: Configurar authselect ──────────────────────────
echo "── Paso 4: Authselect (método oficial Fedora) ──"
if check_authselect; then
    ok "Fingerprint ya habilitado en authselect"
else
    if [ "$APPLY" = true ]; then
        info "Habilitando with-fingerprint en authselect..."
        sudo authselect enable-feature with-fingerprint
        ok "authselect: with-fingerprint habilitado"
        info "PAM configurado automáticamente para: sudo, gdm, login, system-auth"
    else
        echo "  Para habilitar: sudo authselect enable-feature with-fingerprint"
    fi
fi
echo ""

# ─── Paso 4b: Agente polkit ────────────────────────────────
echo "── Paso 4b: Agente polkit ──"
if check_polkit_agent; then
    ok "Agente polkit funcionando"
else
    if [ "$APPLY" = true ]; then
        info "Iniciando hyprpolkitagent..."
        systemctl --user start hyprpolkitagent 2>/dev/null && ok "hyprpolkitagent iniciado" || warn "No se pudo iniciar (¿estás en Hyprland?)"
    else
        echo "  Para iniciar: systemctl --user start hyprpolkitagent"
    fi
fi
echo ""

# ─── Paso 5: Verificar hyprlock PAM ─────────────────────────
echo "── Paso 5: PAM hyprlock ──"
if [ -f /etc/pam.d/hyprlock ]; then
    if grep -q "account.*include" /etc/pam.d/hyprlock && grep -q "session.*include" /etc/pam.d/hyprlock; then
        ok "/etc/pam.d/hyprlock completo"
    else
        warn "/etc/pam.d/hyprlock incompleto (falta account/session)"
        if [ "$APPLY" = true ]; then
            info "Corrigiendo /etc/pam.d/hyprlock..."
            sudo cp /etc/pam.d/hyprlock /etc/pam.d/hyprlock.bak.$(date +%Y%m%d_%H%M%S)
            sudo tee /etc/pam.d/hyprlock > /dev/null << 'PAM'
# PAM configuration file for hyprlock

auth        include     login

account     include     login

session     optional    pam_keyinit.so force revoke
session     include     login
PAM
            ok "/etc/pam.d/hyprlock corregido"
        else
            echo "  Para corregir: ejecuta $0 --apply"
        fi
    fi
else
    warn "/etc/pam.d/hyprlock no existe"
    if [ "$APPLY" = true ]; then
        info "Creando /etc/pam.d/hyprlock..."
        sudo tee /etc/pam.d/hyprlock > /dev/null << 'PAM'
# PAM configuration file for hyprlock

auth        include     login

account     include     login

session     optional    pam_keyinit.so force revoke
session     include     login
PAM
        ok "/etc/pam.d/hyprlock creado"
    else
        echo "  Para crear: ejecuta $0 --apply"
    fi
fi
echo ""

# ─── Paso 6: Verificar huellas ──────────────────────────────
echo "── Paso 6: Huellas registradas ──"
if check_fingers_enrolled; then
    ok "Ya tienes huellas registradas"
else
    echo ""
    echo "  Para registrar huella: fprintd-enroll"
    echo ""
fi
echo ""

# ─── Resumen final ──────────────────────────────────────────
echo "═══════════════════════════════════════"
echo "  Resumen"
echo "═══════════════════════════════════════"
echo ""
echo "  Configuración PAM: authselect (oficial Fedora)"
echo "  GDM:       habilitado via authselect with-fingerprint"
echo "  Hyprlock:  habilitado via /etc/pam.d/hyprlock + config"
echo "  sudo:      habilitado via authselect with-fingerprint"
echo ""
if ! check_fingers_enrolled 2>/dev/null; then
    echo "  SIGUIENTE PASO: fprintd-enroll"
    echo ""
fi
echo "  Verificar estado: $0 --status"
echo ""
