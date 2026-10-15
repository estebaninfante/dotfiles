#!/usr/bin/env bash
set -euo pipefail

target=eztvn.boot-console
min_ms=1200
max_ms=6000
default_ms=2600
margin_s=0.25

usage() {
  printf 'uso: %s [durationMs] [--no-wait] [--selftest]\n' "${0##*/}"
  printf '  Reproduce el overlay de handoff a Windows en la shell de Omarchy.\n'
  printf '  Sin flags dispara %s ms y bloquea ese tiempo mas margen, para que la\n' "$default_ms"
  printf '  animacion termine antes del reboot. --no-wait retorna al dispararla.\n'
}

valid_duration() {
  local value=$1
  [[ $value =~ ^[0-9]+$ ]] || return 1
  (( value >= min_ms && value <= max_ms ))
}

selftest() {
  local failures=0 value
  for value in 1200 2600 6000; do
    if ! valid_duration "$value"; then
      printf 'selftest FAIL: esperaba valido %s\n' "$value" >&2
      failures=1
    fi
  done
  for value in 1199 6001 abc -100 ''; do
    if valid_duration "$value"; then
      printf 'selftest FAIL: esperaba invalido %s\n' "'$value'" >&2
      failures=1
    fi
  done
  (( failures == 0 )) || return 1
  printf 'selftest OK\n'
}

duration_ms=$default_ms
wait_for=1

for arg in "$@"; do
  case "$arg" in
    --no-wait) wait_for=0 ;;
    --selftest) selftest; exit $? ;;
    -h|--help) usage; exit 0 ;;
    *) duration_ms=$arg ;;
  esac
done

if ! valid_duration "$duration_ms"; then
  printf 'durationMs invalido: %s (rango %s-%s)\n' "$duration_ms" "$min_ms" "$max_ms" >&2
  exit 2
fi

if omarchy-shell "$target" play "$duration_ms" >/dev/null; then
  if (( wait_for )); then
    sleep "$(awk -v ms="$duration_ms" -v margin="$margin_s" 'BEGIN { printf "%.2f", ms / 1000 + margin }')"
  fi
else
  printf 'omarchy-shell no respondio; se continua sin overlay\n' >&2
fi
