#!/usr/bin/env bash

# Waybar custom module: keyboard layout (dvk_prog <-> es)
# Click toggles via hyprctl switchxkblayout <main-device> next

main_device() {
    hyprctl devices -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); k=[x for x in d.get('keyboards',[]) if x.get('main')]; print(k[0]['name'] if k else '')"
}

active_index() {
    hyprctl devices -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); k=[x for x in d.get('keyboards',[]) if x.get('main')]; print(k[0].get('active_layout_index',0) if k else 0)"
}

toggle() {
    local dev
    dev=$(main_device)
    [ -z "$dev" ] && return 1
    hyprctl switchxkblayout "$dev" next >/dev/null 2>&1
}

emit() {
    local idx
    idx=$(active_index)
    if [ "$idx" = "1" ]; then
        echo '{"text":"ES","tooltip":"Layout: Español (clic para cambiar a dvk_prog)","class":"es"}'
    else
        echo '{"text":"DVK","tooltip":"Layout: Dvorak Programador Español (clic para cambiar a ES)","class":"dvk"}'
    fi
}

if [ "${1:-}" = "toggle" ]; then
    toggle
    exit 0
fi

while true; do
    emit
    sleep 1
done
