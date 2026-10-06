#!/usr/bin/env bash
set -uo pipefail

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

targets=()
for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\tquickshell\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

if [ "${VERIFY_ACTIVATE:-0}" = "1" ]; then
  if omarchy restart shell >/dev/null 2>&1; then
    sleep 3
    ok "activar" "omarchy restart shell"
  else
    fail "activar" "omarchy restart shell fallo"
  fi
fi

shell_pattern='quickshell -n -p /usr/share/omarchy/shell'
if pgrep -f "$shell_pattern" >/dev/null 2>&1; then
  ok "shell-proceso" "pid $(pgrep -f "$shell_pattern" | head -n1)"
else
  fail "shell-proceso" "quickshell no esta corriendo"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  if omarchy-shell -q shell ping >/dev/null 2>&1; then
    ok "shell-ipc" "ping responde"
  else
    fail "shell-ipc" "ping sin respuesta"
  fi
else
  skip "shell-ipc" "omarchy-shell ausente"
fi

watchdog_unit=omarchy-shell.service
user_bus="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
session_active=0
launcher_pids=""
shell_pids=""

if [ ! -S "$user_bus" ]; then
  skip "watchdog" "sin bus de usuario"
elif ! command -v systemctl >/dev/null 2>&1; then
  skip "watchdog" "systemctl ausente"
else
  if systemctl --user is-active graphical-session.target >/dev/null 2>&1; then
    session_active=1
  fi

  if ! systemctl --user cat "$watchdog_unit" >/dev/null 2>&1; then
    fail "watchdog-unit" "$watchdog_unit ausente"
  else
    unit_enabled=$(systemctl --user is-enabled "$watchdog_unit" 2>/dev/null || true)
    if [ "$unit_enabled" = "enabled" ]; then
      ok "watchdog-unit-enabled" "enabled"
    else
      fail "watchdog-unit-enabled" "estado=$unit_enabled"
    fi

    if [ "$session_active" -eq 1 ]; then
      unit_state=$(systemctl --user is-active "$watchdog_unit" 2>/dev/null || true)
      case "$unit_state" in
        active|activating) ok "watchdog-unit-active" "$unit_state" ;;
        *) fail "watchdog-unit-active" "estado=$unit_state" ;;
      esac
    else
      skip "watchdog-unit-active" "sin sesion grafica"
    fi
  fi

  if [ "$session_active" -eq 1 ]; then
    shell_pids=$(pgrep -f "$shell_pattern" 2>/dev/null || true)
    shell_count=$(printf '%s\n' "$shell_pids" | grep -c . || true)
    if [ "$shell_count" -gt 1 ]; then
      fail "shell-unico" "$shell_count instancias de quickshell"
    else
      ok "shell-unico" "$shell_count instancia"
    fi

    launcher_pids=$(pgrep -f '^/bin/bash /usr/bin/omarchy-launch-shell' 2>/dev/null || true)
    launcher_count=$(printf '%s\n' "$launcher_pids" | grep -c . || true)
    if [ "$launcher_count" -gt 1 ]; then
      fail "launcher-unico" "$launcher_count launchers (posible doble proceso)"
    else
      ok "launcher-unico" "$launcher_count launcher"
    fi

    unsupervised=""
    for pid in $shell_pids; do
      grep -q "$watchdog_unit" "/proc/$pid/cgroup" 2>/dev/null || unsupervised="$unsupervised $pid"
    done
    if [ -n "$unsupervised" ]; then
      fail "shell-supervised" "quickshell fuera de la unidad:$unsupervised"
    elif [ -n "$shell_pids" ]; then
      ok "shell-supervised" "bajo $watchdog_unit"
    else
      skip "shell-supervised" "sin procesos de la shell"
    fi
  fi
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*)
    if [ -L "$HOME/.local/bin/omarchy-launch-shell" ] && [ -x "$HOME/.local/bin/omarchy-launch-shell" ]; then
      ok "launcher-shim" "shim resuelve en PATH"
    else
      fail "launcher-shim" "~/.local/bin/omarchy-launch-shell ausente"
    fi
    ;;
  *)
    skip "launcher-shim" "~/.local/bin fuera de PATH"
    ;;
esac

sync_script="$HOME/dotfiles/scripts/omarchy-sync.sh"
if [ -x "$sync_script" ]; then
  drift_out=$(bash "$sync_script" status 2>&1)
  if [ $? -eq 0 ]; then
    ok "omarchy-drift" "live == repo"
  else
    fail "omarchy-drift" "$(printf '%s' "$drift_out" | grep '^DRIFT' | head -n3 | tr '\n' ' ')"
  fi
else
  skip "omarchy-drift" "omarchy-sync.sh ausente"
fi

qml=()
for target in "${targets[@]}"; do
  case "$target" in
    *.qml)
      qml+=("$target")
      ;;
    *.json)
      if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$target" 2>/dev/null; then
        ok "json:$(basename "$target")" "valido"
      else
        fail "json:$(basename "$target")" "JSON invalido"
      fi
      ;;
  esac
done

if [ "${#qml[@]}" -gt 0 ]; then
  if command -v omarchy-qml-lint >/dev/null 2>&1; then
    lint_out=$(omarchy-qml-lint --quiet "${qml[@]}" 2>&1)
    lint_rc=$?
    if [ "$lint_rc" -eq 0 ]; then
      if [ -z "$lint_out" ]; then
        ok "qml-lint" "${#qml[@]} archivo/s limpios"
      else
        ok "qml-lint" "$(printf '%s' "$lint_out" | head -n1)"
      fi
    else
      fail "qml-lint" "$(printf '%s' "$lint_out" | head -n3 | tr '\n' ' ')"
    fi
  else
    skip "qml-lint" "omarchy-qml-lint ausente"
  fi
fi

exit "$rc"
