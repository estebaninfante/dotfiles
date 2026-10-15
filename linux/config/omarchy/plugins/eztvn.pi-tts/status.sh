#!/usr/bin/env bash
# Puente del widget de barra eztvn.pi-tts.
#
# Interruptor maestro de la voz TTS del SISTEMA de voz (`voice`): togglea
# `tts.enabled` (state.json pisa config.toml), el mismo que respetan los
# agentes (Pi, opencode) al hablar. Un solo switch para toda la voz.
#
# Ademas expone el volumen relativo (`voice volume`) y el historial de la voz
# (`voice history`), para que el panel pueda ajustar el volumen y repasar lo
# que el agente dijo, sin salir de la barra.
#
# Usage:
#   status.sh status              -> JSON: estado + volumen
#   status.sh enable | disable    -> fija el estado
#   status.sh toggle              -> alterna el estado
#   status.sh volume-set <v>      -> volumen relativo (0.0-1.0 o NN%)
#   status.sh history [N]         -> JSON array del historial (reciente primero)
#   status.sh play <ruta.wav>     -> reproduce un WAV del historial
set -euo pipefail

VOICE_BIN="${PI_TTS_VOICE_BIN:-$HOME/.local/bin/voice}"
if [ ! -x "$VOICE_BIN" ]; then
  VOICE_BIN="$(command -v voice || echo voice)"
fi

state() {
  local out
  out="$("$VOICE_BIN" tts 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
  case "$out" in
    *false*) echo "disabled" ;;
    *) echo "enabled" ;;
  esac
}

# `voice volume` imprime "volumen TTS: 60%" (o 0.6). Normaliza a fraccion para
# que el slider del panel tenga una sola escala.
volume_fraction() {
  local raw
  raw="$("$VOICE_BIN" volume 2>/dev/null | sed 's/.*: *//')" || raw=""
  raw="${raw:-1.0}"
  if [[ "$raw" == *% ]]; then
    awk "BEGIN{printf \"%.3f\", ${raw%\%}/100}"
  else
    awk "BEGIN{printf \"%.3f\", $raw}"
  fi
}

print_status() {
  local s v
  s="$(state)"
  v="$(volume_fraction)"
  printf '{"state":"%s","enabled":%s,"volume":%s,"source":"voice tts"}\n' \
    "$s" "$([[ "$s" == enabled ]] && echo true || echo false)" "$v"
}

case "${1:-status}" in
  status)  print_status ;;
  enable)  "$VOICE_BIN" tts on >/dev/null 2>&1 ;;
  disable) "$VOICE_BIN" tts off >/dev/null 2>&1 ;;
  toggle)  "$VOICE_BIN" tts toggle >/dev/null 2>&1 ;;
  volume-set)
    [ "$#" -ge 2 ] || { echo "uso: status.sh volume-set <0.0-1.0|NN%>" >&2; exit 2; }
    v="$2"
    if [[ "$v" != *% ]] && awk "BEGIN{exit !($v>1)}"; then v="${v}%"; fi
    "$VOICE_BIN" volume "$v" >/dev/null 2>&1 ;;
  history)
    "$VOICE_BIN" history --json "${2:-200}" ;;
  play)
    [ "$#" -ge 2 ] || { echo "uso: status.sh play <ruta.wav>" >&2; exit 2; }
    "$VOICE_BIN" play "$2" >/dev/null 2>&1 ;;
  *) echo "uso: status.sh [status|enable|disable|toggle|volume-set|history|play]" >&2; exit 2 ;;
esac
