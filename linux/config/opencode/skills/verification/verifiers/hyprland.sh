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
      printf 'OK\tprobe\thyprland\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

if ! command -v hyprctl >/dev/null 2>&1; then
  skip "hyprctl" "no instalado"
  exit "$rc"
fi

if ! hyprctl version >/dev/null 2>&1; then
  fail "hyprctl" "no responde (compositor apagado?)"
  exit "$rc"
fi
ok "hyprctl" "$(hyprctl version | head -n1)"

if [ "${VERIFY_ACTIVATE:-0}" = "1" ]; then
  if hyprctl reload >/dev/null 2>&1; then
    ok "reload" "hyprctl reload"
  else
    fail "reload" "hyprctl reload fallo"
  fi
fi

errors=$(hyprctl configerrors 2>/dev/null)
if [ -z "$errors" ]; then
  ok "configerrors" "sin errores"
else
  fail "configerrors" "$(printf '%s' "$errors" | head -n3 | tr '\n' ' ')"
fi

config_dir="${HYPR_CONFIG_DIR:-$HOME/.config/hypr}"
if [ -d "$config_dir" ]; then
  missing=""
  while IFS= read -r name; do
    [ -e "$HOME/.local/bin/$name" ] || missing="$missing $name"
  done < <(grep -rhoE '\.local/bin/[A-Za-z0-9_.-]*[A-Za-z0-9]' "$config_dir" --include='*.lua' --include='*.conf' 2>/dev/null | sed 's#^.*\.local/bin/##' | sort -u)
  if [ -z "$missing" ]; then
    ok "local-refs" "refs a ~/.local/bin existen"
  else
    fail "local-refs" "faltan:$missing"
  fi

  if grep -rqE 'hyprctl +dispatch' "$config_dir" --include='*.lua' --include='*.conf' 2>/dev/null; then
    fail "lua-dispatch" "$(grep -rnE 'hyprctl +dispatch' "$config_dir" --include='*.lua' --include='*.conf' 2>/dev/null | head -n1)"
  else
    ok "lua-dispatch" "sin hyprctl dispatch (Lua mode)"
  fi

  if command -v luac >/dev/null 2>&1; then
    lua_files=()
    while IFS= read -r lua; do lua_files+=("$lua"); done < <(find -L "$config_dir" -type f -name '*.lua' 2>/dev/null | sort)
    module_bad=""
    for lua in "${lua_files[@]}"; do
      luac -p "$lua" >/dev/null 2>&1 || module_bad="$module_bad $(basename "$lua")"
    done
    if [ -z "$module_bad" ]; then
      ok "lua-modules" "${#lua_files[@]} modulos sintaxis ok"
    else
      fail "lua-modules" "sintaxis:$module_bad"
    fi

    unresolved=""
    while IFS= read -r module; do
      case "$module" in
        default.*|omarchy.*|hypr.*) continue ;;
      esac
      rel="${module//./\/}"
      if [ ! -f "$config_dir/$rel.lua" ] && [ ! -f "$config_dir/$rel/init.lua" ]; then
        unresolved="$unresolved $module"
      fi
    done < <(grep -rhoE 'require\("([^"]+)"\)' "$config_dir" --include='*.lua' 2>/dev/null | sed -E 's/require\("([^"]+)"\)/\1/' | sort -u)
    if [ -z "$unresolved" ]; then
      ok "require-resolve" "todos los require resuelven"
    else
      fail "require-resolve" "sin archivo:$unresolved"
    fi
  else
    skip "lua-modules" "luac ausente"
    skip "require-resolve" "luac ausente"
  fi
fi

for target in "${targets[@]}"; do
  case "$target" in
    *.lua)
      if command -v luac >/dev/null 2>&1; then
        if luac -p "$target" >/dev/null 2>&1; then
          ok "lua:$(basename "$target")" "sintaxis ok"
        else
          fail "lua:$(basename "$target")" "$(luac -p "$target" 2>&1 | head -n1)"
        fi
      else
        skip "lua:$(basename "$target")" "luac ausente"
      fi
      ;;
  esac
done

exit "$rc"
