#!/usr/bin/env bash
# verify/wifi-sync.sh — chequeo determinista de la replicación de perfiles
# WiFi entre las dos máquinas (wifi-sync + dispatcher de NetworkManager).
#
# Sin peer: valida scripts, unit del dispatcher y que el modo --dry no toque
# nada. Sale 0 si todo está en su lugar.
#
# Uso: scripts/verify/wifi-sync.sh [--quiet]
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

REPO="${HOME}/dotfiles"
BIN="$REPO/linux/bin/wifi-sync"
DISP="$REPO/linux/system/NetworkManager/dispatcher.d/91-wifi-sync"

[ -x "$BIN" ] && ok "wifi-sync ejecutable" || fail "wifi-sync falta o no es ejecutable"
bash -n "$BIN" 2>/dev/null && ok "wifi-sync sintaxis" || fail "wifi-sync no parsea"

[ -f "$DISP" ] && ok "dispatcher 91-wifi-sync en el repo" || fail "falta dispatcher 91-wifi-sync"
sh -n "$DISP" 2>/dev/null && ok "dispatcher sintaxis" || fail "dispatcher no parsea"

grep -q '91-wifi-sync' "$REPO/scripts/setup-omarchy.sh" \
    && ok "setup-omarchy instala el dispatcher" \
    || fail "setup-omarchy no instala el dispatcher"

# El dispatcher solo debe disparar en 'up' de WiFi.
grep -q 'ACTION.*=.*up' "$DISP" && ok "dispatcher filtra action=up" \
    || fail "dispatcher no filtra action=up"
grep -q 'GENERAL.TYPE.*wifi' "$DISP" && ok "dispatcher filtra WiFi" \
    || fail "dispatcher no filtra WiFi"

# --dry con un peer inalcanzable: debe salir 0 y no escribir perfiles.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
XDG_STATE_HOME="$tmp" LAN_MOUSE_CONFIG=/dev/null timeout 40 "$BIN" --dry >/dev/null 2>&1
rc=$?
[ "$rc" = 0 ] && ok "--dry sale 0 sin peer" || fail "--dry salió $rc"

if [ "$fails" = 0 ]; then
    [ "$QUIET" = 1 ] || echo "PASS wifi-sync"
    exit 0
fi
echo "FAIL wifi-sync ($fails)"
exit 1
