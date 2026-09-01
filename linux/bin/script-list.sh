#!/usr/bin/env bash

# Producer del modo "Scripts" del launcher (quickshell).
# Lista scripts del usuario desde los directorios canónicos.
# Salida por línea (TSV):
#   name<TAB>path

SCRIPT_DIRS=(
    "$HOME/.local/bin"
    "$HOME/dotfiles/scripts"
    "$HOME/dotfiles/linux"
    "$HOME/dotfiles/linux/bin"
    "$HOME/dotfiles/bin"
)

for dir in "${SCRIPT_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 1 -type f \( -executable -o -name "*.sh" \) -printf "%f\t%p\n"
done | sort -u