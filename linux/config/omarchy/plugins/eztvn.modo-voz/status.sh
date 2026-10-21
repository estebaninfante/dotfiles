#!/usr/bin/env bash
# Puente del widget de barra eztvn.modo-voz.
#
# Lee el ritmo de los agentes y cuántos mensajes hay pendientes en el buzón.
# El modo real se deduce de la entrega y de `chatiness`, así el indicador no
# miente aunque alguien cambie solo una parte desde el panel de voz.
#
# Usage:
#   status.sh status                 -> {"mode":"fluido","pending":0}
#   status.sh set fluido|concentracion|campana
set -euo pipefail

VOICE_BIN="${PI_VOICE_BIN:-$HOME/.local/bin/voice}"
if [ ! -x "$VOICE_BIN" ]; then
  VOICE_BIN="$(command -v voice || echo voice)"
fi

mode_now() {
  local raw chat deliv
  raw="$("$VOICE_BIN" modo 2>/dev/null || true)"
  chat="$(printf '%s' "$raw" | sed -n 's/.*modo: *\([a-z]*\).*/\1/p')"
  deliv="$(printf '%s' "$raw" | sed -n 's/.*entrega: *\([a-z]*\).*/\1/p')"
  case "$deliv" in
    bell) echo "campana" ;;
    silent|mailbox) echo "concentracion" ;;
    *) if [ "$chat" = "concentracion" ]; then echo "concentracion"; else echo "fluido"; fi ;;
  esac
}

pending_count() {
  local p
  p="$("$VOICE_BIN" inbox count 2>/dev/null | tr -dc '0-9')" || p="0"
  echo "${p:-0}"
}

print_status() {
  printf '{"mode":"%s","pending":%s}\n' "$(mode_now)" "$(pending_count)"
}

case "${1:-status}" in
  status) print_status ;;
  set)
    case "${2:-}" in
      fluido|concentracion|campana) "$VOICE_BIN" modo "$2" >/dev/null 2>&1 ;;
      *) echo "uso: status.sh set fluido|concentracion|campana" >&2; exit 2 ;;
    esac
    print_status
    ;;
  *) echo "uso: status.sh [status|set <modo>]" >&2; exit 2 ;;
esac
