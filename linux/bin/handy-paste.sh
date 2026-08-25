#!/usr/bin/env bash
# Pegado para Handy (paste_method = external_script).
#
# Por que existe: Warp bloquea/ignora el pegado simulado por wtype
# (protocolo virtual-keyboard de Wayland). dotool inyecta a nivel uinput
# (kernel), indistinguible de un teclado fisico, y el combo llega a Warp.
#
# Contrato Handy: recibe la transcripcion como $1 y pega en la app enfocada.
set -euo pipefail

text="${1:-}"
[ -z "$text" ] && exit 0

old="$(wl-paste --no-newline 2>/dev/null || true)"
printf '%s' "$text" | wl-copy --no-newline >/dev/null 2>&1 </dev/null || true
sleep 0.15
printf 'key ctrl+shift+v\n' | dotool
sleep 0.3

# Restaurar portapapeles previo (equivalente a clipboard_handling=dont_modify)
if [ -n "$old" ]; then
  printf '%s' "$old" | wl-copy --no-newline >/dev/null 2>&1 </dev/null || true
fi
