#!/usr/bin/env bash
set -uo pipefail

DOMAIN=bridge

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

TG_SRC="$HOME/dotfiles/linux/bin/rig-telegram-bot"
TG_LINK="$HOME/.local/bin/rig-telegram-bot"
TG_UNIT_SRC="$HOME/dotfiles/linux/system/systemd-user/rig-telegram-bot.service"
TG_UNIT_LIVE="$HOME/.config/systemd/user/rig-telegram-bot.service"
TG_ENV="$HOME/.config/rig/telegram.env"
DC_SRC="$HOME/dotfiles/linux/bin/rig-discord-bot"
DC_LINK="$HOME/.local/bin/rig-discord-bot"
DC_UNIT_SRC="$HOME/dotfiles/linux/system/systemd-user/rig-discord-bot.service"
DC_UNIT_LIVE="$HOME/.config/systemd/user/rig-discord-bot.service"
DC_ENV="$HOME/.config/rig/discord.env"
DOC="$HOME/dotfiles/docs/main-bridge.md"

for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
    *rig-discord-bot.service) DC_UNIT_SRC="$arg" ;;
    */rig-discord-bot) DC_SRC="$arg" ;;
    *rig-telegram-bot.service) TG_UNIT_SRC="$arg" ;;
    */rig-telegram-bot) TG_SRC="$arg" ;;
    *main-bridge.md) DOC="$arg" ;;
  esac
done

scan_token() {
  local src="$1"
  if [[ -f "$src" ]] && grep -Eqn '[0-9]{7,}:[A-Za-z0-9_-]{30,}|[A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,}' "$src"; then
    return 0
  fi
  return 1
}

check_bot() {
  local name="$1" src="$2" link="$3" unit_src="$4" unit_live="$5" env_file="$6"

  if [[ -f "$src" ]]; then
    if python3 -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' "$src" "${TMPDIR:-/tmp}/rig-bridge-$name.pyc" 2>"${TMPDIR:-/tmp}/rig-bridge-$name.err"; then
      ok "$name:py_compile" "sintaxis valida"
    else
      fail "$name:py_compile" "$(head -c 300 "${TMPDIR:-/tmp}/rig-bridge-$name.err")"
    fi
    if out="$(python3 "$src" --selftest 2>&1)"; then
      ok "$name:selftest" "ida y vuelta simulada OK"
    else
      fail "$name:selftest" "$(printf '%s' "$out" | tail -c 300)"
    fi
    if scan_token "$src"; then
      fail "$name:token-leak" "posible token incrustado en el script"
    else
      ok "$name:token-leak" "sin token incrustado"
    fi
  else
    skip "$name:src" "falta $src"
  fi

  if [[ -f "$unit_src" ]]; then
    out="$(systemd-analyze verify "$unit_src" 2>&1 || true)"
    if printf '%s' "$out" | grep -Eqi 'Unknown key|Invalid|Failed to parse|not loaded'; then
      fail "$name:unit-syntax" "$(printf '%s' "$out" | head -c 300)"
    elif printf '%s' "$out" | grep -q 'not executable'; then
      skip "$name:unit-syntax" "unit valido; ExecStart aun no enlazado en ~/.local/bin"
    else
      ok "$name:unit-syntax" "systemd-analyze verify sin errores"
    fi
  else
    skip "$name:unit-syntax" "falta $unit_src"
  fi

  if [[ -L "$link" ]]; then
    ok "$name:symlink" "$link -> $(readlink "$link")"
  elif [[ -e "$link" ]]; then
    fail "$name:symlink" "$link existe y no es symlink"
  else
    skip "$name:symlink" "aun no instalado (correr link-dotfiles.sh)"
  fi

  if [[ -e "$unit_live" ]]; then
    if systemctl --user is-active --quiet "$(basename "$unit_live")"; then
      ok "$name:unit-active" "$(basename "$unit_live") activo"
    else
      skip "$name:unit-active" "unit presente, inactivo (falta token en $env_file)"
    fi
  else
    skip "$name:unit-active" "unit no instalado en ~/.config/systemd/user"
  fi
}

check_bot discord "$DC_SRC" "$DC_LINK" "$DC_UNIT_SRC" "$DC_UNIT_LIVE" "$DC_ENV"
check_bot telegram "$TG_SRC" "$TG_LINK" "$TG_UNIT_SRC" "$TG_UNIT_LIVE" "$TG_ENV"

if [[ -f "$DOC" ]] && grep -q 'rig-discord-bot' "$DOC" && grep -q 'rig-telegram-bot' "$DOC"; then
  ok "docs" "main-bridge.md documenta ambos puentes"
else
  skip "docs" "falta $DOC o no documenta ambos puentes"
fi

exit "$rc"
