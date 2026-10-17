#!/usr/bin/env bash
# verify/cursor.sh — el puntero no se esconde por inactividad.
#
# Solo lee; no cambia nada. Sale 0 si la config gestionada evita el ocultado
# accidental del cursor. El caso real: `mouse_hide_wait 3` en kitty hacía que
# el puntero desapareciera a los 3 s de quietud sobre la terminal y volviera
# recién al moverlo. Se apaga con `mouse_hide_wait 0`.
#
# Uso:
#   scripts/verify/cursor.sh          # texto
#   scripts/verify/cursor.sh --quiet  # solo FAIL/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KITTY="$REPO/linux/config/kitty/kitty.conf"
LOOKNFEEL="$REPO/linux/config/hypr/looknfeel.lua"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- kitty: no ocultar el mouse por inactividad ---------------------------
if [ ! -f "$KITTY" ]; then
    fail "no existe $KITTY"
else
    v="$(awk '$1 == "mouse_hide_wait" {print $2; exit}' "$KITTY")"
    if [ "$v" = "0" ]; then
        ok "kitty: mouse_hide_wait 0"
    elif [ -z "$v" ]; then
        fail "kitty sin mouse_hide_wait (default 3 s: el cursor se esconde)"
    else
        fail "kitty: mouse_hide_wait=$v (debe ser 0)"
    fi
fi

# --- Hyprland: que nadie configure lo contrario ---------------------------
if [ ! -f "$LOOKNFEEL" ]; then
    fail "no existe $LOOKNFEEL"
else
    if grep -qE '^\s*invisible\s*=\s*(1|true)' "$LOOKNFEEL"; then
        fail "looknfeel.lua tiene cursor:invisible activo"
    else
        ok "looknfeel.lua: cursor no invisible"
    fi

    t="$(sed -n 's/^[[:space:]]*inactive_timeout[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$LOOKNFEEL" | head -1)"
    if [ -n "$t" ] && [ "$t" != "0" ]; then
        fail "looknfeel.lua: inactive_timeout=$t (debe ser 0 o no estar)"
    else
        ok "looknfeel.lua: inactive_timeout sin ocultado"
    fi
fi

if [ "$fails" = 0 ]; then
    [ "$QUIET" = 1 ] || echo "PASS cursor"
    exit 0
fi
echo "FAIL cursor ($fails)"
exit 1
