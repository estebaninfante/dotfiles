#!/usr/bin/env bash
# verify/pi-clean.sh — "pi clean" arranca pi con configuración de fábrica.
#
# Comprueba, sin criterio humano:
#   1. pi-clean existe, es ejecutable y está enlazado en ~/.local/bin.
#   2. `pi clean` llega al script (el lanzador lo intercepta).
#   3. La config limpia solo tiene credenciales: nada de skills, agentes,
#      extensiones, MCP, settings, AGENTS.md ni model-fallback.
#   4. La carpeta temporal se borra al salir; PI_CLEAN_DIR se conserva.
#
# Uso:
#   scripts/verify/pi-clean.sh           # texto
#   scripts/verify/pi-clean.sh --quiet   # solo fallas
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/linux/bin/pi-clean"
WRAPPER="$REPO/linux/bin/pi"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- 1. script presente y enlazado -----------------------------------------
if [[ -x "$SCRIPT" ]]; then
  ok "pi-clean ejecutable"
else
  fail "pi-clean no existe o no es ejecutable: $SCRIPT"
fi
if [[ "$(readlink -f "$HOME/.local/bin/pi-clean" 2>/dev/null)" == "$(readlink -f "$SCRIPT")" ]]; then
  ok "~/.local/bin/pi-clean apunta al repo"
else
  fail "~/.local/bin/pi-clean no apunta a $SCRIPT"
fi

# --- 2 y 3. `pi clean` aísla la configuración ------------------------------
out="$(PI_CLEAN_DEBUG=1 "$REPO/linux/bin/pi" clean --list-models 2>&1)"
if grep -q "contenido:" <<<"$out"; then
  ok "el lanzador deriva 'clean' a pi-clean"
else
  fail "'pi clean' no llegó a pi-clean: $out"
fi
content="$(sed -n 's/^contenido: //p' <<<"$out")"
forbidden=0
for name in skills agents extensions mcp.json settings.json AGENTS.md themes model-fallback models.json; do
  if grep -qE "(^| )${name//./\\.}( |$)" <<<"$content"; then
    fail "la config limpia trae $name"
    forbidden=1
  fi
done
[ "$forbidden" = 0 ] && ok "config limpia sin cargas propias (contenido: ${content:-vacío})"
dir="$(sed -n 's/^PI_CODING_AGENT_DIR=//p' <<<"$out")"
case "$dir" in
  "$HOME/.pi/agent"|"") fail "la config limpia apunta a la config real: ${dir:-vacío}" ;;
  *) ok "config limpia en ${dir:-?}" ;;
esac

# --- 4. temporales --------------------------------------------------------
tmpdir="$(mktemp -d -t pi-clean-verify-XXXXXX)"
PI_CLEAN_DIR="$tmpdir" PI_CLEAN_DEBUG=1 "$SCRIPT" >/dev/null 2>&1
if [[ -d "$tmpdir" ]]; then
  ok "PI_CLEAN_DIR se conserva"
  rm -rf "$tmpdir"
else
  fail "PI_CLEAN_DIR se borró sola"
fi
# Una corrida temporal no debe dejar restos.
before="$(find /tmp -maxdepth 1 -name 'pi-clean-*' -not -name 'pi-clean-verify-*' 2>/dev/null | wc -l)"
PI_CLEAN_DEBUG=1 "$SCRIPT" >/dev/null 2>&1
after="$(find /tmp -maxdepth 1 -name 'pi-clean-*' -not -name 'pi-clean-verify-*' 2>/dev/null | wc -l)"
if [[ "$before" == "$after" ]]; then
  ok "la carpeta temporal se limpia"
else
  fail "quedaron restos en /tmp (antes $before, después $after)"
fi

if [[ "$fails" -gt 0 ]]; then
  printf '\npi clean: %d falla(s)\n' "$fails"
  exit 1
fi
[ "$QUIET" = 1 ] || printf '\npi clean: todo en orden\n'
