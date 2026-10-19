#!/usr/bin/env bash
# verify/crash.sh — autodiagnóstico de crashes como ticket del rig.
#
# Comprueba, sin criterio humano, que:
#   1. el watcher de Omarchy se reemplaza por drop-in (no se edita /usr/share);
#   2. el watcher escucha coredump, filtra y lanza el diagnóstico desprendido;
#   3. el diagnóstico abre un ticket del rig, usa SOLO modelos free y lo cierra;
#   4. install-user-units.sh enlaza los drop-ins versionados.
#
# Uso:
#   scripts/verify/crash.sh          # texto
#   scripts/verify/crash.sh --quiet  # solo FALLA/aviso
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WATCH="$REPO/linux/bin/omarchy-crash-autodiagnose"
DIAG="$REPO/linux/bin/omarchy-crash-diagnose"
DROPIN="$REPO/linux/system/systemd-user/omarchy-crash-watch.service.d/override.conf"
INSTALL="$REPO/scripts/install-user-units.sh"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- 1. scripts presentes y sintácticamente sanos ---------------------------
for f in "$WATCH" "$DIAG"; do
  if [ ! -f "$f" ]; then
    fail "falta $(basename "$f")"
    continue
  fi
  if bash -n "$f" 2>/dev/null; then
    ok "sintaxis: $(basename "$f")"
  else
    fail "sintaxis rota: $(basename "$f")"
  fi
  [ -x "$f" ] && ok "ejecutable: $(basename "$f")" || fail "no ejecutable: $(basename "$f")"
done

# --- 2. drop-in que reemplaza el watcher de Omarchy -------------------------
if [ -f "$DROPIN" ]; then
  ok "existe el drop-in del watcher"
  grep -q '^ExecStart=$' "$DROPIN" \
    && ok "drop-in limpia el ExecStart original" \
    || fail "drop-in no limpia el ExecStart (no reemplaza nada)"
  grep -q '^ExecStart=%h/.local/bin/omarchy-crash-autodiagnose$' "$DROPIN" \
    && ok "drop-in apunta al autodiagnóstico" \
    || fail "drop-in no apunta a omarchy-crash-autodiagnose"
else
  fail "falta el drop-in $DROPIN"
fi

# --- 3. el watcher: señal, filtros y lanzamiento desprendido ----------------
if [ -f "$WATCH" ]; then
  for marca in 'fc2e22bc6ee647b6b90729ab34a250b1' 'COREDUMP_PID' \
               'dedupe_seconds' 'ignore_pattern' 'UID' 'systemd-run' 'setsid' \
               'omarchy-crash-diagnose' 'omarchy-crash-'; do
    grep -q "$marca" "$WATCH" \
      && ok "watcher: $marca" \
      || fail "watcher sin $marca"
  done
fi

# --- 4. el diagnóstico: ticket del rig, evidencia y cierre ------------------
if [ -f "$DIAG" ]; then
  for marca in 'rig ticket add' '--project' '--area' 'rig ticket set' \
               '--status done' '--status blocked' 'diagnose-crash' 'opencode run'; do
    grep -q -- "$marca" "$DIAG" \
      && ok "diagnóstico: $marca" \
      || fail "diagnóstico sin $marca"
  done
fi

# --- 5. SOLO modelos free ---------------------------------------------------
if [ -f "$DIAG" ]; then
  paid=0; n=0
  # Solo el bloque de modelos declarados; un comentario no debe contar.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    n=$((n + 1))
    case "$m" in
      *-free) ;;
      *) paid=$((paid + 1)); fail "modelo no free en el diagnóstico: $m" ;;
    esac
  done < <(sed -n '/free_models=(/,/)/p' "$DIAG" | grep -oE '(opencode|opencode-go)/[a-z0-9.-]+' | sort -u)
  [ "$paid" -eq 0 ] && [ "$n" -gt 0 ] \
    && ok "diagnóstico: $n modelo(s) free, ninguno pago" \
    || { [ "$n" -eq 0 ] && fail "el diagnóstico no declara ningún modelo free"; }
fi

# --- 6. el instalador enlaza drop-ins ---------------------------------------
if grep -q '"\$SRC"/\*\.d' "$INSTALL" && grep -q 'ln -sfn' "$INSTALL"; then
  ok "install-user-units: enlaza drop-ins *.d"
else
  fail "install-user-units no enlaza drop-ins"
fi

if [ "$fails" -eq 0 ]; then
  [ "$QUIET" = 1 ] || echo "PASS crash"
  exit 0
fi
echo "FAIL crash ($fails)"
exit 1
