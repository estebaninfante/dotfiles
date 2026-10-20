#!/usr/bin/env bash
# verify/espacios.sh — un espacio del escritorio por agente.
#
# Comprueba, sin criterio humano y sin tocar el escritorio real (ESPACIOS_SIN_ESC=1):
#   1. El registro reparte espacios distintos y es idempotente por agente.
#   2. Un agente cuyo proceso murió deja el espacio libre.
#   3. Los atajos de PATH (`xdg-open`, `kitty`, …) apuntan al comando.
#   4. `abrir` le pone al programa la clase del agente (`agente-<slug>`).
#   5. Sin agente, `abrir` es un pasamanos: no rompe nada del usuario.
#   6. La extensión de pi existe, engancha el PATH y deja el sonido afuera.
#
# Uso:
#   scripts/verify/espacios.sh          # texto
#   scripts/verify/espacios.sh --quiet  # solo FAIL/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ESPACIOS="$REPO/linux/bin/espacios"
EXT="$REPO/linux/pi/agent/extensions/espacios.ts"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }
aviso(){ [ "$QUIET" = 1 ] || printf '  aviso %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export ESPACIOS_DIR="$TMP/estado" ESPACIOS_SIN_ESC=1 ESPACIOS_MOVIMIENTO=0
unset PI_AGENTE PI_AGENTE_WS PI_AGENTE_SHIMS

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)"; }

# --- 1. reparto e idempotencia ------------------------------------------
a=$("$ESPACIOS" reclamar puma --pid $$ --json | json '["espacio"]') || a=""
b=$("$ESPACIOS" reclamar quetzal --pid $$ --json | json '["espacio"]') || b=""
a2=$("$ESPACIOS" reclamar puma --pid $$ --json | json '["espacio"]') || a2=""
if [[ "$a" =~ ^[0-9]+$ ]] && [[ "$b" =~ ^[0-9]+$ ]] && [ "$a" != "$b" ]; then
  ok "reparto: puma=$a quetzal=$b"
else
  fail "reparto: puma='$a' quetzal='$b' (deben ser números distintos)"
fi
if [ "$a" = "$a2" ]; then ok "idempotente: puma sigue en $a"; else fail "idempotente: $a → $a2"; fi

# --- 2. espacio libre cuando el proceso murió ---------------------------
muerto=$(sh -c 'echo $$')
"$ESPACIOS" reclamar colibri --pid "$muerto" >/dev/null 2>&1
c=$("$ESPACIOS" reclamar tucan --pid $$ --json | json '["espacio"]') || c=""
if [ "$c" != "$a" ] && [ "$c" != "$b" ]; then
  ok "muerto libera: tucan=$c"
else
  aviso "muerto libera: tucan=$c (reusó un espacio; puede pasar si el ws admite 2)"
fi

# --- 3. atajos de PATH --------------------------------------------------
shims="$("$ESPACIOS" reclamar puma --pid $$ --json | json '["shims"]')"
atajo="$shims/xdg-open"
if [ -x "$atajo" ] && grep -q "espacios" "$atajo" && grep -q 'abrir --bin' "$atajo"; then
  ok "atajo xdg-open → espacios"
else
  fail "atajo xdg-open: $atajo"
fi

# --- 4. la clase del agente va en el comando ----------------------------
mkdir -p "$TMP/fig"
cat > "$TMP/fig/kitty" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$(dirname "$0")/args.txt"
SH
chmod +x "$TMP/fig/kitty"
PI_AGENTE=puma "$ESPACIOS" abrir --bin "$TMP/fig/kitty" -- --title hola >/dev/null 2>&1
sleep 0.5
if grep -q -- '--class=agente-puma' "$TMP/fig/args.txt" 2>/dev/null; then
  ok "abrir agrega --class=agente-puma"
else
  fail "abrir no agregó la clase ($(cat "$TMP/fig/args.txt" 2>/dev/null | tr '\n' ' '))"
fi

# --- 5. sin agente es pasamanos -----------------------------------------
salida=$(env -u PI_AGENTE "$ESPACIOS" abrir -- /bin/echo hola-espacios 2>&1) || salida=""
if [ "$(printf '%s' "$salida" | tail -1)" = "hola-espacios" ]; then
  ok "sin agente: pasamanos"
else
  fail "sin agente: salida '$salida'"
fi

# --- 6. liberar ---------------------------------------------------------
"$ESPACIOS" liberar puma >/dev/null 2>&1
estado=$("$ESPACIOS" listar 2>/dev/null | awk '$2=="puma"{print $4}')
if [ "$estado" = "libre" ]; then ok "liberar deja el espacio libre"; else fail "liberar: estado '$estado'"; fi

# --- 6. la extensión de pi ----------------------------------------------
if [ -f "$EXT" ]; then
  ok "extensión presente"
else
  fail "falta $EXT"
fi
if grep -q 'PI_AGENTE_SHIMS' "$EXT" && grep -q 'process.env.PATH' "$EXT"; then
  ok "extensión engancha los atajos en el PATH"
else
  fail "extensión: no engancha el PATH"
fi
if grep -qi 'sonido' "$EXT" && grep -q 'notify-send' "$EXT"; then
  ok "extensión exceptúa el sonido"
else
  fail "extensión: no aclara la excepción de sonido"
fi
if [ -L "$HOME/.local/bin/espacios" ] || [ -x "$HOME/.local/bin/espacios" ]; then
  ok "comando instalado en ~/.local/bin"
else
  aviso "falta el symlink ~/.local/bin/espacios (corré scripts/link-dotfiles.sh)"
fi
if [ -L "$HOME/.pi/agent/extensions/espacios.ts" ] || [ -f "$HOME/.pi/agent/extensions/espacios.ts" ]; then
  ok "extensión instalada en ~/.pi/agent/extensions"
else
  aviso "falta el symlink de la extensión"
fi

if [ "$fails" -eq 0 ]; then
  [ "$QUIET" = 1 ] || printf '\nespacios: OK\n'
  exit 0
fi
printf '\nespacios: %d falla(s)\n' "$fails"
exit 1
