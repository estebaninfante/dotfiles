#!/usr/bin/env bash
set -uo pipefail

DOMAIN=hypr3d
SRC="${HYPR3D_SRC:-$HOME/.local/share/hypr3d-src}"

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
  esac
done

if [ ! -d "$SRC" ]; then
  skip "src" "$SRC no existe"
  exit "$rc"
fi
ok "src" "$SRC"

if command -v g++ >/dev/null 2>&1 && [ -f "$SRC/tests/test_logic.cpp" ]; then
  tmp=$(mktemp -d)
  if g++ -std=c++23 -I"$SRC/src" -Wall -Wextra -Werror \
      -o "$tmp/test_logic" "$SRC/tests/test_logic.cpp" \
      >/tmp/hypr3d-verify-gpp.log 2>&1; then
    if "$tmp/test_logic" >/dev/null 2>&1; then
      ok "logic-tests" "AimFocus dwell + MovementKeys mapping"
    else
      fail "logic-tests" "asserts fallaron"
    fi
  else
    fail "logic-tests" "$(head -n1 /tmp/hypr3d-verify-gpp.log)"
  fi
  rm -rf "$tmp"
else
  skip "logic-tests" "g++ o tests ausentes"
fi

if [ -f "$SRC/src/main.cpp" ]; then
  aim_body=$(awk '/^static void updateAimFocus\(float dt\)/,/^}/' "$SRC/src/main.cpp")
  if printf '%s\n' "$aim_body" | grep -q 'superHeld()' && ! printf '%s\n' "$aim_body" | grep -q 'g_superHeld'; then
    ok "super-gate" "auto-gesto exige Super fisico (getModifiers), no el cache"
  else
    fail "super-gate" "updateAimFocus debe consultar superHeld() y no g_superHeld"
  fi
fi

if [ -f "$SRC/src/HyprlandCompat/WindowsCompat.cpp" ]; then
  restore_body=$(awk '/^void restoreWindowLayout/,/^}/' "$SRC/src/HyprlandCompat/WindowsCompat.cpp")
  detach=$(printf '%s\n' "$restore_body" | grep -c 'assignToSpace(nullptr)')
  attach=$(printf '%s\n' "$restore_body" | grep -c 'assignToSpace(save.space)')
  if [ "$detach" -ge 1 ] && [ "$attach" -ge 1 ] &&
     [ "$(printf '%s\n' "$restore_body" | grep -n 'assignToSpace' | head -n1 | cut -d: -f1)" = \
       "$(printf '%s\n' "$restore_body" | grep -n 'assignToSpace(nullptr)' | head -n1 | cut -d: -f1)" ]; then
    ok "ghost-restore" "restore detacha (add branch) antes de reasignar el space"
  else
    fail "ghost-restore" "restoreWindowLayout debe llamar assignToSpace(nullptr) antes de assignToSpace(save.space)"
  fi
fi

if [ -f "$SRC/CMakeLists.txt" ] && [ -d /usr/include/hyprland ]; then
  if cmake --build "$SRC/build" -j"$(nproc)" \
      >/tmp/hypr3d-verify-cmake.log 2>&1; then
    ok "plugin-build" "$(basename "$SRC/build/hypr3d.so")"
  else
    fail "plugin-build" "$(tail -n1 /tmp/hypr3d-verify-cmake.log)"
  fi
else
  skip "plugin-build" "headers de Hyprland ausentes"
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
  if hyprctl plugins list 2>/dev/null | grep -qi hypr3d; then
    if [ -f "$SRC/build/hypr3d.so" ]; then
      ok "live-vs-built" "so en disco se aplica al reiniciar Hyprland"
    else
      fail "live-vs-built" "so ausente"
    fi
  else
    skip "live-vs-built" "hypr3d no cargado"
  fi
else
  skip "live-vs-built" "hyprctl no disponible"
fi

exit "$rc"
