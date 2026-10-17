#!/usr/bin/env bash
# verify/lan-mouse-sync.sh — chequeo determinista de la sincronización de la
# disposición de LAN-Mouse entre las dos máquinas.
#
# No toca el peer ni la config viva: usa un HOME temporal y un config de
# prueba. Sale 0 si todo está en su lugar.
#
# Uso: scripts/verify/lan-mouse-sync.sh [--quiet]
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

REPO="${HOME}/dotfiles"
BIN="$REPO/linux/bin"
UNITS="$REPO/linux/system/systemd-user"

for s in kvm-peer lan-mouse-peer-apply lan-mouse-sync; do
    [ -x "$BIN/$s" ] && ok "$s ejecutable" || fail "$s falta o no es ejecutable"
    bash -n "$BIN/$s" 2>/dev/null && ok "$s sintaxis" || fail "$s no parsea"
done

for u in lan-mouse-sync.path lan-mouse-sync.service; do
    [ -f "$UNITS/$u" ] && ok "$u en el repo" || fail "falta $u"
    grep -qx "$u" "$UNITS/enabled-all.txt" \
        && ok "$u habilitado en enabled-all.txt" \
        || fail "$u no figura en enabled-all.txt"
done

# El path unit tiene que apuntar al service.
grep -q '^Unit=lan-mouse-sync.service' "$UNITS/lan-mouse-sync.path" \
    && ok "path -> service" || fail "path no referencia lan-mouse-sync.service"

# Espejo de posiciones, con un config de prueba (no toca la config viva).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state"
cat >"$tmp/config.toml" <<'EOF'
port = 4242
[[clients]]
hostname = "192.0.2.10"
ips = ["192.0.2.10"]
position = "left"
activate_on_startup = true
EOF

get_peer="$(XDG_STATE_HOME="$tmp/state" LAN_MOUSE_CONFIG="$tmp/config.toml" \
    "$BIN/kvm-peer" 2>/dev/null || true)"
[ "$get_peer" = "192.0.2.10" ] && ok "kvm-peer resuelve el peer" \
    || fail "kvm-peer devolvió '$get_peer'"

for pair in "left:right" "right:left" "top:bottom" "bottom:top"; do
    from="${pair%%:*}"; to="${pair##*:}"
    sed -i "s/^position = \".*\"/position = \"$from\"/" "$tmp/config.toml"
    XDG_STATE_HOME="$tmp/state" LAN_MOUSE_CONFIG="$tmp/config.toml" \
        LAN_MOUSE_REPO="$tmp/repo" "$BIN/lan-mouse-sync" --dry >/dev/null 2>&1 || true
    if grep -qE ": $to$" "$tmp/state/lan-mouse-sync.log" 2>/dev/null; then
        ok "$from -> peer $to"
    else
        fail "$from no se tradujo a $to"
    fi
done

if [ "$fails" = 0 ]; then
    [ "$QUIET" = 1 ] || echo "PASS lan-mouse-sync"
    exit 0
fi
echo "FAIL lan-mouse-sync ($fails)"
exit 1
