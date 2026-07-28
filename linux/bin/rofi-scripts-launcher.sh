#!/usr/bin/env bash

# Rofi launcher para los scripts ejecutables del usuario en ~/.local/bin

SCRIPTS_DIR="$HOME/.local/bin"

if [ -n "$1" ]; then
    if [ "$1" == "rofi-scripts-launcher.sh" ] || [ "$1" == "rofi-file-search.sh" ]; then
        exit 0
    fi

    SCRIPT_PATH="$SCRIPTS_DIR/$1"
    if [ -x "$SCRIPT_PATH" ]; then
        # Si el usuario presionó Shift+Enter (ROFI_RETV != 1)
        if [ -n "$ROFI_RETV" ] && [ "$ROFI_RETV" -ne 1 ]; then
            coproc ( ~/.local/bin/rofi-context-menu.sh "$SCRIPT_PATH" > /dev/null 2>&1 )
            exit 0
        else
            coproc ( "$SCRIPT_PATH" > /dev/null 2>&1 )
            exit 0
        fi
    fi
fi

if [ -d "$SCRIPTS_DIR" ]; then
    find "$SCRIPTS_DIR" -maxdepth 1 -type f -executable -not -name "rofi-*" -printf "%f\n" 2>/dev/null | sort
fi
