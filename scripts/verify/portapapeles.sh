#!/usr/bin/env bash
# verify/portapapeles.sh — el portapapeles viaja entero entre las dos máquinas.
#
# Prueba `clipboard-sync` contra la sesión Wayland viva, pero con el "otro
# equipo" simulado en loopback (CLIPBOARD_SYNC_LOCAL_PEER=1): el receptor corre
# en la misma máquina, así se ejercita el protocolo completo (digest, ecos,
# framing de archivos, uri-list) sin necesitar la otra máquina ni SSH.
#
# OJO: usa el portapapeles real (lo pisa). No toca la config ni el estado vivo
# del demonio: todo el estado va a un directorio temporal.
#
# Sale 0 si:
#   - texto e imagen llegan y quedan idénticos (byte por byte);
#   - el eco que vuelve se ignora (no hay ping-pong);
#   - los archivos viajan íntegros, con espacios en el nombre, y la uri-list se
#     reescribe al destino;
#   - receive rechaza un mime o un digest inválidos;
#   - con el otro equipo caído el envío falla rápido, avisa y no queda "visto";
#   - `send` comparte una ruta y el demonio empuja solo al copiar.
#
# Uso:
#   scripts/verify/portapapeles.sh          # texto
#   scripts/verify/portapapeles.sh --quiet  # solo FALLA

set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CS="$REPO/linux/bin/clipboard-sync"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

[ -x "$CS" ] || { echo "no encuentro $CS" >&2; exit 1; }
bash -n "$CS" || { echo "sintaxis rota en clipboard-sync" >&2; exit 1; }

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if ! command -v wl-paste >/dev/null || ! command -v wl-copy >/dev/null; then
  echo "falta wl-clipboard"; exit 1
fi
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    [ -S "$s" ] && { export WAYLAND_DISPLAY="${s##*/}"; break; }
  done
fi
[ -n "${WAYLAND_DISPLAY:-}" ] || { echo "sin sesión Wayland"; exit 1; }

T="$(mktemp -d)"
export CLIPBOARD_SYNC_STATE="$T/state"
export CLIPBOARD_SYNC_LOG="$T/log"
export INCOMING_DIR="$T/incoming"
export CLIPBOARD_SYNC_CONFIG="$T/no-config"
mkdir -p "$T/fuente" "$CLIPBOARD_SYNC_STATE"
trap 'rm -rf "$T"' EXIT

# Todo el arnés corre con el "otro equipo" en loopback (incluido el demonio).
export CLIPBOARD_SYNC_LOCAL_PEER=1
peer() { "$CS" "$@"; }
lastlog() { tail -n "${1:-20}" "$CLIPBOARD_SYNC_LOG" 2>/dev/null; }

# --- 1. texto -------------------------------------------------------------
msg="prueba-portapapeles-$RANDOM"
printf '%s' "$msg" | wl-copy 2>/dev/null
sleep 0.3
peer push
[ "$(wl-paste)" = "$msg" ] && ok "texto: llega al otro equipo" || fail "texto distinto en destino"
lastlog | grep -q 'receive: text/plain' && ok "texto: el receptor aplicó text/plain" || fail "texto: sin receive en el registro"

# --- 2. eco ---------------------------------------------------------------
peer push
lastlog | grep -q 'eco conocido' && ok "eco: el mismo contenido no rebota" || fail "eco: se reenvió lo mismo"

# --- 3. imagen ------------------------------------------------------------
head -c 120000 /dev/urandom >"$T/fuente/foto.png"
wl-copy --type image/png <"$T/fuente/foto.png"
sleep 0.3
peer push
cmp -s <(wl-paste --type image/png) "$T/fuente/foto.png" &&
  ok "imagen: bytes idénticos" || fail "imagen distinta en destino"

# --- 4. archivos ----------------------------------------------------------
printf 'video de prueba\n' >"$T/fuente/mi video.mp4"
head -c 3000000 /dev/urandom >"$T/fuente/captura.png"
sum1=$(sha256sum "$T/fuente/mi video.mp4" | cut -d' ' -f1)
sum2=$(sha256sum "$T/fuente/captura.png" | cut -d' ' -f1)
printf 'file://%s/mi%%20video.mp4\r\nfile://%s/captura.png\r\n' "$T/fuente" "$T/fuente" | wl-copy --type text/uri-list
sleep 0.3
peer push
dst=$(find "$INCOMING_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
if [ -n "$dst" ]; then
  ok "archivos: carpeta destino ${dst##*/}"
else
  fail "archivos: sin carpeta destino"
fi
[ -n "$dst" ] && [ "$(sha256sum "$dst/mi video.mp4" 2>/dev/null | cut -d' ' -f1)" = "$sum1" ] &&
  ok "archivos: video íntegro (nombre con espacio)" || fail "archivos: video distinto"
[ -n "$dst" ] && [ "$(sha256sum "$dst/captura.png" 2>/dev/null | cut -d' ' -f1)" = "$sum2" ] &&
  ok "archivos: png íntegro (3 MB)" || fail "archivos: png distinto"
[ -n "$dst" ] && wl-paste --type text/uri-list | grep -qF "file://$dst/" &&
  ok "archivos: la uri-list apunta al destino" || fail "archivos: uri-list sin reescribir"

# --- 5. entradas inválidas ------------------------------------------------
printf 'x' | "$CS" receive 'basura' "$(printf 'a%.0s' {1..64})" >/dev/null 2>&1
[ $? -eq 2 ] && ok "receive: rechaza mime inválido" || fail "receive: aceptó mime inválido"
printf 'x' | "$CS" receive 'text/plain' 'zz' >/dev/null 2>&1
[ $? -eq 2 ] && ok "receive: rechaza digest inválido" || fail "receive: aceptó digest inválido"

# --- 6. otro equipo caído -------------------------------------------------
msg="sin-ruta-$RANDOM"
printf '%s' "$msg" | wl-copy 2>/dev/null
sleep 0.3
t0=$(date +%s)
CLIPBOARD_SYNC_LOCAL_PEER=0 PEER_LAN_ADDR=203.0.113.1 \
  PEER_LAN=eztvn@203.0.113.1 PEER_TS=eztvn@203.0.113.1 "$CS" push >/dev/null 2>&1
rc=$?
dt=$(( $(date +%s) - t0 ))
[ "$rc" -ne 0 ] && ok "peer caído: push falla (rc=$rc, ${dt}s)" || fail "peer caído: push dijo que salió bien"
[ "$dt" -le 20 ] && ok "peer caído: no se cuelga (${dt}s)" || fail "peer caído: tardó ${dt}s"
lastlog | grep -q 'falló el envío' && ok "peer caído: queda registrado" || fail "peer caído: sin registro"
# --- 7. send --------------------------------------------------------------
peer send "$T/fuente/captura.png" >/dev/null 2>&1
find "$INCOMING_DIR" -name 'captura*.png' | grep -q . &&
  ok "send: comparte una ruta suelta" || fail "send: no llegó"

# --- 8. demonio -----------------------------------------------------------
setsid "$CS" watch >/dev/null 2>&1 &
wpid=$!
sleep 2
n0=$(wc -l <"$CLIPBOARD_SYNC_LOG" 2>/dev/null || echo 0)
printf 'lo que copio con el demonio escuchando' | wl-copy 2>/dev/null
sleep 2
tail -n +"$((n0 + 1))" "$CLIPBOARD_SYNC_LOG" 2>/dev/null | grep -q 'push: text/plain' &&
  ok "demonio: empuja solo al copiar" || fail "demonio: no reaccionó"
kill -- "-$wpid" 2>/dev/null || kill "$wpid" 2>/dev/null
wait "$wpid" 2>/dev/null

# --- resultado ------------------------------------------------------------
if [ "$fails" -eq 0 ]; then
  [ "$QUIET" = 1 ] || printf '\nportapapeles: todo en orden\n'
  exit 0
fi
printf '\nportapapeles: %d falla(s)\n' "$fails"
exit 1
