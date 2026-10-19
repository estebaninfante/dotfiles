#!/usr/bin/env bash
# verify/cerebro.sh — cerebro de voz (Omar) sobre Hermes, y arranque de Pi.
#
# Solo lee; no cambia nada. Sale 0 si:
#   1. `voice-hermes` existe, es ejecutable y su sintaxis es válida.
#   2. El cerebro corre Hermes en una pasada (`-z`) dentro de pi-brain, con
#      toolset terminal y el guard de comandos destructivos en el PATH.
#   3. El puente de OmniVoz apunta al cerebro (voice-hermes) y compila.
#   4. `voice think` y `omar ask` usan el cerebro nuevo.
#   5. El servicio instalado coincide con el del repo.
#   6. Pi arranca en pensamiento `low` para deepseek-flash.
#   7. La copia viva del AGENTS.md del cerebro coincide con el repo.
#
# Uso:
#   scripts/verify/cerebro.sh          # texto
#   scripts/verify/cerebro.sh --quiet  # solo FALLA/aviso
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$REPO/linux/bin/voice-hermes"
VOICE="$REPO/linux/bin/voice"
OMAR="$REPO/linux/bin/omar"
SHIM="$REPO/linux/voice/pi_shim.py"
BRAIN_AGENTS="$REPO/linux/voice/pi-brain/AGENTS.md"
LIVE_BRAIN="$HOME/.local/share/voice/pi-brain"
UNIT="$REPO/linux/system/systemd-user/voice-pi-shim.service"
LIVE_UNIT="$HOME/.config/systemd/user/voice-pi-shim.service"
SETTINGS="$REPO/linux/pi/agent/settings.json"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }
aviso(){ [ "$QUIET" = 1 ] || printf '  aviso %s\n' "$*"; }

# --- 1. el script del cerebro --------------------------------------------
if [ -x "$BIN" ]; then
    ok "voice-hermes es ejecutable"
else
    fail "voice-hermes no existe o no es ejecutable ($BIN)"
fi
if bash -n "$BIN" 2>/dev/null; then
    ok "voice-hermes tiene sintaxis válida"
else
    fail "voice-hermes no compila"
fi
if grep -q 'hermes -z\|args=(-z' "$BIN" && grep -q 'guard:' "$BIN"; then
    ok "voice-hermes corre hermes -z con el guard en el PATH"
else
    fail "voice-hermes no invoca hermes -z o perdió el guard"
fi
if grep -q 'TOOLSETS=.*terminal' "$BIN"; then
    ok "voice-hermes limita el toolset a terminal"
else
    fail "voice-hermes no limita el toolset (latencia/prompt inflados)"
fi

# --- 2. el puente de OmniVoz ---------------------------------------------
if python3 -m py_compile "$SHIM" 2>/dev/null; then
    ok "pi_shim.py compila"
else
    fail "pi_shim.py no compila"
fi
if grep -q 'voice-hermes' "$SHIM" && grep -q 'VOICE_BRAIN_BIN' "$SHIM"; then
    ok "el puente usa voice-hermes (VOICE_BRAIN_BIN manda)"
else
    fail "el puente no apunta a voice-hermes"
fi

# --- 3. llamadas del cerebro ---------------------------------------------
grep -q 'voice-hermes' "$VOICE" \
    && ok "voice think usa voice-hermes" \
    || fail "voice think sigue llamando a voice-pi"
grep -q 'voice-hermes' "$OMAR" \
    && ok "omar ask usa voice-hermes" \
    || fail "omar ask sigue llamando a voice-pi"

# --- 4. servicio instalado -----------------------------------------------
if [ -f "$LIVE_UNIT" ] && diff -q "$UNIT" "$LIVE_UNIT" >/dev/null 2>&1; then
    ok "la unidad instalada coincide con el repo"
else
    fail "la unidad instalada difiere del repo (correr scripts/install-user-units.sh)"
fi
if systemctl --user is-active --quiet voice-pi-shim.service 2>/dev/null; then
    ok "voice-pi-shim.service está activo"
else
    aviso "voice-pi-shim.service no está activo (systemctl --user start voice-pi-shim)"
fi

# --- 5. arranque de Pi en low --------------------------------------------
if python3 - "$SETTINGS" <<'PY' >/dev/null 2>&1
import json, sys
s = json.load(open(sys.argv[1]))
assert s.get("defaultThinkingLevel") == "low"
assert (s.get("modelThinkingLevels") or {}).get("deepseek/deepseek-flash") == "low"
PY
then
    ok "Pi arranca en pensamiento low para deepseek-flash"
else
    fail "Pi no arranca en low (defaultThinkingLevel/modelThinkingLevels)"
fi

# --- 6. copia viva del cerebro -------------------------------------------
if diff -q "$BRAIN_AGENTS" "$LIVE_BRAIN/AGENTS.md" >/dev/null 2>&1; then
    ok "el AGENTS.md del cerebro coincide con el repo"
else
    aviso "el AGENTS.md vivo difiere del repo (copiar $BRAIN_AGENTS a $LIVE_BRAIN/)"
fi
guard_ok=1
for name in omarchy systemctl reboot poweroff shutdown; do
    [ -L "$LIVE_BRAIN/guard/$name" ] || { guard_ok=0; break; }
done
[ "$guard_ok" = 1 ] \
    && ok "el guard de comandos destructivos está completo" \
    || fail "falta un symlink del guard en $LIVE_BRAIN/guard/"

if [ "$fails" -gt 0 ]; then
    printf '\n%d falla(s)\n' "$fails"
    exit 1
fi
[ "$QUIET" = 1 ] || printf '\ntodo ok\n'
