#!/usr/bin/env bash
set -uo pipefail

SO="${HYPR3D_SO:-$HOME/.local/share/hypr3d-src/build/hypr3d.so}"
ASSETS="$HOME/.local/share/hypr3d"
OUT="${HYPR3D_VERIFY_OUT:-/tmp/opencode/hypr3d-verify}"
CONF="$OUT/nested.lua"
LOG="$OUT/nested.log"
REPORT="$OUT/report.json"
PNG_ON="$OUT/on.png"
PNG_OFF="$OUT/off.png"
MODE="${HYPR3D_DEV_MODE:-1280x720@60}"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HYPR_DIR="$RT/hypr"
PANORAMA="$ASSETS/space.png"
MAP="$ASSETS/space.glb"
SETTLE="${HYPR3D_VERIFY_SETTLE:-2.0}"
CYCLES="${HYPR3D_VERIFY_CYCLES:-1}"
WITH_FLOAT="${HYPR3D_VERIFY_FLOAT:-0}"
WITH_CHURN="${HYPR3D_VERIFY_CHURN:-0}"
CLASS="hypr3d-fixture"
FCLASS="hypr3d-float"
NEW_TITLE="HYPR3D-D"
CLOSED_TITLE="HYPR3D-C"

TERMINAL=""
for c in kitty foot ghostty alacritty wezterm; do
    command -v "$c" >/dev/null 2>&1 && { TERMINAL="$c"; break; }
done
[ -n "$TERMINAL" ] || { echo "SUMMARY: FAIL no-terminal"; exit 1; }
[ -f "$SO" ] || { echo "SUMMARY: FAIL no-so $SO"; exit 1; }
[ -f "$PANORAMA" ] || { echo "SUMMARY: FAIL no-panorama $PANORAMA"; exit 1; }
[ -f "$MAP" ] || { echo "SUMMARY: FAIL no-map $MAP"; exit 1; }

mkdir -p "$OUT"
SIG_HOST="$(hyprctl instances 2>/dev/null | sed -n 's/^instance \(.*\):$/\1/p' | head -1)"
[ -n "$SIG_HOST" ] || SIG_HOST="${HYPRLAND_INSTANCE_SIGNATURE:-}"

{
    echo "local SO = os.getenv(\"HYPR3D_SO\")"
    echo ""
    echo "hl.monitor({ output = \"WAYLAND-1\", mode = \"$MODE\", position = \"0x0\", scale = 1 })"
    echo "hl.monitor({ output = \"\", mode = \"$MODE\", position = \"auto\", scale = 1 })"
    echo ""
    echo "hl.config({"
    echo "  animations = { enabled = false },"
    echo "  cursor = { no_hardware_cursors = true },"
    echo "  input = { follow_mouse = 0 },"
    echo "})"
    echo ""
    if [ "$WITH_FLOAT" = "1" ]; then
        echo "hl.window_rule({ match = { class = \"$FCLASS\" }, float = 1 })"
        echo ""
    fi
    echo "if SO then hl.plugin.load(SO) end"
    echo ""
    echo "hl.on(\"hyprland.start\", function()"
    echo "  hl.exec_cmd(\"$TERMINAL --class $CLASS --title HYPR3D-A\")"
    echo "  hl.exec_cmd(\"$TERMINAL --class $CLASS --title HYPR3D-B\")"
    echo "  hl.exec_cmd(\"$TERMINAL --class $CLASS --title HYPR3D-C\")"
    if [ "$WITH_FLOAT" = "1" ]; then
        echo "  hl.exec_cmd(\"$TERMINAL --class $FCLASS --title HYPR3D-F\")"
    fi
    echo "end)"
} > "$CONF"

cleanup() {
    [ -n "${nested_pid:-}" ] && kill "$nested_pid" >/dev/null 2>&1 || true
    pkill -f 'hypr3d-verify/nested.lua' >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
cleanup
sleep 0.3

setsid env HYPRLAND_NO_LOGO=1 HYPR3D_SO="$SO" Hyprland -c "$CONF" >"$LOG" 2>&1 </dev/null &
nested_pid=$!

SIG=""
for _ in $(seq 1 240); do
    for d in $(ls -t "$HYPR_DIR" 2>/dev/null); do
        [ "$d" = "$SIG_HOST" ] && continue
        if HYPRLAND_INSTANCE_SIGNATURE="$d" hyprctl -j version >/dev/null 2>&1; then
            SIG="$d"; break
        fi
    done
    [ -n "$SIG" ] && break
    sleep 0.25
done
[ -n "$SIG" ] || { echo "SUMMARY: FAIL no-nested-ipc"; exit 1; }

nested() { HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@"; }

plugin_loaded="$(nested plugin list 2>/dev/null | grep -ci hypr3d)"
plugin_version="$(nested -j plugin list 2>/dev/null | jq -r '[.[]|select(.name|test("hypr3d";"i"))][0].version // "none"' 2>/dev/null)"

opts() {
    for o in general:gaps_in general:gaps_out general:border_size; do
        printf '%s=%s ' "$o" "$(nested -j getoption "$o" 2>/dev/null | jq -r '.int // "?"')"
    done
}

fixtures() {
    nested -j clients | jq -c --arg c "$CLASS" --arg f "$FCLASS" \
        '[.[] | select(((.class // "") == $c) or ((.class // "") == $f)) | {title, class, floating, at, size}] | sort_by(.title)'
}

tiled_fixtures() {
    nested -j clients | jq -c --arg c "$CLASS" \
        '[.[] | select((.class // "") == $c) | {title, class, floating, at, size}] | sort_by(.title)'
}

stable_fixtures() {
    local prev="" cur="" same=0
    for _ in $(seq 1 120); do
        cur="$(tiled_fixtures 2>/dev/null)"
        [ -n "$cur" ] && [ "$cur" != "[]" ] && [ "$cur" = "$prev" ] && same=$((same+1)) || same=0
        [ "$same" -ge 4 ] && { echo "$cur"; return; }
        prev="$cur"
        sleep 0.25
    done
    echo "$cur"
}

stable_all() {
    local prev="" cur="" same=0
    for _ in $(seq 1 120); do
        cur="$(fixtures 2>/dev/null)"
        [ -n "$cur" ] && [ "$cur" != "[]" ] && [ "$cur" = "$prev" ] && same=$((same+1)) || same=0
        [ "$same" -ge 4 ] && { echo "$cur"; return; }
        prev="$cur"
        sleep 0.25
    done
    echo "$cur"
}

WANT_N=3
[ "$WITH_FLOAT" = "1" ] && WANT_N=4
for _ in $(seq 1 160); do
    n="$(fixtures 2>/dev/null | jq 'length' 2>/dev/null)"
    [ "${n:-0}" -ge "$WANT_N" ] && break
    sleep 0.25
done
sleep 1.0

HOSTWAY="$(HYPRLAND_INSTANCE_SIGNATURE="$SIG_HOST" hyprctl -j clients 2>/dev/null | jq -r '[.[] | select((.class // "") | test("aquamarine"; "i"))][0].address' 2>/dev/null)"
GEOM=""
if [ -n "$HOSTWAY" ] && [ "$HOSTWAY" != "null" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$SIG_HOST" hyprctl eval "hl.dispatch(hl.dsp.window.move({ window = \"address:$HOSTWAY\", x = 20, y = 20, relative = false }))" >/dev/null 2>&1 || true
    HYPRLAND_INSTANCE_SIGNATURE="$SIG_HOST" hyprctl eval "hl.dispatch(hl.dsp.window.resize({ window = \"address:$HOSTWAY\", x = 1000, y = 640, relative = false }))" >/dev/null 2>&1 || true
    sleep 0.5
    GEOM="$(HYPRLAND_INSTANCE_SIGNATURE="$SIG_HOST" hyprctl -j clients 2>/dev/null | jq -r --arg a "$HOSTWAY" '[.[] | select(.address==$a)][0] | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
fi

PRE_ALL="$(stable_all)"
nested eval "hl.plugin.hypr3d.config({ world = { panorama = '$PANORAMA', grid = false }, player = { flying = true, spawn = { x = 0, y = 2, z = 16 } }, map = { path = '$MAP', collision = true, flat = false, emissive_scale = 1.0 } })" >/dev/null 2>&1

POSTS=""
MID_LAST=""
for cycle in $(seq 1 "$CYCLES"); do
    nested eval 'hl.plugin.hypr3d.toggle()' >/dev/null 2>&1
    sleep "$SETTLE"
    MID_LAST="$(tiled_fixtures)"
    [ "$cycle" -eq 1 ] && [ -n "$GEOM" ] && grim -g "$GEOM" "$PNG_ON" >/dev/null 2>&1 || true

    # Ring/room snapshot for the deterministic layout checks below.
    nested eval 'hl.plugin.hypr3d.rooms()' >/dev/null 2>&1
    cp /tmp/hypr3d-rooms.txt "$OUT/rooms-$cycle.txt" 2>/dev/null || true

    if [ "$WITH_CHURN" = "1" ] && [ "$cycle" -eq 1 ]; then
        addr="$(nested -j clients 2>/dev/null | jq -r --arg t "$CLOSED_TITLE" '[.[] | select(.title==$t)][0].address // ""')"
        [ -n "$addr" ] && nested eval "hl.dispatch(hl.dsp.window.close({ window = \"address:$addr\" }))" >/dev/null 2>&1
        sleep 0.5
        nested eval "hl.dispatch(hl.dsp.exec_cmd(\"$TERMINAL --class $CLASS --title $NEW_TITLE\"))" >/dev/null 2>&1
        sleep 1.0
    fi

    nested eval 'hl.plugin.hypr3d.toggle()' >/dev/null 2>&1
    sleep "$SETTLE"
    POSTS="$POSTS$(stable_fixtures)
"
    [ "$cycle" -eq "$CYCLES" ] && [ -n "$GEOM" ] && grim -g "$GEOM" "$PNG_OFF" >/dev/null 2>&1 || true
done

POST_ALL="$(stable_all)"
POSTS_JSON="$(printf '%s' "$POSTS" | jq -s -c '.')"
MID_JSON="$(printf '%s' "$MID_LAST" | jq -c '.')"
PRE_JSON="$(printf '%s' "$PRE_ALL" | jq -c '.')"
DIAG_POST="$(opts)"
MONS_POST="$(nested -j monitors 2>/dev/null | jq -c '[.[] | {name, width, height, scale, reserved, activeWorkspace: .activeWorkspace.id}]')"

nested -j clients > "$OUT/clients-post.json" 2>/dev/null

VERDICT="$(jq -n -c \
    --argjson pre "$PRE_JSON" \
    --argjson mid "$MID_JSON" \
    --argjson posts "$POSTS_JSON" \
    --argjson postall "$POST_ALL" \
    --arg cls "$CLASS" \
    --arg newt "$NEW_TITLE" \
    --arg closedt "$CLOSED_TITLE" \
    --argjson cycles "$CYCLES" \
    --argjson churn "$([ "$WITH_CHURN" = "1" ] && echo true || echo false)" '
  def overlaps($a;$b):
    ($a.at[0] < ($b.at[0]+$b.size[0])) and ($b.at[0] < ($a.at[0]+$a.size[0])) and
    ($a.at[1] < ($b.at[1]+$b.size[1])) and ($b.at[1] < ($a.at[1]+$a.size[1]));
  def any_overlap($w):
    [range(0; ($w|length)) as $i | range($i+1; ($w|length)) as $j |
      if overlaps($w[$i];$w[$j]) then "\($w[$i].title)/\($w[$j].title)" else empty end];
  def boxdiff($a;$b): (($a.at[0]-$b.at[0])|fabs) + (($a.at[1]-$b.at[1])|fabs);
  def samesize($a;$b): ($a.size[0]==$b.size[0]) and ($a.size[1]==$b.size[1]);
  def tiled: map(select(.class==$cls));
  def missing_expected: if $churn then [$closedt] else [] end;
  ($pre|tiled) as $preT |
  ($mid|tiled) as $midT |
  ($posts|map(tiled)) as $postsT |
  ($postall|tiled) as $postT |
  ($preT|map(.title)) as $preTitles |
  {
    cycles: $cycles,
    count_pre: ($preT|length),
    count_mid: ($midT|length),
    count_post: ($postT|length),
    floating_mid: [$midT[] | select(.floating) | .title],
    missing_post: [$preTitles[] | select(. as $t | ($postT|map(.title)|index($t)) == null) | .],
    floating_post: [$postT[] | select(.floating) | .title],
    overlap_post: any_overlap($postT),
    drift_post: [($postT[] | . as $p | ($preT[] | select(.title==$p.title) | . as $q | if boxdiff($p;$q) > 4 or (samesize($p;$q)|not) or $p.floating != $q.floating then $p.title else empty end))],
    drift_cycles: [range(0;($postsT|length)) as $c | ($postsT[$c] | .[] | . as $p | ($preT[] | select(.title==$p.title) | . as $q | if boxdiff($p;$q) > 4 or (samesize($p;$q)|not) or $p.floating != $q.floating then {cycle: ($c+1), title: $p.title} else empty end))],
    float_window: ($pre|map(select(.class != $cls)) | map({title, floating, at, size})),
    float_window_post: ($postall|map(select(.class != $cls)) | map({title, floating, at, size})),
    new_window_post: [($postT[] | select(.title==$newt) | {title, floating, at, size})],
    new_window_ok: ([($postT[] | select(.title==$newt) | select(.floating or .size[0] >= 500))]|length) == ($churn|if . then 1 else 0 end)
  }')"


ok=yes
jq -e '
  (.count_post >= 3 or (.missing_post|length) == 0) and
  (.floating_post|length) == 0 and
  (.overlap_post|length) == 0 and
  (.drift_post|length) == 0 and
  (.drift_cycles|length) == 0 and
  (.missing_post|length) == 0 and
  (.float_window_post|map(select(.floating))|length) == (.float_window|length) and
  .new_window_ok
' <<<"$VERDICT" >/dev/null 2>&1 || ok=no
[ "$plugin_loaded" -ge 1 ] || ok=no

# --- ring room checks -------------------------------------------------------
# The plugin dumps its rooms to /tmp/hypr3d-rooms.txt on demand
# (hl.plugin.hypr3d.rooms()). Both the geometry and the persistence across an
# off/on toggle are asserted here, deterministically, without screenshots.
RING_JSON="null"
RING_OK=skip
RING_PERSIST=-1

if [ -f "$OUT/rooms-1.txt" ]; then
    RING_JSON_RAW="$(awk '
        BEGIN { PI = 3.141592653589793; TAU = 2 * PI; R0 = 0 }
        function abs(x) { return x < 0 ? -x : x }
        function wrap(x) { x = x % TAU; if (x > PI) x -= TAU; if (x < -PI) x += TAU; return x }
        /^active / { act = $2; next }
        /^room / { inroom = ($2 == act); R = $4; cx = $5; cy = $6; cz = $7; next }
        inroom && $1 == "win" {
            n++; id[n] = $2; x[n] = $3; y[n] = $4; z[n] = $5;
            yaw[n] = $6; w[n] = $7; h[n] = $8; ring[n] = $9;
        }
        END {
            bad = "";
            if (n < 2) bad = bad "few-windows;";
            for (i = 1; i <= n; i++) {
                if (ring[i] != 1) bad = bad "not-ring:" id[i] ";";
                dx = x[i] - cx; dz = z[i] - cz;
                r = sqrt(dx * dx + dz * dz);
                if (i == 1) R0 = r; else if (abs(r - R0) > 0.08) bad = bad "radius:" id[i] ";";
                if (abs(y[i] - cy) > 0.02) bad = bad "level:" id[i] ";";
                a = atan2(dx, -dz);
                if (abs(wrap(yaw[i] + a)) > 0.08) bad = bad "facing:" id[i] ";";
            }
            for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) {
                dx = x[i] - x[j]; dy = y[i] - y[j]; dz = z[i] - z[j];
                d = sqrt(dx * dx + dy * dy + dz * dz);
                need = (w[i] + w[j]) / 2;
                if (d < need) bad = bad "overlap:" i "," j ";";
            }
            printf "%d %.4f %d %s\n", n, R0, (bad == ""), (bad == "" ? "none" : bad);
        }
    ' "$OUT/rooms-1.txt" 2>/dev/null)"

    read -r RING_N RING_R RING_GOOD RING_PROBLEMS <<<"${RING_JSON_RAW:-}"

    if [ "${RING_GOOD:-0}" = "1" ]; then
        RING_OK=yes
    else
        RING_OK=no
    fi

    RING_JSON="$(jq -n -c \
        --argjson n "${RING_N:-0}" \
        --argjson radius "${RING_R:-0}" \
        --argjson ok "$([ "${RING_GOOD:-0}" = "1" ] && echo true || echo false)" \
        --arg problems "${RING_PROBLEMS:-no-data}" \
        '{n: $n, radius: $radius, ok: $ok, problems: $problems}')"

    pose_of() {
        awk '
            /^active / { act = $2; next }
            /^room / { inroom = ($2 == act); next }
            inroom && $1 == "win" { printf "%s %.4f %.4f %.4f %.4f\n", $2, $3, $4, $5, $6 }
        ' "$1" | sort
    }

    if [ "$CYCLES" -ge 2 ] && [ -f "$OUT/rooms-2.txt" ]; then
        pose_of "$OUT/rooms-1.txt" > "$OUT/pose-1.txt"
        pose_of "$OUT/rooms-2.txt" > "$OUT/pose-2.txt"
        if cmp -s "$OUT/pose-1.txt" "$OUT/pose-2.txt"; then
            RING_PERSIST=1
        else
            RING_PERSIST=0
            RING_OK=no
        fi
    fi
fi

[ "$RING_OK" = no ] && ok=no
if [ "$RING_OK" = skip ] && [ "${HYPR3D_VERIFY_REQUIRE_RING:-0}" = "1" ]; then
    ok=no
fi

{
    echo "{"
    echo "\"plugin_loaded\": $plugin_loaded,"
    echo "\"plugin_version\": \"$plugin_version\","
    echo "\"cycles\": $CYCLES,"
    echo "\"with_float\": $WITH_FLOAT,"
    echo "\"with_churn\": $WITH_CHURN,"
    echo "\"pre\": $PRE_ALL,"
    echo "\"in3d\": $MID_JSON,"
    echo "\"posts\": $POSTS_JSON,"
    echo "\"post_all\": $POST_ALL,"
    echo "\"mons_post\": $MONS_POST,"
    echo "\"diag_post\": \"$DIAG_POST\","
    echo "\"ring\": $RING_JSON,"
    echo "\"ring_ok\": \"$RING_OK\","
    echo "\"ring_persist\": $RING_PERSIST,"
    echo "\"verdict\": $VERDICT"
    echo "}"
} > "$REPORT"

echo "SUMMARY: verdict=$ok plugin_loaded=$plugin_loaded version=$plugin_version cycles=$CYCLES float=$WITH_FLOAT churn=$WITH_CHURN ring=$RING_OK persist=$RING_PERSIST"
echo "RING: $RING_JSON"
echo "VERDICT: $(echo "$VERDICT" | tr -d "\n ")"
echo "PNG_ON=$PNG_ON PNG_OFF=$PNG_OFF"
echo "LOG: $LOG REPORT: $REPORT"
[ "$ok" = yes ] && exit 0 || exit 1
