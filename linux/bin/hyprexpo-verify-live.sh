#!/usr/bin/env bash
# verify-live.sh — prove hyprexpo live-refresh: hidden-workspace tile must
# recapture while the overview is open (frozen preview bug otherwise).
# Launches a nested Hyprland (never the live session), opens a scrolling
# terminal on workspace 2, switches back to 1, opens the overview, screenshots
# the nested host window twice ~1.5s apart and counts differing pixels.
set -uo pipefail

SRC="${HYPREXPO_SRC:-$HOME/.cache/hyprexpo-src}"
OUT="${HYPREXPO_VERIFY_OUT:-$HOME/.cache/hyprexpo-live}"
MODE="${HYPREXPO_DEV_MODE:-900x600@60}"
RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SIG_HOST="$(hyprctl instances 2>/dev/null | sed -n 's/^instance \(.*\):$/\1/p' | head -1)"
[ -n "$SIG_HOST" ] || SIG_HOST="${HYPRLAND_INSTANCE_SIGNATURE:-}"
HYPR_DIR="$RT/hypr"
SETTLE_MS="${HYPREXPO_VERIFY_SETTLE_MS:-2000}"
GAP_MS="${HYPREXPO_VERIFY_GAP_MS:-1500}"

mkdir -p "$OUT"
LOG="$OUT/nested.log"

cat > "$OUT/livetest-ticker.sh" <<'EOF'
#!/bin/sh
while :; do date +%s.%N; sleep 0.1; done
EOF
chmod +x "$OUT/livetest-ticker.sh"

nested_pid=""
cleanup() {
    [ -n "$nested_pid" ] && kill "$nested_pid" >/dev/null 2>&1 || true
    pkill -f 'hyprexpo-dev.conf' >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
cleanup
sleep 0.3

echo "[verify-live] launching nested (mode=$MODE)"
HYPREXPO_DEV_3D="${HYPREXPO_DEV_3D:-0}" HYPREXPO_DEV_MODE="$MODE" \
    setsid "$SRC/scripts/run-nested.sh" >"$LOG" 2>&1 </dev/null &
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
if [ -z "$SIG" ]; then
    echo "SUMMARY: FAIL no-nested-ipc"
    exit 1
fi
nested() { HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@"; }
host() { HYPRLAND_INSTANCE_SIGNATURE="$SIG_HOST" hyprctl "$@"; }

plugin_count="$(nested -j plugin list 2>/dev/null | jq 'length' 2>/dev/null)"

# host window geometry
addr=""; geom=""
for _ in $(seq 1 240); do
    addr=$(host -j clients | jq -r '[.[] | select((.class // "") | test("aquamarine|Hyprland"; "i"))][0].address' 2>/dev/null)
    if [ -n "$addr" ] && [ "$addr" != "null" ]; then
        geom=$(host -j clients | jq -r --arg a "$addr" '[.[] | select(.address==$a)][0] | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
        break
    fi
    sleep 0.25
done
if [ -z "$addr" ] || [ "$addr" = "null" ]; then
    echo "SUMMARY: FAIL no-host-window"
    exit 1
fi

host dispatch togglefloating "address:$addr" >/dev/null 2>&1 || true
host dispatch resizewindowpixel "exact 880 560,address:$addr" >/dev/null 2>&1 || true
host dispatch movewindowpixel  "exact 20 20,address:$addr"    >/dev/null 2>&1 || true
sleep 0.4
geom=$(host -j clients | jq -r --arg a "$addr" '[.[] | select(.address==$a)][0] | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
read -r wx wy ww wh <<<"$geom"

# --- ticking terminal on workspace 2, then back to 1 -------------------------
nested dispatch workspace 2 >/dev/null 2>&1 || true
sleep 0.5
nested dispatch exec "kitty --class livetest -e "$OUT/livetest-ticker.sh"" >/dev/null 2>&1 || true
sleep 2.5
nested dispatch workspace 1 >/dev/null 2>&1 || true
sleep 0.8

nested dispatch hyprexpo:expo toggle >/dev/null 2>&1 || true
sleep "$(awk -v ms="$SETTLE_MS" 'BEGIN{printf "%.2f", ms/1000}')"

PNG_A="$OUT/live-a.png"
PNG_B="$OUT/live-b.png"
grim -g "$wx,$wy ${ww}x${wh}" "$PNG_A" 2>"$OUT/grim.err" || { echo "SUMMARY: FAIL grim"; exit 1; }
sleep "$(awk -v ms="$GAP_MS" 'BEGIN{printf "%.2f", ms/1000}')"
grim -g "$wx,$wy ${ww}x${wh}" "$PNG_B" 2>>"$OUT/grim.err" || { echo "SUMMARY: FAIL grim2"; exit 1; }

# Count differing pixels (0 = frozen preview, >0 = something recaptured).
AE="$(compare -metric AE "$PNG_A" "$PNG_B" null: 2>&1 | tr -d '\n')"
alive="no"; kill -0 "$nested_pid" >/dev/null 2>&1 && alive="yes"

verdict="FROZEN"; case "$AE" in 0|0.0) verdict="frozen" ;; *) verdict="live" ;; esac
echo "SUMMARY: nested_alive=$alive plugins=$plugin_count diff_pixels=$AE verdict=$verdict a=$PNG_A b=$PNG_B window=[$geom]"
[ "$verdict" = "live" ] && exit 0 || exit 2
