#!/usr/bin/env bash
# verify/notify.sh — chequeo determinista de los avisos de escritorio.
#
# Un solo camino: `linux/bin/notify` (omarchy-notification-send, con fallback a
# notify-send). Ningun script del repo debe llamar notify-send por su cuenta,
# porque se salta el glifo y el estilo del escritorio.
#
# Uso: scripts/verify/notify.sh [--quiet]
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

REPO="${HOME}/dotfiles"
BIN="$REPO/linux/bin/notify"

[ -x "$BIN" ] && ok "notify ejecutable" || fail "falta linux/bin/notify o no es ejecutable"
bash -n "$BIN" 2>/dev/null && ok "notify sintaxis" || fail "notify no parsea"

# Ningun script del repo salta el wrapper. El propio wrapper es la excepcion
# (su rama de fallback si habla notify-send directo).
offenders=$(grep -rn 'notify-send' \
    "$REPO/linux/bin" "$REPO/linux/config" "$REPO/scripts" "$REPO/linux/voice" \
    2>/dev/null \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' \
    | grep -v 'command -v notify-send' \
    | grep -v "^$BIN:" \
    | grep -v "^$REPO/scripts/verify/notify.sh:" \
    | cut -d: -f1 | sort -u)
if [ -z "$offenders" ]; then
    ok "nadie llama notify-send por fuera del wrapper"
else
    fail "usan notify-send directo: $(echo "$offenders" | tr '\n' ' ')"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ln -s "$(command -v bash)" "$tmp/bash" 2>/dev/null

# Stubs: registran su argv, una linea por argumento.
stub() {
    local dir="$tmp/$1" name="$2"
    mkdir -p "$dir"
    printf '#!/bin/bash\nprintf "%%s\\n" "$@"\n' >"$dir/$name"
    chmod +x "$dir/$name"
}
stub omarchy omarchy-notification-send
stub plain notify-send

run() { PATH="$1" "$tmp/bash" "$BIN" "${@:2}" 2>/dev/null; }

# Con omarchy: los alias de notify-send se traducen (-a -> --app-name) y el
# glifo viaja tal cual.
out=$(run "$tmp/omarchy" -a shot -g "󰹑" -u critical -t 2500 "Titulo" "Cuerpo")
want=$'--app-name\nshot\n-g\n󰹑\n-u\ncritical\n-t\n2500\nTitulo\nCuerpo'
[ "$out" = "$want" ] && ok "omarchy: flags y glifo traducidos" \
    || fail "omarchy: argv inesperado: $(echo "$out" | tr '\n' ' ')"

# Un cuerpo que empieza con guion es contenido, no un flag.
out=$(run "$tmp/omarchy" "Titulo" "-50% off")
[ "$out" = $'Titulo\n-50% off' ] && ok "omarchy: cuerpo con guion intacto" \
    || fail "omarchy: cuerpo con guion se interpreto como flag"

# Sin omarchy: cae a notify-send, sin glifo (no existe alli).
out=$(PATH="$tmp/plain" "$tmp/bash" "$BIN" --app-name dotfiles -g "󰊢" -u critical "Titulo" "Cuerpo" 2>/dev/null)
want=$'-a\ndotfiles\n-u\ncritical\nTitulo\nCuerpo'
[ "$out" = "$want" ] && ok "fallback: traduce a notify-send" \
    || fail "fallback: argv inesperado: $(echo "$out" | tr '\n' ' ')"

# Sin emisor alguno no rompe ni imprime basura.
mkdir -p "$tmp/none"
PATH="$tmp/none" "$tmp/bash" "$BIN" "Titulo" >/dev/null 2>&1
[ $? -eq 0 ] && ok "sin emisor: sale 0 sin ruido" || fail "sin emisor: salio distinto de 0"

if [ "$fails" = 0 ]; then
    [ "$QUIET" = 1 ] || echo "PASS notify"
    exit 0
fi
echo "FAIL notify ($fails)"
exit 1
