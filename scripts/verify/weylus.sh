#!/usr/bin/env bash
# verify/weylus.sh — chequeo determinista de Weylus (tablet como tableta gráfica).
#
# Solo lee; no cambia nada. Sale 0 si el interruptor, los scripts, los servicios
# y la fila del menu de Omarchy estan como corresponde; 1 si algo se rompio.
#
# Uso:
#   scripts/verify/weylus.sh            # texto
#   scripts/verify/weylus.sh --quiet    # solo FAIL
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${HOME}/.local/bin"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/weylus/on"
MENU_LIVE="${OMARCHY_CONFIG_DIR:-$HOME/.config/omarchy}/extensions/omarchy-menu.jsonc"
MENU_REPO="$REPO/linux/config/omarchy/extensions/omarchy-menu.jsonc"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
warn() { [ "$QUIET" = 1 ] || printf '  AVISO %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- scripts versionados y enlazados --------------------------------------
for nombre in weylus-toggle weylus-tablet-watch weylus-instalar; do
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

# --- el vigilante respeta el interruptor ----------------------------------
watch="$REPO/linux/bin/weylus-tablet-watch"
if [ -f "$watch" ]; then
    grep -q 'state/weylus/on' "$watch" \
        && ok "el vigilante mira el estado del interruptor" \
        || fail "el vigilante no mira ~/.local/state/weylus/on (armaria el tunel igual con el modo apagado)"
fi

# --- servicios coherentes con el interruptor ------------------------------
encendido=0
[ -e "$STATE" ] && encendido=1
if [ "$encendido" = 1 ]; then
    for unidad in weylus.service weylus-tablet.service; do
        systemctl --user is-enabled --quiet "$unidad" \
            && ok "$unidad habilitado" \
            || fail "$unidad deberia estar habilitado (interruptor en on)"
        systemctl --user is-active --quiet "$unidad" \
            && ok "$unidad corriendo" \
            || fail "$unidad deberia estar corriendo (interruptor en on)"
    done
    curl -fsS --connect-timeout 1 --max-time 2 -o /dev/null http://localhost:1701/ \
        && ok "Weylus responde en http://localhost:1701" \
        || fail "Weylus no responde en el puerto 1701"
else
    for unidad in weylus.service weylus-tablet.service; do
        systemctl --user is-active --quiet "$unidad" \
            && fail "$unidad sigue corriendo con el interruptor en off" \
            || ok "$unidad detenido (modo apagado)"
    done
fi

# --- acceso por WiFi (firewall) -------------------------------------------
# Por USB el tunel adb no pasa por el firewall; por WiFi si. Si ufw esta
# activo, el puerto tiene que estar abierto para la red local.
if systemctl is-active --quiet ufw 2>/dev/null; then
    if ! reglas="$(sudo -n ufw status 2>/dev/null)"; then
        warn "no puedo leer las reglas de ufw sin sudo; revisá a mano que 1701/tcp este permitido"
    elif grep -q '^1701/tcp' <<<"$reglas"; then
        ok "el firewall deja entrar al 1701 (WiFi)"
    else
        fail "ufw activo y sin regla para 1701/tcp: la tablet no va a conectar por WiFi"
    fi
fi

# --- fila en el menu de Omarchy -------------------------------------------
for menu in "$MENU_LIVE" "$MENU_REPO"; do
    [ -f "$menu" ] || { fail "no existe $menu"; continue; }
    if grep -q '"trigger.toggle.weylus"' "$menu"; then
        ok "fila de menu presente en $menu"
    else
        fail "falta la fila trigger.toggle.weylus en $menu"
    fi
done
if [ -f "$MENU_LIVE" ] && [ -f "$MENU_REPO" ] && ! diff -q "$MENU_LIVE" "$MENU_REPO" >/dev/null; then
    fail "la config viva de Omarchy difiere del repo (correr scripts/omarchy-sync.sh export)"
fi

[ "$fails" -eq 0 ] && { [ "$QUIET" = 1 ] || echo "Weylus: todo en orden"; exit 0; }
echo "Weylus: $fails problema(s)" >&2
exit 1
