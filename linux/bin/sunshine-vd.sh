#!/usr/bin/env bash
# sunshine-vd.sh — pantalla virtual adaptativa para Sunshine en Hyprland (API Lua).
#
# Modos:
#   headless | off          host con la pantalla apagada: crea SUNSHINE-VD y
#                           desactiva la salida física (el cliente ve solo la virtual)
#   mirror | dup            host encendido y duplicando la pantalla virtual
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

# --- detección de red del cliente ---------------------------------------------
detect_net() {
    local peer
    peer=$(ss -Htn state established '( sport = :47989 or sport = :47984 or sport = :48010 )' 2>/dev/null \
        | awk '{print $5}' \
        | sed -E 's/^\[?([0-9.]+|.*%[^]]*)\]?:.*$/\1/' \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
        | grep -vE '^127\.' | head -1)
    case "$peer" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) echo tailscale ;;
        '') echo local ;;
        *) echo local ;;
    esac
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
client_present() {
    ss -Htn state established '( sport = :47984 or sport = :47989 or sport = :48010 )' 2>/dev/null | grep -q .
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

# --- arranque -----------------------------------------------------------------
do_start() {
    local mode="${1:-headless}" net="${2:-auto}"

    if ! hypr_init; then
        log "Hyprland no disponible; no se toca nada"
        return 0
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
    local ws
    case "$mode" in
        headless|off)
            [ -n "$PHYS" ] && lua "hl.monitor({ output=\"$PHYS\", disabled=true })"
            lua "hl.dispatch(hl.dsp.focus({ monitor = \"$OUTPUT\" }))"
            ;;
        mirror|dup|duplicar)
            if [ -n "$PHYS" ]; then
                ws=$(hypr activeworkspace -j 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["id"])
except Exception: print("")' 2>/dev/null)
                if [ -n "$ws" ]; then
                    lua "hl.dispatch(hl.dsp.workspace.move({ workspace = $ws, monitor = \"$OUTPUT\" }))"
                    sleep 0.2
                fi
                lua "hl.monitor({ output=\"$PHYS\", mode=\"$PMODE\", position=\"$PPOS\", scale=$PSCALE, mirror=\"$OUTPUT\", disabled=false })"
            fi
            lua "hl.dispatch(hl.dsp.focus({ monitor = \"$OUTPUT\" }))"
            ;;
        extend|extender)
            lua "hl.dispatch(hl.dsp.focus({ monitor = \"$OUTPUT\" }))"
            ;;
        *)
            log "modo desconocido: $mode"
            return 1
            ;;
    esac

    sleep 0.3
    snapshot
    touch "$STATE" 2>/dev/null
    spawn_watch
    log "modo=$mode red=$net cliente=${W}x${H}@${FPS} escala=$scale host=${PHYS:-ninguno} pos=$pos"
}

# --- parada -------------------------------------------------------------------
do_stop() {
    if ! hypr_init; then
        log "Hyprland no disponible; nada que restaurar"
        return 0
    fi
    if [ -r "$STATE" ]; then
        restore_state
        sleep 0.6
    fi
    hypr output remove "$OUTPUT" >/dev/null 2>&1
    rm -f "$STATE"
    snapshot
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
