#!/usr/bin/env bash
set -uo pipefail

DOMAIN=tauri
TAURI_DEPS=(base-devel webkit2gtk-4.1 gtk3 librsvg patchelf xdotool openssl rustup)
APPINDICATOR_PROVIDERS=(libappindicator libappindicator-gtk3 libayatana-appindicator)

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

check_toolchain() {
  local tool version
  for tool in rustc cargo rustup; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      fail "toolchain:$tool" "no encontrado en PATH"
      continue
    fi
    version=$("$tool" --version 2>&1 | head -1)
    ok "toolchain:$tool" "$version"
  done
}

check_default_stable() {
  local active
  active=$(rustup show active-toolchain 2>&1 | head -1)
  if [[ "$active" == stable* ]]; then
    ok "default-toolchain" "$active"
  else
    fail "default-toolchain" "esperado stable, obtenido: ${active:-<vacio>}"
  fi
}

check_deps() {
  local pkg missing=()
  for pkg in "${TAURI_DEPS[@]}"; do
    pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "deps-installed" "${TAURI_DEPS[*]}"
  else
    fail "deps-installed" "faltan: ${missing[*]}"
  fi
}

check_appindicator() {
  local pkg
  for pkg in "${APPINDICATOR_PROVIDERS[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      ok "appindicator" "$pkg"
      return
    fi
  done
  fail "appindicator" "ninguno instalado: ${APPINDICATOR_PROVIDERS[*]}"
}

check_pkgconfig() {
  if pkg-config --exists webkit2gtk-4.1; then
    ok "pkgconfig:webkit2gtk-4.1" "$(pkg-config --modversion webkit2gtk-4.1 2>/dev/null)"
  else
    fail "pkgconfig:webkit2gtk-4.1" "pkg-config --exists fallo"
  fi
}

check_cargo_bin_path() {
  if grep -q 'cargo/bin' "$HOME/.bashrc" 2>/dev/null; then
    ok "cargo-bin-path" "\$HOME/.cargo/bin referenciado en \$HOME/.bashrc"
  else
    fail "cargo-bin-path" "\$HOME/.cargo/bin no referenciado en \$HOME/.bashrc"
  fi
}

check_toolchain
check_default_stable
check_deps
check_appindicator
check_pkgconfig
check_cargo_bin_path

exit "$rc"
