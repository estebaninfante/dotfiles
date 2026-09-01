#!/usr/bin/env bash

# Producer del modo "Archivos" del launcher (quickshell).
# Escanea $HOME incluyendo ~/.config, filtrando cachés pesadas.
# Ejecutables (scripts) primero, luego directorios, resto de archivos.
# Salida por línea (TSV, sin markup):
#   name<TAB>path<TAB>dirreal<TAB>disdir<TAB>isDir<TAB>isExec

HEAVY_DIRS=(Cache GPUCache node_modules __pycache__ venv .venv target dist \
    .git .cache .local keyd libinput-gestures anyrun avizo build contrib \
    "Crash Reports" google-chrome BraveSoftware)

prune_args=()
for d in "${HEAVY_DIRS[@]}"; do
    prune_args+=( -name "$d" -prune -o )
done

emit() {
    # $1 isDir, $2 isExec, resto = predicados find
    local isDir="$1" isExec="$2"
    shift 2
    find "$HOME" \
        -maxdepth 6 \
        "${prune_args[@]}" \
        "$@" \
        \( -not -path '*/.*' -o -path "$HOME/.config*" \) 2>/dev/null | \
        awk -v isDir="$isDir" -v isExec="$isExec" -v home="$HOME" '
$0 != home {
    path = $0
    n = split(path, parts, "/")
    name = parts[n]
    dir = substr(path, 1, length(path) - length(name) - 1)
    disp = dir
    sub("^" home, "~", disp)
    if (disp == "") disp = "~"
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", name, path, dir, disp, isDir, isExec
}'
}

emit 0 1 ! -type d -perm /111
emit 1 0 -type d
emit 0 0 -type f ! -perm /111