#!/usr/bin/env bash
# install-user-units.sh — aplica a esta máquina los units que dotfiles gestiona.
#
# Los units que dotfiles maneja se declaran en listas aditivas:
#   linux/system/systemd-user/enabled-all.txt       → todas las máquinas
#   linux/system/systemd-user/enabled-<máquina>.txt → según ~/.config/machine-type
# Solo esos se enlazan (symlink al repo: un cambio en dotfiles llega solo, sin
# copiar) y se habilitan. Lo que no está en las listas no se toca: así cada
# equipo conserva sus servicios propios y no se pisan configs a mano.
#
# Es idempotente. Lo llama reconcile-machine.sh en cada sync cuando cambian los
# units; también se puede correr a mano.
set -uo pipefail

REPO="${HOME}/dotfiles"
SRC="$REPO/linux/system/systemd-user"
DST="${HOME}/.config/systemd/user"
MACHINE="$(tr -d '[:space:]' < "${HOME}/.config/machine-type" 2>/dev/null || true)"
MACHINE="${MACHINE:-laptop}"

[ -d "$SRC" ] || { echo "install-user-units: falta $SRC" >&2; exit 1; }
mkdir -p "$DST"

managed_units() {
  local f
  for f in "$SRC/enabled-all.txt" "$SRC/enabled-$MACHINE.txt"; do
    [ -f "$f" ] || continue
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$f" | grep -v '^$' || true
  done
}

changed=0
for u in $(managed_units); do
  src="$SRC/$u"
  dst="$DST/$u"
  if [ ! -f "$src" ]; then
    echo "install-user-units: falta el unit $u en el repo" >&2
    continue
  fi
  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
    continue
  fi
  ln -sfn "$src" "$dst"
  changed=1
  echo "enlazado: $u"
done

[ "$changed" = 1 ] && systemctl --user daemon-reload

for u in $(managed_units); do
  systemctl --user is-enabled "$u" >/dev/null 2>&1 \
    || systemctl --user enable "$u" >/dev/null 2>&1 \
    || { echo "install-user-units: no pude habilitar $u" >&2; continue; }
  systemctl --user is-active "$u" >/dev/null 2>&1 \
    || systemctl --user start "$u" >/dev/null 2>&1 \
    || true
  echo "habilitado: $u"
done

exit 0
