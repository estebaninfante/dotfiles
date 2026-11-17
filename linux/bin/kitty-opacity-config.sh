#!/bin/sh
# geninclude de kitty (ver ~/.config/kitty/kitty.conf).
#
# Desconectado (batería), toda instancia nueva de kitty nace opaca y sin blur
# propio. Las instancias ya abiertas las ajusta kitty-opacity.sh en caliente;
# para eso hace falta dynamic_background_opacity yes, que kitty solo acepta del
# config del arranque.
#
# Solo batería: el perfil power-saver ("modo silencioso") está activo también
# con AC, y ahí la terminal conserva su transparencia.
on_battery() {
    for p in /sys/class/power_supply/*/online; do
        [ -f "$p" ] || continue
        case "$p" in */BAT*) continue ;; esac
        [ "$(cat "$p" 2>/dev/null)" = "1" ] && return 1
    done
    return 0
}

if on_battery; then
    printf 'background_opacity 1.0\nbackground_blur 0\n'
fi
exit 0
