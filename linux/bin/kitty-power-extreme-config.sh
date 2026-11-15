#!/bin/sh
# geninclude de kitty (ver ~/.config/kitty/kitty.conf).
#
# Con el modo ahorro extremo activo, toda instancia nueva de kitty nace opaca y
# sin blur propio. Las instancias ya abiertas las ajusta en caliente
# power-extreme.sh con `kitten @ set-background-opacity`; para eso hace falta
# dynamic_background_opacity yes, que kitty solo acepta del config del arranque.
flag="${XDG_STATE_HOME:-$HOME/.local/state}/power-extreme/on"
[ -f "$flag" ] && printf 'background_opacity 1.0\nbackground_blur 0\n'
exit 0
