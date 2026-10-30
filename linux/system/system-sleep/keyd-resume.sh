#!/usr/bin/env bash
set -uo pipefail

KEYD_UNIT="${KEYD_UNIT:-keyd.service}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
HYPRCTL="${HYPRCTL:-hyprctl}"
SETPRIV="${SETPRIV:-setpriv}"
HEAL_HYPR="${HEAL_HYPR:-1}"

restart_keyd() {
  if ! "$SYSTEMCTL" cat "$KEYD_UNIT" >/dev/null 2>&1; then
    return 0
  fi
  "$SYSTEMCTL" restart "$KEYD_UNIT"
}

# Si se suspende con la grilla de hyprexpo abierta, el submap "hyprexpo" queda
# pegado al volver: el overview no sobrevive al ciclo del compositor, pero el
# submap sí, y con él se apagan TODOS los atajos del escritorio (workspaces,
# mover/redimensionar ventanas, los gestos con Súper). Se cierra lo que haya
# quedado abierto y, cuando termina su animación, se vuelve al submap base.
# El reset va después del cierre a propósito: el plugin restaura el submap que
# capturó al abrir, y si ese valor quedó contaminado el nuestro debe ganar.
heal_hypr_submap() {
  local rt inst sig uid gid rc=0
  command -v "$HYPRCTL" >/dev/null 2>&1 || return 0
  command -v "$SETPRIV" >/dev/null 2>&1 || return 0
  for rt in /run/user/[0-9]*; do
    [ -d "$rt/hypr" ] || continue
    uid="${rt##*/}"
    gid="$(id -g "$uid" 2>/dev/null)" || continue
    for inst in "$rt"/hypr/*/; do
      [ -S "${inst%/}/.socket.sock" ] || continue
      sig="$(basename "$inst")"
      timeout 5 "$SETPRIV" --reuid="$uid" --regid="$gid" --init-groups \
        env XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
        "$HYPRCTL" eval 'if hl.plugin ~= nil and hl.plugin.hyprexpo ~= nil then hl.plugin.hyprexpo.expo("cancel") end' \
        >/dev/null 2>&1 || rc=1
      sleep 1
      timeout 5 "$SETPRIV" --reuid="$uid" --regid="$gid" --init-groups \
        env XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
        "$HYPRCTL" dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || rc=1
    done
  done
  return "$rc"
}

selftest() {
  local out rc=0
  out="$(SYSTEMCTL=echo KEYD_UNIT=keyd.service HEAL_HYPR=0 "$0" post)"
  printf '%s\n' "$out" | grep -qx 'restart keyd.service' || rc=1
  out="$(SYSTEMCTL=echo KEYD_UNIT=keyd.service HEAL_HYPR=0 "$0" pre)"
  [ -z "$out" ] || rc=1
  [ "$rc" -eq 0 ] && printf 'selftest ok\n'
  return "$rc"
}

case "${1:-}" in
  post)
    restart_keyd
    [ "$HEAL_HYPR" = 1 ] && heal_hypr_submap
    ;;
  --selftest) selftest ;;
esac
