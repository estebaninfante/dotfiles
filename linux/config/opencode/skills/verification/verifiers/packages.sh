#!/usr/bin/env bash
set -uo pipefail

DOMAIN=packages
STREMIO_DEPS=(qt5-webengine qt5-webchannel qt5-location openssl-1.1)

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }

for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
  esac
done

check_installed() {
  local pkg missing=()
  for pkg in "$@"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "deps-installed" "$*"
  else
    fail "deps-installed" "faltan: ${missing[*]}"
  fi
}

check_binary() {
  local bin=/usr/bin/stremio
  if [ ! -L "$bin" ] || [ ! -x "$bin" ]; then
    fail "binary" "symlink $bin ausente o no ejecutable"
    return
  fi
  local missing
  missing=$(ldd "$bin" 2>/dev/null | grep -i 'not found' || true)
  if [ -n "$missing" ]; then
    fail "binary" "libs faltantes: $(echo "$missing" | tr -s ' ' | cut -d' ' -f1 | tr '\n' ' ')"
    return
  fi
  ok "binary" "$bin resuelve todas sus libs"
}

check_desktop_entry() {
  if [ -r /usr/share/applications/stremio.desktop ]; then
    ok "desktop-entry" "/usr/share/applications/stremio.desktop"
  else
    fail "desktop-entry" "falta /usr/share/applications/stremio.desktop"
  fi
}

check_no_source_build() {
  local dir="$HOME/.cache/yay/qt5-webengine"
  if [ -d "$dir/src" ]; then
    fail "qt5-source-build" "hay un build de Chromium en curso en $dir/src (horas). Borrarlo y usar el .pkg.tar.zst de CachyOS"
  else
    ok "qt5-source-build" "sin build de qt5-webengine en curso"
  fi
}

check_pkg_not_from_source_repo() {
  local pkg
  for pkg in qt5-webengine qt5-webchannel qt5-location; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      ok "pkg:$pkg" "instalado"
    else
      fail "pkg:$pkg" "no instalado (instalar desde mirror CachyOS, jamas desde fuente)"
    fi
  done
}

run_checks() {
  check_installed "${STREMIO_DEPS[@]}" mpv nodejs patchelf
  check_pkg_not_from_source_repo
  check_binary
  check_desktop_entry
  check_no_source_build
}

run_checks

exit "$rc"
