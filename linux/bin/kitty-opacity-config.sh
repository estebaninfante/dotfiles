#!/bin/sh
# geninclude de kitty (ver ~/.config/kitty/kitty.conf).
#
# Desconectado (batería) o con perfil power-saver, toda instancia nueva de kitty
# nace opaca y sin blur propio. Las instancias ya abiertas las ajusta
# kitty-opacity.sh en caliente; para eso hace falta dynamic_background_opacity
# yes, que kitty solo acepta del config del arranque.
#
# El criterio es el mismo que hypr/base/power.lua y power-session-guard.sh:
# low_power = batería O perfil power-saver.
on_battery() {
    for p in /sys/class/power_supply/*/online; do
        [ -f "$p" ] || continue
        case "$p" in */BAT*) continue ;; esac
        [ "$(cat "$p" 2>/dev/null)" = "1" ] && return 1
    done
    return 0
}

power_saver() {
    v="$(busctl get-property org.freedesktop.UPower.PowerProfiles \
        /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles \
        ActiveProfile 2>/dev/null | cut -d'"' -f2)"
    [ "$v" = "power-saver" ]
}

if on_battery || power_saver; then
    printf 'background_opacity 1.0\nbackground_blur 0\n'
fi
exit 0
