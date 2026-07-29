#!/usr/bin/env bash

SCRIPT_DIRS=(
    "$HOME/.local/bin"
    "$HOME/dotfiles/scripts"
)

if [ -n "$1" ]; then
    for dir in "${SCRIPT_DIRS[@]}"; do
        SCRIPT_PATH="$dir/$1"
if [ -x "$SCRIPT_PATH" ]; then
          if [ "$1" == "rofi-scripts-launcher.sh" ] || \
             [ "$1" == "rofi-file-search.sh" ] || \
             [ "$1" == "rofi-context-menu.sh" ]; then
              exit 0
          fi

          if [ -n "$ROFI_RETV" ] && [ "$ROFI_RETV" -ne 1 ]; then
              coproc ( ~/.local/bin/rofi-context-menu.sh "$SCRIPT_PATH" > /dev/null 2>&1 )
          elif [[ "$SCRIPT_PATH" == "$HOME/dotfiles/scripts/"* ]]; then
              # scripts interactivos: necesitan terminal
              coproc ( kitty -e "$SCRIPT_PATH" )
          else
              coproc ( "$SCRIPT_PATH" )
          fi
            exit 0
        fi
    done
fi

for dir in "${SCRIPT_DIRS[@]}"; do
    [ -d "$dir" ] || continue

    find "$dir" \
        -maxdepth 1 \
        -type f \
        -executable \
        -printf "%f\n"
done | sort -u
