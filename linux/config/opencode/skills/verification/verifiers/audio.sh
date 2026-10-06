#!/usr/bin/env bash
set -uo pipefail

DOMAIN=audio
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/pw-duck/config.toml"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/pw-duck.service"

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

targets=()
for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

check_toml() {
  local file="$1" err
  if [ ! -r "$file" ]; then
    fail "config:$file" "no legible"
    return
  fi
  err=$(python3 - "$file" <<'PY'
import sys, tomllib
try:
    with open(sys.argv[1], "rb") as fh:
        data = tomllib.load(fh)
except Exception as exc:
    print(exc)
    sys.exit(1)
vs = data.get("voice_source")
if not isinstance(vs, dict):
    print("falta [voice_source]")
    sys.exit(1)
missing = [k for k in ("application_name", "media_class") if not vs.get(k)]
if missing:
    print("campos vacios: " + ",".join(missing))
    sys.exit(1)
PY
  ) || {
    fail "config:$file" "${err:-TOML invalido}"
    return
  }
  ok "config:$file" "voice_source ok"
}

if [ "${#targets[@]}" -gt 0 ]; then
  matched=0
  for t in "${targets[@]}"; do
    case "$t" in
      *.toml)
        matched=1
        check_toml "$t"
        ;;
    esac
  done
  if [ "$matched" -eq 0 ]; then
    skip "targets" "sin .toml que validar"
  fi
else
  if command -v pw-duck >/dev/null 2>&1; then
    ok "bin:pw-duck" "$(command -v pw-duck)"
  else
    fail "bin:pw-duck" "no instalado"
  fi

  if [ -r "$CONFIG" ]; then
    check_toml "$CONFIG"
  else
    fail "config:$CONFIG" "no existe"
  fi

  if [ -f "$UNIT" ]; then
    if systemd-analyze --user verify "$UNIT" >/dev/null 2>&1; then
      ok "unit:pw-duck.service" "valido"
    else
      fail "unit:pw-duck.service" "systemd-analyze verify fallo"
    fi
    enabled=$(systemctl --user is-enabled pw-duck.service 2>/dev/null || true)
    active=$(systemctl --user is-active pw-duck.service 2>/dev/null || true)
    if [ "$enabled" = "enabled" ]; then
      ok "enabled:pw-duck.service" "$enabled"
      if [ "$active" = "active" ]; then
        ok "active:pw-duck.service" "$active"
        if command -v pactl >/dev/null 2>&1 && pactl list short sinks 2>/dev/null | grep -q 'pw-duck-'; then
          ok "routing:sink" "sink virtual activo"
        else
          skip "routing:sink" "servicio activo, sin app de llamada visible"
        fi
      else
        fail "active:pw-duck.service" "${active:-inactivo}"
      fi
    else
      skip "enabled:pw-duck.service" "${enabled:-desconocido}"
    fi
  else
    skip "unit:pw-duck.service" "no instalado"
  fi
fi

exit "$rc"
