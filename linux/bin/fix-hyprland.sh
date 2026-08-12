#!/bin/bash
# ==========================================================
# fix-hyprland.sh
# Diagnóstico y reparación de problemas comunes en
# Hyprland (NixOS, Wayland).
#
# USO:
#   ./fix-hyprland.sh            # Diagnóstico completo
#   ./fix-hyprland.sh --quick    # Diagnóstico rápido (solo vital)
#   ./fix-hyprland.sh --logs     # Solo mostrar logs recientes
#   ./fix-hyprland.sh --restart  # Reiniciar Hyprland (con aviso)
#   ./fix-hyprland.sh --help     # Mostrar ayuda
#
# IDEMPOTENTE: Solo lectura por defecto.
# ==========================================================

set -euo pipefail

# ─── Configuración ──────────────────────────────────────────
HYPR_CONFIG="$HOME/.config/hypr/hyprland.conf"
HYPR_ENV_FILE="$HOME/.config/hypr/hyprland_env.conf"
LOG_CMD="journalctl --user -xe -u hyprland"
LOG_COUNT=30

# ─── Funciones ──────────────────────────────────────────────

info()    { echo -e "  [INFO] $*"; }
ok()      { echo -e "  [OK]   $*"; }
warn()    { echo -e "  [WARN] $*"; }
error()   { echo -e "  [ERROR] $*"; }
header()  { echo ""; echo "── $* ──"; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        warn "$1 no encontrado en PATH"
        return 1
    fi
    return 0
}

check_hyprland_running() {
    if pgrep -x Hyprland &>/dev/null; then
        ok "Hyprland en ejecución (PID: $(pgrep -x Hyprland))"
        return 0
    else
        warn "Hyprland NO está en ejecución"
        return 1
    fi
}

check_hyprctl() {
    if check_command hyprctl; then
        if hyprctl monitors 2>/dev/null | head -5 | grep -qi "Monitor"; then
            return 0
        fi
        warn "hyprctl disponible pero no responde (¿Hyprland corriendo?)"
        return 1
    fi
    return 1
}

check_wlr_errors() {
    local log_lines
    log_lines=$(journalctl --user -u hyprland -n 100 --no-pager 2>/dev/null | grep -ciE "error|fail|crash|segfault|assert" || true)
    if [ "$log_lines" -gt 0 ]; then
        warn "Se encontraron $log_lines líneas con errores en los últimos 100 mensajes de hyprland"
        journalctl --user -u hyprland -n 50 --no-pager 2>/dev/null | grep -iE "error|fail|crash|segfault|assert" | tail -10 || true
        return 1
    fi
    ok "Sin errores críticos en logs recientes de hyprland"
    return 0
}

check_config_syntax() {
    if [ ! -f "$HYPR_CONFIG" ]; then
        warn "Archivo de configuración no encontrado: $HYPR_CONFIG"
        return 1
    fi
    # Verificación básica de sintaxis
    local errors
    errors=$(hyprctl -j 2>/dev/null | head -1 || echo "")
    # No hay un verificador de sintaxis nativo, validamos con grep
    if grep -n "bind" "$HYPR_CONFIG" | grep -v "^#" | grep -qvE "SUPER|ALT|CTRL|SHIFT"; then
        warn "Posibles binds sin modificador estándar en $HYPR_CONFIG"
    fi
    # Verificar llaves balanceadas (para configs con bloques {})
    local opens closes
    opens=$(grep -c '{' "$HYPR_CONFIG" 2>/dev/null || echo 0)
    closes=$(grep -c '}' "$HYPR_CONFIG" 2>/dev/null || echo 0)
    if [ "$opens" -ne "$closes" ]; then
        error "Llaves desbalanceadas: $opens abiertas, $closes cerradas"
        return 1
    fi
    ok "Sintaxis básica de config OK (líneas totales: $(wc -l < "$HYPR_CONFIG"))"
    return 0
}

check_env_file() {
    if [ -f "$HYPR_ENV_FILE" ]; then
        info "Archivo de entorno encontrado: $HYPR_ENV_FILE"
        grep -v "^#" "$HYPR_ENV_FILE" | grep -v "^$" | while read -r line; do
            echo "    $line"
        done
        return 0
    fi
    # Verificar variables de entorno comunes
    local vars_ok=true
    for var in XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP; do
        if [ -z "${!var:-}" ]; then
            warn "$var no está definida"
            vars_ok=false
        fi
    done
    [ "$vars_ok" = true ] && ok "Variables de entorno Wayland presentes"
    return 0
}

check_services() {
    header "Servicios de usuario"
    local services=("waybar" "mako" "wl-clipboard" "swaync")
    for svc in "${services[@]}"; do
        if systemctl --user is-active "$svc" &>/dev/null 2>&1; then
            ok "$svc activo"
        elif command -v "$svc" &>/dev/null; then
            echo "  [--] $svc instalado pero no como servicio systemd"
        else
            echo "  [--] $svc no instalado"
        fi
    done
}

check_keyboard_layout() {
    header "Layout de teclado"
    if check_command hyprctl && check_hyprland_running; then
        local layout
        layout=$(hyprctl devices -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); k=d.get('keyboards',[{}])[0]; print(k.get('name','?'), k.get('layout','?'))" 2>/dev/null || true)
        if [ -n "$layout" ]; then
            ok "Teclado: $layout"
        fi
    fi
    if [ -f "$HYPR_CONFIG" ]; then
        grep -i "kb_layout" "$HYPR_CONFIG" | head -3 || warn "No se encontró kb_layout en config"
    fi
}

check_logs() {
    header "Últimos $LOG_COUNT mensajes de hyprland"
    if journalctl --user -u hyprland -n "$LOG_COUNT" --no-pager 2>/dev/null | grep -q .; then
        journalctl --user -u hyprland -n "$LOG_COUNT" --no-pager 2>/dev/null | tail -n "$LOG_COUNT"
    else
        warn "No hay logs de hyprland (systemd --user)"
    fi
}

quick_diagnostic() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║  fix-hyprland.sh — Diagnóstico       ║"
    echo "╚══════════════════════════════════════╝"

    header "Estado"
    if check_hyprland_running; then
        if check_hyprctl; then
            hyprctl monitors 2>/dev/null | head -5
        fi
    fi

    header "Logs (errores)"
    journalctl --user -u hyprland -n 50 --no-pager 2>/dev/null | grep -iE "error|fail|crash" | tail -10 || echo "  (sin errores recientes)"

    header "Config"
    [ -f "$HYPR_CONFIG" ] && ok "Config existe: $HYPR_CONFIG ($(wc -l < "$HYPR_CONFIG") líneas)" || error "Config no encontrada"
}

full_diagnostic() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║  fix-hyprland.sh — Diagnóstico FULL   ║"
    echo "╚═══════════════════════════════════════╝"

    header "1. Proceso Hyprland"
    check_hyprland_running

    header "2. hyprctl"
    check_hyprctl

    header "3. Monitores"
    if check_hyprctl; then
        hyprctl monitors 2>/dev/null | grep -E "Monitor|resolution|scale|refresh" || warn "No se pudieron leer monitores"
    fi

    header "4. Workspaces"
    if check_hyprctl; then
        hyprctl workspaces 2>/dev/null | grep -E "workspace ID|windows|monitor" | head -10 || true
    fi

    header "5. Archivos de configuración"
    [ -f "$HYPR_CONFIG" ]   && ok "hyprland.conf: $HYPR_CONFIG" || error "Falta hyprland.conf"
    [ -f "$HYPR_ENV_FILE" ] && ok "hyprland_env.conf: $HYPR_ENV_FILE" || warn "No existe archivo de entorno separado"

    header "6. Sintaxis de configuración"
    check_config_syntax || true

    header "7. Variables de entorno"
    check_env_file || true

    header "8. Logs de hyprland (errores)"
    check_wlr_errors || true

    header "9. Servicios de usuario"
    check_services

    header "10. Layout de teclado"
    check_keyboard_layout

    header "11. Logs (recientes)"
    check_logs

    header "12. Resumen de herramientas"
    for cmd in hyprctl grim slurp wl-paste wl-copy swaylock makoctl; do
        if check_command "$cmd" &>/dev/null; then
            echo "  [OK]   $cmd"
        else
            echo "  [MISS] $cmd (no instalado)"
        fi
    done

    echo ""
    echo "── Diagnóstico completado ──"
}

restart_hyprland() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║  Reiniciar Hyprland                  ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    warn "Esto cerrará la sesión actual de Hyprland."
    echo "  Presiona Ctrl+C para cancelar o espera 5 segundos..."
    sleep 5
    echo "  Reiniciando..."
    if pgrep -x Hyprland &>/dev/null; then
        hyprctl dispatch exit 2>/dev/null || loginctl terminate-user "$USER"
    else
        warn "Hyprland no está corriendo"
    fi
}

# ─── Main ───────────────────────────────────────────────────

MODE="${1:-}"

case "$MODE" in
    --quick|-q)
        quick_diagnostic
        ;;
    --logs|-l)
        check_logs
        ;;
    --restart|-r)
        restart_hyprland
        ;;
    --help|-h)
        echo "Uso: $0 [--quick|--logs|--restart|--help]"
        echo ""
        echo "  (sin flag)  Diagnóstico completo"
        echo "  --quick     Diagnóstico rápido (resumen)"
        echo "  --logs      Últimos $LOG_COUNT logs de hyprland"
        echo "  --restart   Reiniciar Hyprland (con espera de seguridad)"
        echo "  --help      Mostrar ayuda"
        exit 0
        ;;
    *)
        full_diagnostic
        ;;
esac

exit 0