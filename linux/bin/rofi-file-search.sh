#!/usr/bin/env bash

# Rofi Everything/FlowLauncher file searcher - Includes ~/.config & Auto Neovim for text/code files

target="${ROFI_INFO:-$1}"

if [ -n "$target" ] && [ -e "$target" ]; then
    # Si presiona Shift+Enter o Alt+Enter en Rofi, abrir menú contextual
    if [ -n "$ROFI_RETV" ] && [ "$ROFI_RETV" -ne 1 ]; then
        coproc ( ~/.local/bin/rofi-context-menu.sh "$target" > /dev/null 2>&1 )
        exit 0
    else
        # Enter normal: si es un directorio, abrirlo con el gestor de archivos
        if [ -d "$target" ]; then
            coproc ( xdg-open "$target" > /dev/null 2>&1 )
            exit 0
        fi

        # Si es un archivo de código o texto, abrirlo automáticamente en Neovim con Kitty
        case "$target" in
            *.py|*.sh|*.lua|*.json|*.conf|*.md|*.txt|*.js|*.ts|*.tsx|*.jsx|*.html|*.css|*.rasi|*.yaml|*.toml|*.zsh|*.bash|*.env|*.ini|*.sql|*.lock|*.csv|*.xml)
                dirname=$(dirname "$target")
                coproc ( kitty -d "$dirname" -e nvim "$target" > /dev/null 2>&1 )
                exit 0
                ;;
            *)
                coproc ( xdg-open "$target" > /dev/null 2>&1 )
                exit 0
                ;;
        esac
    fi
fi

echo -en "\0markup-rows\x1ftrue\n"

# Escanear $HOME e incluir ~/.config (filtrando cachés del sistema)
find "$HOME" \
    -maxdepth 6 \
    \( -not -path '*/.*' -o -path "$HOME/.config*" \) 2>/dev/null | \
    grep -v -E "/(Cache|GPUCache|node_modules|__pycache__|venv|\.venv|target|dist|\.git|\.cache|\.local|keyd|libinput-gestures|anyrun|avizo|build|contrib|Crash Reports|google-chrome|BraveSoftware)/" | \
    awk -v home="$HOME" '
$0 != home {
    path = $0
    n = split(path, parts, "/")
    filename = parts[n]
    dir = substr(path, 1, length(path) - length(filename) - 1)
    sub("^" home, "~", dir)
    if (dir == "") dir = "~"
    printf "%s  <span foreground=\"#888888\" size=\"small\">%s</span>\0info\x1f%s\n", filename, dir, path
}'
