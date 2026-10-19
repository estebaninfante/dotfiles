#!/usr/bin/env bash
# verify/agentes.sh — identidad de agentes y trazabilidad de tickets.
#
# Comprueba, sin criterio humano:
#   1. El reparto de colores da colores únicos (identity.py selftest).
#   2. No hay dos agentes vivos con el mismo color (tmux, si hay servidor).
#   3. El árbol de tickets (raíz → pedidos → delegaciones) funciona
#      (node --test lib/trazas.test.ts).
#   4. El rig reclama color al arrancar y crea subtickets (código presente).
#
# Uso:
#   scripts/verify/agentes.sh          # texto
#   scripts/verify/agentes.sh --quiet  # solo FAIL/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IDENTITY="$REPO/linux/voice/identity.py"
CONVERSAR="$REPO/linux/pi/agent/extensions/conversar.ts"
RIG_TS="$REPO/linux/pi/agent/extensions/rig.ts"
RIG_SH="$REPO/linux/bin/rig"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }
aviso(){ [ "$QUIET" = 1 ] || printf '  aviso %s\n' "$*"; }

# --- 1. colores únicos en el reparto ------------------------------------
if out=$(python3 "$IDENTITY" selftest 2>&1); then
  ok "identity: ${out}"
else
  fail "identity: ${out:-sin salida}"
fi

# --- 2. colores únicos entre agentes vivos ------------------------------
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
  if out=$(python3 "$IDENTITY" check 2>&1); then
    ok "vivos: ${out}"
  else
    fail "vivos: ${out}"
  fi
else
  aviso "sin servidor tmux: no hay agentes vivos que revisar"
fi

# --- 3. árbol de tickets ------------------------------------------------
if out=$(node --test "$REPO/linux/pi/agent/extensions/lib/trazas.test.ts" 2>&1); then
  ok "árbol de tickets: $(printf '%s\n' "$out" | awk '/^ℹ pass /{print $3; exit}') pruebas"
else
  fail "árbol de tickets: node --test falló"
  printf '%s\n' "$out" | tail -20 >&2
fi

# --- 4. el rig no puede perder estas piezas -----------------------------
grep -q -- '--claim' "$CONVERSAR" \
  && ok "conversar: reclama color al arrancar" \
  || fail "conversar: no reclama color (--claim)"
grep -q 'reclamarColorSiRepetido' "$CONVERSAR" \
  && ok "conversar: corrige colores repetidos en cada turno" \
  || fail "conversar: no corrige colores repetidos"
grep -q 'tipo: "sesion"' "$RIG_TS" \
  && ok "rig: ticket raíz por sesión (un agente = un ticket)" \
  || fail "rig: falta el ticket raíz de sesión"
grep -q '"subtarea"' "$RIG_TS" \
  && ok "rig: subtickets para pedidos y delegaciones" \
  || fail "rig: faltan los subtickets"
grep -q 'markdownTraza' "$RIG_TS" \
  && ok "rig: traza en Markdown para el usuario" \
  || fail "rig: falta la traza en Markdown"
grep -q 'ticket_live_seat' "$RIG_SH" \
  && ok "rig: un ticket no lo trabaja más de un agente vivo" \
  || fail "rig: falta el candado de un agente por ticket"

if [ "$fails" = 0 ]; then
  [ "$QUIET" = 1 ] || echo "PASS agentes"
  exit 0
fi
echo "FAIL agentes ($fails)"
exit 1
