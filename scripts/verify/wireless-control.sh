#!/usr/bin/env bash
# verify/wireless-control.sh — chequeo determinista de Wireless Control
# (tablet o celular como tableta gráfica; el motor es Weylus).
#
# Solo lee; no cambia nada. Sale 0 si el interruptor, los scripts, los servicios
# y la fila del menú de Omarchy están como corresponde; 1 si algo se rompió.
#
# Uso:
#   scripts/verify/wireless-control.sh            # texto
#   scripts/verify/wireless-control.sh --quiet    # solo FAIL
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${HOME}/.local/bin"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/wireless-control/on"
MENU_LIVE="${OMARCHY_CONFIG_DIR:-$HOME/.config/omarchy}/extensions/omarchy-menu.jsonc"
MENU_REPO="$REPO/linux/config/omarchy/extensions/omarchy-menu.jsonc"
UNITS="wireless-control.service wireless-control-tablet.service"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
warn() { [ "$QUIET" = 1 ] || printf '  AVISO %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- comandos: versionados y enlazados ------------------------------------
# wireless-control y wireless-control-usb viven en el repo (symlink).
for nombre in wireless-control wireless-control-usb; do
    src="$REPO/linux/bin/$nombre"
    if [ ! -x "$src" ]; then
        fail "falta o no es ejecutable: linux/bin/$nombre"
    elif [ ! -L "$BIN/$nombre" ]; then
        fail "$BIN/$nombre no es un symlink al repo"
    elif [ "$(readlink -f "$BIN/$nombre")" != "$src" ]; then
        fail "$BIN/$nombre apunta a otro lado ($(readlink "$BIN/$nombre"))"
    else
        ok "$nombre enlazado al repo"
    fi
    if [ -x "$src" ] && ! bash -n "$src" 2>/dev/null; then
        fail "linux/bin/$nombre tiene error de sintaxis"
    fi
done

# El instalador y el vigilante los genera el instalador (no son symlinks).
for nombre in wireless-control-instalar wireless-control-watch; do
    if [ ! -x "$BIN/$nombre" ]; then
        fail "falta o no es ejecutable: $BIN/$nombre (correr wireless-control-instalar)"
    elif ! bash -n "$BIN/$nombre" 2>/dev/null; then
        fail "$BIN/$nombre tiene error de sintaxis"
    else
        ok "$nombre instalado"
    fi
done

# El vigilante respeta el interruptor.
watch="$BIN/wireless-control-watch"
if [ -f "$watch" ]; then
    grep -q 'state/wireless-control/on' "$watch" \
        && ok "el vigilante mira el estado del interruptor" \
        || fail "el vigilante no mira ~/.local/state/wireless-control/on"
fi

# --- servicios coherentes con el interruptor ------------------------------
encendido=0
[ -e "$STATE" ] && encendido=1
if [ "$encendido" = 1 ]; then
    for unidad in $UNITS; do
        systemctl --user is-enabled --quiet "$unidad" \
            && ok "$unidad habilitado" \
            || fail "$unidad debería estar habilitado (interruptor en on)"
        systemctl --user is-active --quiet "$unidad" \
            && ok "$unidad corriendo" \
            || fail "$unidad debería estar corriendo (interruptor en on)"
    done
    systemctl --user is-active --quiet hypr-outline.service \
        && ok "hypr-outline corriendo" \
        || fail "hypr-outline.service debería estar corriendo"
    curl -fsS --connect-timeout 1 --max-time 2 -o /dev/null http://localhost:1701/ \
        && ok "el motor (weylus) responde en http://localhost:1701" \
        || fail "weylus no responde en el puerto 1701"
    # La piel y la interfaz del proyecto tienen que estar servidas, no las de weylus.
    curl -fsS --connect-timeout 1 --max-time 2 http://localhost:1701/style.css 2>/dev/null \
        | grep -q 'Wireless Control' \
        && ok "la piel de Wireless Control está servida" \
        || fail "style.css servido no es la piel de Wireless Control (falta --custom-style-css)"
    curl -fsS --connect-timeout 1 --max-time 2 http://localhost:1701/lib.js 2>/dev/null \
        | grep -q 'hyo-pista' \
        && ok "la interfaz (overlay) está inyectada" \
        || fail "lib.js servido no tiene el overlay de Wireless Control"
else
    for unidad in $UNITS; do
        systemctl --user is-active --quiet "$unidad" \
            && fail "$unidad sigue corriendo con el interruptor en off" \
            || ok "$unidad detenido (modo apagado)"
    done
fi

# --- acceso por WiFi (firewall) -------------------------------------------
if systemctl is-active --quiet ufw 2>/dev/null; then
    if ! reglas="$(sudo -n ufw status 2>/dev/null)"; then
        warn "no puedo leer las reglas de ufw sin sudo; revisá a mano que 1701/tcp esté permitido"
    elif grep -q '^1701/tcp' <<<"$reglas"; then
        ok "el firewall deja entrar al 1701 (WiFi/tailnet)"
    else
        fail "ufw activo y sin regla para 1701/tcp: el celular no va a conectar"
    fi
fi

# --- touchpad: depende de ydotool ---
if command -v ydotool >/dev/null 2>&1; then
    ok "ydotool instalado (touchpad nativo)"
else
    fail "falta ydotool: el modo touchpad no puede mover el puntero"
fi
if pgrep -x ydotoold >/dev/null 2>&1; then
    ok "ydotoold corriendo"
else
    warn "ydotoold no está corriendo: el touchpad no va a mover el puntero"
fi
curl -fsS --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:1781/api/pointer?dx=0&dy=0" >/dev/null 2>&1 \
    && ok "el API del puntero responde" \
    || fail "el API del puntero no responde en 1781"

# --- fila en el menú de Omarchy -------------------------------------------
for menu in "$MENU_LIVE" "$MENU_REPO"; do
    [ -f "$menu" ] || { fail "no existe $menu"; continue; }
    if grep -q '"trigger.toggle.wireless-control"' "$menu"; then
        ok "fila de menú presente en $menu"
    else
        fail "falta la fila trigger.toggle.wireless-control en $menu"
    fi
done
if [ -f "$MENU_LIVE" ] && [ -f "$MENU_REPO" ] && ! diff -q "$MENU_LIVE" "$MENU_REPO" >/dev/null; then
    fail "la config viva de Omarchy difiere del repo (correr scripts/omarchy-sync.sh export)"
fi

# --- no quedan restos del nombre viejo ------------------------------------
if command -v systemctl >/dev/null 2>&1 && systemctl --user cat weylus.service >/dev/null 2>&1; then
    fail "sigue existiendo weylus.service (quedó del nombre viejo)"
fi
if [ -e "$BIN/weylus-toggle" ]; then
    fail "sigue existiendo ~/.local/bin/weylus-toggle"
fi

[ "$fails" -eq 0 ] && { [ "$QUIET" = 1 ] || echo "Wireless Control: todo en orden"; exit 0; }
echo "Wireless Control: $fails problema(s)" >&2
exit 1
