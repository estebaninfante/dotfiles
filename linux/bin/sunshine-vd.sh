#!/usr/bin/env bash
# sunshine-vd.sh — pantalla virtual adaptativa para Sunshine en Hyprland (API Lua).
#
# Modos:
#   headless | off          host con la pantalla apagada: crea SUNSHINE-VD y
#                           desactiva la salida física (el cliente ve solo la virtual)
#   mirror | dup            host intacto: la pantalla virtual copia la física
#                           (el cliente ve lo mismo que se muestra en el host)
#   extend                  host encendido + pantalla extra a la derecha
#   stop | restore          quita la virtual y devuelve el monitor a como estaba
#   status                  imprime el estado actual
#
# Red (2º argumento, opcional): local | tailscale | auto (por defecto auto).
# La resolución/FPS sale de SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS que exporta Sunshine,
# así que se adapta sola a lo que pida cada cliente (Moonlight, iPhone, tablet...).
#
# Overrides en ~/.config/sunshine/vd.conf (formato KEY=VALOR):
#   MAX_W_LOCAL=3840  MAX_FPS_LOCAL=0      # 0 = sin tope
#   MAX_W_TAILSCALE=1920  MAX_FPS_TAILSCALE=60
#   FORCE_SCALE=                           # vacío = automático (2 si alto >= 1600)
#   CLIENTES_TECLADO="14:ac:60:ff:a4:15"   # MACs/IPs de clientes con teclado
#                                          # físico propio: no se cambia el layout

set -uo pipefail

SELF="$(readlink -f "$0")"
OUTPUT="SUNSHINE-VD"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sunshine-vd"
STATE="$CACHE/state.json"
MONS="$CACHE/monitors.json"
LUA="$CACHE/restore.lua"
LOG="$CACHE/last.log"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/vd.conf"

mkdir -p "$CACHE"

# La salida se guarda en $LOG y además va a stderr, que es lo que Sunshine
# recoge en su propio log. stdout queda libre para 'status'.
log() {
    local msg
    msg="[$(date '+%F %T')] $*"
    printf '%s\n' "$msg" >>"$LOG"
    printf '%s\n' "$msg" >&2
}

# --- ajustes (sobrescribibles) ------------------------------------------------
MAX_W_LOCAL=3840
MAX_FPS_LOCAL=0
MAX_W_TAILSCALE=1920
MAX_FPS_TAILSCALE=60
FORCE_SCALE=""
# Clientes en la red de casa que escriben con su propio teclado Dvorak (la
# laptop): por MAC (wifi de laptopmarchy) o IP. Por Tailscale no hace falta
# listarlos: se decide por el sistema operativo del nodo.
CLIENTES_TECLADO="14:ac:60:ff:a4:15 192.168.1.240"
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"

# --- hyprctl (con fallback de instancia) --------------------------------------
SIG=""
hypr() {
    if [ -n "$SIG" ]; then
        HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@"
    else
        hyprctl "$@"
    fi
}

hypr_init() {
    if hypr monitors -j >/dev/null 2>&1; then
        [ -n "$SIG" ] || SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
        return 0
    fi
    local d
    for d in $(ls -1dt /run/user/"$(id -u)"/hypr/*/ 2>/dev/null); do
        SIG="$(basename "$d")"
        if hypr monitors -j >/dev/null 2>&1; then
            return 0
        fi
    done
    SIG=""
    return 1
}

lua() { hypr eval "$1" >/dev/null 2>&1; }

snapshot() { hypr monitors all -j >"$MONS" 2>/dev/null; [ -s "$MONS" ]; }

# --- layout del teclado -------------------------------------------------------
# El cliente (Moonlight en el celular) manda posiciones QWERTY, así que mientras
# dura el stream todos los teclados tienen que estar en 'es'. Al terminar vuelve
# el dvk_prog del teclado físico. Índices de switch-layout.sh: 0=dvk_prog, 1=es.
LAYOUT_SH="${HOME}/.local/bin/switch-layout.sh"
switch_layout() {
    [ -x "$LAYOUT_SH" ] || return 0
    "$LAYOUT_SH" "$1" || log "switch-layout.sh $1 falló"
}

# --- estado del host ----------------------------------------------------------
save_state() {
    snapshot || return 1
    python3 - "$MONS" "$STATE" "$OUTPUT" <<'PY'
import json, sys
mons, state, out = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(mons))
by_id = {m.get("id"): m for m in data}
keep = []
for m in data:
    name = m["name"]
    if name == out or name.startswith("HEADLESS"):
        continue
    mirror = m.get("mirrorOf") or "none"
    if mirror not in ("none", "", None):
        target = by_id.get(mirror) or next((x for x in data if x["name"] == mirror), None)
        mirror = target["name"] if target else "none"
    keep.append({
        "name": name,
        "mode": "%dx%d@%.5f" % (m["width"], m["height"], m["refreshRate"]),
        "position": "%dx%d" % (m["x"], m["y"]),
        "scale": m["scale"],
        "mirror": mirror,
        "disabled": bool(m.get("disabled", False)),
        "cm": m.get("cm") or "",
        "vrr": 1 if m.get("vrr") else 0,
    })
json.dump(keep, open(state, "w"), indent=2)
PY
    log "estado guardado en $STATE"
}

restore_state() {
    [ -r "$STATE" ] || return 1
    python3 - "$STATE" >"$LUA" <<'PY'
import json, sys
for m in json.load(open(sys.argv[1])):
    parts = ['output="%s"' % m["name"], 'mode="%s"' % m["mode"],
             'position="%s"' % m["position"], 'scale=%s' % m["scale"],
             'disabled=%s' % ("true" if m["disabled"] else "false")]
    # mirror siempre explícito: la regla de monitor se fusiona por salida, así
    # que sin esto un espejo anterior quedaría pegado a la salida.
    parts.append('mirror="%s"' % (m.get("mirror") if m.get("mirror") and m["mirror"] != "none" else ""))
    if m.get("cm"):
        parts.append('cm="%s"' % m["cm"])
    if m.get("vrr"):
        parts.append("vrr=1")
    print("hl.monitor({ %s })" % ", ".join(parts))
PY
    lua "$(cat "$LUA")"
    log "monitores restaurados"
}

# --- detección del cliente ---------------------------------------------------
# Mientras corre el prep-cmd el cliente mantiene abierta la petición /launch
# (HTTPS), así que su IP sale de esa conexión. Con 'state established' ss no
# imprime la columna de estado: el par remoto es la 4ª columna.
client_ip() {
    ss -Htn state established '( sport = :47989 or sport = :47984 or sport = :48010 )' 2>/dev/null \
        | awk '{print $4}' \
        | sed -E 's/^\[?(::ffff:)?([0-9.]+)\]?:[0-9]+$/\2/' \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
        | grep -vE '^127\.' | head -1
}

is_tailscale_ip() {
    case "$1" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
    esac
    return 1
}

detect_net() {
    if is_tailscale_ip "$(client_ip)"; then echo tailscale; else echo local; fi
}

# ¿El cliente trae su propio teclado físico? Un computador manda las teclas
# ya en su layout y en el host tiene que seguir dvk_prog; un celular o una
# tablet mandan posiciones QWERTY y necesitan 'es'.
client_has_keyboard() {
    local ip="$1" os mac entry
    [ -n "$ip" ] || return 1
    if is_tailscale_ip "$ip" && command -v tailscale >/dev/null 2>&1; then
        os=$(timeout 3 tailscale whois --json "$ip" 2>/dev/null |
            python3 -c 'import json,sys; print(json.load(sys.stdin)["Node"]["Hostinfo"].get("OS",""))' 2>/dev/null)
        case "$os" in
            linux|windows|macOS|freebsd) return 0 ;;
            '') ;;
            *) return 1 ;;
        esac
    fi
    mac=$(ip neigh show "$ip" 2>/dev/null | awk '/lladdr/ {print tolower($5); exit}')
    for entry in $CLIENTES_TECLADO; do
        entry=$(printf '%s' "$entry" | tr 'A-Z' 'a-z')
        [ "$entry" = "$ip" ] || { [ -n "$mac" ] && [ "$entry" = "$mac" ]; } && return 0
    done
    return 1
}

# --- monitor físico -----------------------------------------------------------
# Emite: NOMBRE MODO POSICION ESCALA POSICION_DERECHA
phys_info() {
    snapshot || return 1
    python3 - "$MONS" "$OUTPUT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
out = sys.argv[2]
cands = [m for m in data if m["name"] != out and not m["name"].startswith("HEADLESS")]
if not cands:
    print()
    raise SystemExit
enabled = [m for m in cands if not m.get("disabled")] or cands
m = enabled[0]
right = m["x"] + round(m["width"] / (m["scale"] or 1))
print(m["name"], "%dx%d@%.5f" % (m["width"], m["height"], m["refreshRate"]),
      "%dx%d" % (m["x"], m["y"]), m["scale"], "%dx%d" % (right, m["y"]))
PY
}

# --- watchdog: si el cliente desaparece sin cerrar sesión ---------------------
# Sunshine ejecuta el 'undo' al cerrar la app, pero si el cliente se cae (crash,
# kill, pérdida de red) el host se quedaría con la pantalla virtual puesta.
# Este vigilante restaura el monitor cuando no hay ninguna conexión de cliente.
# Durante el stream no queda ninguna conexión TCP (video, audio y control van
# por UDP sin conectar), así que el estado real sale del log de Sunshine: hay
# cliente si la última línea CLIENT CONNECTED/DISCONNECTED es CONNECTED.
SUNSHINE_LOG="${XDG_CONFIG_HOME:-$HOME/.config}/sunshine/sunshine.log"
client_present() {
    ss -Htn state established '( sport = :47984 or sport = :47989 or sport = :48010 )' 2>/dev/null | grep -q . && return 0
    pgrep -x sunshine >/dev/null 2>&1 || return 1
    grep -oE 'CLIENT (CONNECTED|DISCONNECTED)' "$SUNSHINE_LOG" 2>/dev/null | tail -n1 | grep -q 'CLIENT CONNECTED$'
}

watch_loop() {
    local misses=0 mtime
    mtime=$(stat -c %Y "$STATE" 2>/dev/null || echo 0)
    while [ -r "$STATE" ]; do
        local cur
        cur=$(stat -c %Y "$STATE" 2>/dev/null || echo 0)
        if [ "$cur" != "$mtime" ]; then
            # sesión nueva: empezar a contar de cero
            mtime=$cur
            misses=0
        elif client_present; then
            misses=0
        else
            misses=$((misses + 1))
            if [ "$misses" -ge 9 ]; then
                log "sin cliente desde hace ~45s; restaurando la pantalla"
                do_stop
                break
            fi
        fi
        sleep 5
    done
}

spawn_watch() {
    if command -v flock >/dev/null 2>&1; then
        setsid flock -n "$CACHE/watch.lock" "$SELF" __watch </dev/null >/dev/null 2>&1 &
    else
        setsid "$SELF" __watch </dev/null >/dev/null 2>&1 &
    fi
}

# --- transición en pantalla (plugin eztvn.enlace del shell) -------------------
# Antes de tocar monitores se cubre la pantalla con una escena (equipo y
# cliente separándose); los cambios ocurren debajo y al final se pide el
# reveal. Si el shell o el plugin no están, todo sigue igual que antes.
ENLACE_READY=""
enlace_ready() {
    if [ -z "$ENLACE_READY" ]; then
        ENLACE_READY=no
        command -v omarchy-shell >/dev/null 2>&1 &&
            [ "$(timeout 2 omarchy-shell eztvn.enlace ping 2>/dev/null)" = ok ] &&
            ENLACE_READY=yes
    fi
    [ "$ENLACE_READY" = yes ]
}

# enlace_cover in MODO W H FPS RED | enlace_cover out
enlace_cover() {
    enlace_ready || return 0
    local method=streamOut payload='{}'
    if [ "$1" = in ]; then
        method=streamIn
        payload=$(python3 -c 'import json, sys
a = sys.argv[1:]
print(json.dumps({"mode": a[0], "width": int(a[1]), "height": int(a[2]),
                  "fps": int(a[3]), "net": a[4], "app": a[5]}))' \
            "$2" "$3" "$4" "$5" "$6" "${SUNSHINE_APP_NAME:-}" 2>/dev/null) || payload='{}'
    fi
    timeout 2 omarchy-shell -q eztvn.enlace "$method" "$payload" >/dev/null 2>&1
    # La escena tiene que estar opaca antes del primer modeset (Tokens.slow +
    # aire). Con animaciones apagadas el plugin tapa en seco.
    if [ "$(cat "$HOME/.local/state/omarchy/animations-enabled" 2>/dev/null || echo 1)" != 0 ]; then
        sleep 0.42
    fi
}

# enlace_reveal [ms de espera antes de abrir]
enlace_reveal() {
    enlace_ready || return 0
    timeout 2 omarchy-shell -q eztvn.enlace streamReveal "${1:-1}" >/dev/null 2>&1
}

# --- arranque -----------------------------------------------------------------
do_start() {
    local mode="${1:-headless}" net="${2:-auto}"

    if ! hypr_init; then
        log "Hyprland no disponible; no se toca nada"
        return 0
    fi

    # Celular/tablet escriben con posiciones QWERTY; el teclado físico usa
    # dvk_prog. Un cliente con teclado propio (la laptop) se queda en dvk_prog.
    local cip kb
    cip=$(client_ip)
    if client_has_keyboard "$cip"; then
        kb=dvk_prog
    else
        kb=es
        switch_layout 1
    fi

    local W="${SUNSHINE_CLIENT_WIDTH:-1920}"
    local H="${SUNSHINE_CLIENT_HEIGHT:-1080}"
    local FPS="${SUNSHINE_CLIENT_FPS:-60}"
    case "$W" in *[!0-9]*|'') W=1920 ;; esac
    case "$H" in *[!0-9]*|'') H=1080 ;; esac
    case "$FPS" in *[!0-9]*|'') FPS=60 ;; esac
    FPS=${FPS%.*}
    [ "$W" -ge 640 ] || W=640
    [ "$H" -ge 480 ] || H=480

    if [ "$net" = auto ]; then
        net=$(detect_net)
    fi

    enlace_cover in "$mode" "$W" "$H" "$FPS" "$net"

    local maxw maxfps
    if [ "$net" = tailscale ]; then
        maxw=$MAX_W_TAILSCALE; maxfps=$MAX_FPS_TAILSCALE
    else
        maxw=$MAX_W_LOCAL; maxfps=$MAX_FPS_LOCAL
    fi
    if [ "${maxw:-0}" -gt 0 ] && [ "$W" -gt "$maxw" ]; then
        H=$((H * maxw / W)); W=$maxw
    fi
    if [ "${maxfps:-0}" -gt 0 ] && [ "$FPS" -gt "$maxfps" ]; then
        FPS=$maxfps
    fi
    # pares, que los codificadores lo agradecen
    W=$((W / 2 * 2)); H=$((H / 2 * 2))

    local scale="$FORCE_SCALE"
    if [ -z "$scale" ]; then
        if [ "$H" -ge 1600 ]; then scale=2; else scale=1; fi
    fi

    # 1) estado original del host (solo la primera vez)
    [ -r "$STATE" ] || save_state

    local PHYS="" PMODE="" PPOS="" PSCALE="" PRIGHT=""
    read -r PHYS PMODE PPOS PSCALE PRIGHT < <(phys_info)

    # 2) posición de la virtual
    local pos="0x0"
    if [ "$mode" = extend ] && [ -n "$PRIGHT" ]; then
        pos="$PRIGHT"
    fi

    # 3) crear la salida virtual
    hypr output remove "$OUTPUT" >/dev/null 2>&1
    hypr output create headless "$OUTPUT" >/dev/null 2>&1
    local i
    for i in $(seq 1 40); do
        if snapshot && grep -q "\"$OUTPUT\"" "$MONS"; then break; fi
        sleep 0.1
    done

    lua "hl.monitor({ output=\"$OUTPUT\", mode=\"${W}x${H}@${FPS}\", position=\"$pos\", scale=$scale })"
    sleep 0.3

    # 4) acciones según el modo
    case "$mode" in
        headless|off)
            [ -n "$PHYS" ] && lua "hl.monitor({ output=\"$PHYS\", disabled=true })"
            lua "hl.dispatch(hl.dsp.focus({ monitor = \"$OUTPUT\" }))"
            ;;
        mirror|dup|duplicar)
            # El host no se toca: la virtual copia la física con su misma
            # resolución, escala y posición. El cliente ve exactamente lo que
            # hay en la pantalla del host y Moonlight lo escala a su tamaño.
            if [ -n "$PHYS" ]; then
                lua "hl.monitor({ output=\"$OUTPUT\", mode=\"$PMODE\", position=\"$PPOS\", scale=$PSCALE, mirror=\"$PHYS\" })"
            fi
            ;;
        extend|extender)
            lua "hl.dispatch(hl.dsp.focus({ monitor = \"$OUTPUT\" }))"
            ;;
        *)
            log "modo desconocido: $mode"
            enlace_reveal 1
            return 1
            ;;
    esac

    sleep 0.3
    snapshot
    touch "$STATE" 2>/dev/null
    spawn_watch
    # El cliente empieza a recibir video recién cuando este prep-cmd termina:
    # se abre con un poco de demora para que también vea la apertura.
    enlace_reveal 900
    log "modo=$mode red=$net cliente=${cip:-?} teclado=$kb ${W}x${H}@${FPS} escala=$scale host=${PHYS:-ninguno} pos=$pos"
}

# --- parada -------------------------------------------------------------------
do_stop() {
    if ! hypr_init; then
        log "Hyprland no disponible; nada que restaurar"
        return 0
    fi
    switch_layout 0
    enlace_cover out
    if [ -r "$STATE" ]; then
        restore_state
        sleep 0.6
    fi
    hypr output remove "$OUTPUT" >/dev/null 2>&1
    rm -f "$STATE"
    snapshot
    enlace_reveal 150
    log "pantalla virtual eliminada; estado restaurado"
}

case "${1:-headless}" in
    __watch) watch_loop ;;
    stop|restore|undo) do_stop ;;
    status)
        if hypr_init && snapshot; then
            python3 - "$MONS" <<'PY'
import json, sys
for m in json.load(open(sys.argv[1])):
    print("%-14s %5dx%-5d @%8.2f  %6s  escala %-5s mirror %-8s %s" % (
        m["name"], m["width"], m["height"], m["refreshRate"],
        "%dx%d" % (m["x"], m["y"]), m["scale"], m["mirrorOf"],
        "disabled" if m.get("disabled") else "activo"))
PY
        else
            echo "Hyprland no disponible"
        fi
        ;;
    *) do_start "$@" ;;
esac
