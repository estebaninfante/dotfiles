#!/usr/bin/env bash

# Producer del modo "Aplicaciones" del launcher (quickshell, paridad con
# rofi drun). Escanea *.desktop en los directorios canónicos.
# Salida por línea (TSV):
#   name<TAB>exec<TAB>icon
# - Omitidos: NoDisplay=true, Hidden=true, sin Name o sin Exec.
# - Exec sin field codes (%f %F %u %U ...) — el launcher los correría tal cual.

apps_dirs=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    "$HOME/.local/share/flatpak/exports/share/applications"
)
IFS=: read -ra share_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for s in "${share_dirs[@]}"; do
    apps_dirs+=("$s/applications")
done

{
    for dir in "${apps_dirs[@]}"; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null
    done
} | LC_ALL=C sort -u | awk -F= '
function clean_exec(s) {
    gsub(/%[fFuUdDnNickvm]/, "", s)
    gsub(/ +$/, "", s)
    return s
}
BEGIN { inEntry = 0; name = ""; exec = ""; icon = ""; skip = 0 }
/^\[/ {
    if (inEntry && !skip && name != "" && exec != "")
        printf "%s\t%s\t%s\n", name, clean_exec(exec), icon
    inEntry = ($0 ~ /^\[Desktop Entry\]/)
    name = ""; exec = ""; icon = ""; skip = 0
    next
}
inEntry && !skip {
    if ($0 ~ /^Name=/ && name == "") name = substr($0, 6)
    else if ($0 ~ /^Exec=/) exec = substr($0, 6)
    else if ($0 ~ /^Icon=/) icon = substr($0, 6)
    else if ($0 ~ /^NoDisplay=true/) skip = 1
    else if ($0 ~ /^Hidden=true/) skip = 1
}
END {
    if (inEntry && !skip && name != "" && exec != "")
        printf "%s\t%s\t%s\n", name, clean_exec(exec), icon
}' | LC_ALL=C sort -f