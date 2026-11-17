#!/usr/bin/env bash
# kitty-opacity.sh — opacidad de kitty según la fuente de energía.
#
# background_opacity 0.88 + background_blur 32 son alpha de la app: el
# compositor no puede anularlas. Desconectado (batería), toda instancia
# corriendo pasa a 1.0 y se guarda su opacidad por socket para devolverla al
# enchufar. Solo batería: el perfil power-saver ("modo silencioso") está activo
# también con AC. Las instancias nuevas nacen opacas por el
# geninclude de kitty.conf (kitty-opacity-config.sh).
#
# Uso:
#   kitty-opacity.sh auto      apply si batería, restore si no (guard)
#   kitty-opacity.sh apply     opaca todo y guarda lo previo (idempotente)
#   kitty-opacity.sh restore   devuelve lo guardado
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/kitty-opacity"
SAVE="$STATE_DIR/restore"

log() { logger -t kitty-opacity -- "$*" 2>/dev/null || true; }

on_battery() {
  local p
  for p in /sys/class/power_supply/*/online; do
    [ -f "$p" ] || continue
    case "$p" in */BAT*) continue ;; esac
    [ "$(cat "$p" 2>/dev/null)" = "1" ] && return 1
  done
  return 0
}

# Se habla por el socket de listen_on que define /etc/xdg/kitty/kitty.conf, no
# por KITTY_LISTEN_ON (puede quedar viejo en el entorno de quien invoca).
kitty_socks() {
  local socket
  for socket in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/omarchy-kitty-*; do
    [ -S "$socket" ] && printf '%s\n' "$socket"
  done
}

kitty_opacity() { # kitty_opacity <socket> [opacidad]
  command -v kitten >/dev/null 2>&1 || return 1
  if [ $# -ge 2 ]; then
    timeout 3 kitten @ --to "unix:$1" set-background-opacity --all "$2" >/dev/null 2>&1
  else
    timeout 3 kitten @ --to "unix:$1" ls 2>/dev/null |
      python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["background_opacity"] if d else "")' 2>/dev/null
  fi
}

# Idempotente: si ya hay una opacidad guardada para el socket no se pisa, así
# entrar/salir del modo extremo no pierde el valor original.
apply() {
  command -v kitten >/dev/null 2>&1 || return 0
  mkdir -p "$STATE_DIR"
  local socket opacity
  while IFS= read -r socket; do
    opacity="$(kitty_opacity "$socket")" || true
    [ -n "${opacity:-}" ] || continue
    grep -qF -- "$socket" "$SAVE" 2>/dev/null ||
      printf '%s\t%s\n' "$socket" "$opacity" >>"$SAVE"
    kitty_opacity "$socket" 1.0 ||
      log "no se pudo cambiar $socket (¿arrancada sin dynamic_background_opacity?)"
  done < <(kitty_socks)
}

restore() {
  [ -f "$SAVE" ] || return 0
  local socket opacity
  while IFS=$'\t' read -r socket opacity; do
    [ -S "${socket:-}" ] && [ -n "${opacity:-}" ] && kitty_opacity "$socket" "$opacity"
  done <"$SAVE"
  rm -f "$SAVE"
}

case "${1:-auto}" in
  auto) if on_battery; then apply; else restore; fi ;;
  apply) apply ;;
  restore) restore ;;
  *)
    echo "Uso: kitty-opacity.sh [auto|apply|restore]" >&2
    exit 1
    ;;
esac
