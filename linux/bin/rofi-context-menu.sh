#!/usr/bin/env bash

# Script de menú contextual para Rofi

target="$1"
if [ -z "$target" ]; then exit 0; fi

basename=$(basename "$target")
dirname=$(dirname "$target")

if [ -d "$target" ]; then
    options="📂 Abrir carpeta en Gestor de Archivos\n💻 Abrir carpeta en Terminal (Kitty)\n📝 Abrir carpeta en Neovim\n📋 Copiar ruta al portapapeles"
else
    options="📄 Abrir archivo con aplicación por defecto"
    if [ -x "$target" ]; then
        options+="\n🚀 Ejecutar script"
    fi
    options+="\n💻 Abrir carpeta contenedora en Terminal (Kitty)\n📁 Mostrar carpeta en Gestor de Archivos\n📝 Abrir archivo en Neovim\n📋 Copiar ruta al portapapeles"
fi

choice=$(echo -e "$options" | rofi -dmenu -p "Opciones: $basename" -theme-str 'window { width: 500px; }')

case "$choice" in
    "📂 Abrir carpeta en Gestor de Archivos"|"📁 Mostrar carpeta en Gestor de Archivos")
        if [ -d "$target" ]; then
            coproc ( xdg-open "$target" > /dev/null 2>&1 )
        else
            coproc ( xdg-open "$dirname" > /dev/null 2>&1 )
        fi
        ;;
    "💻 Abrir carpeta en Terminal (Kitty)"|"💻 Abrir carpeta contenedora en Terminal (Kitty)")
        if [ -d "$target" ]; then
            coproc ( kitty -d "$target" > /dev/null 2>&1 )
        else
            coproc ( kitty -d "$dirname" > /dev/null 2>&1 )
        fi
        ;;
    "📝 Abrir carpeta en Neovim"|"📝 Abrir archivo en Neovim")
        if [ -d "$target" ]; then
            coproc ( kitty -d "$target" -e nvim . > /dev/null 2>&1 )
        else
            coproc ( kitty -d "$dirname" -e nvim "$target" > /dev/null 2>&1 )
        fi
        ;;
    "📄 Abrir archivo con aplicación por defecto")
        coproc ( xdg-open "$target" > /dev/null 2>&1 )
        ;;
    "🚀 Ejecutar script")
        coproc ( "$target" > /dev/null 2>&1 )
        ;;
    "📋 Copiar ruta al portapapeles")
        if command -v wl-copy >/dev/null 2>&1; then
            echo -n "$target" | wl-copy
        else
            echo -n "$target" | xclip -selection clipboard
        fi
        ;;
esac
