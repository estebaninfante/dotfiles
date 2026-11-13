#!/usr/bin/env bash
# verify/web-search-rustxng.sh — el tool web_search del harness busca con RustXNG.
#
# El plugin `linux/dsh/plugins/web-search-rustxng` registra el provider `rustxng`
# en `ctx.web`: si el servicio no está corriendo lo levanta, consulta su API JSON
# y lo deja apagarse solo por inactividad. Corre sin servidor: carga el plugin y
# hace dos búsquedas reales a través del provider.
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "FALLA falta node en PATH"
    exit 1
fi

out="$(node "$HERE/web-search-rustxng.mjs" 2>&1)"
if [ "$?" -ne 0 ]; then
    printf '%s\n' "$out"
    echo "FALLA la búsqueda no sale por RustXNG"
    exit 1
fi

[ "$QUIET" = 1 ] || printf '  ok    %s\n' "$out"
[ "$QUIET" = 1 ] || printf '\nweb-search-rustxng: OK\n'
exit 0
