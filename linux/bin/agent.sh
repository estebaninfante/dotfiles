#!/usr/bin/env bash

# Script para ejecutar tu Agente Autónomo con modelo DeepSeek en OpenRouter
# Estética e interfaz optimizada estilo Antigravity

KEY_FILE="$HOME/.config/openrouter_key"
VENV_BIN="$HOME/.local/share/agents-venv/bin"

if [ -f "$KEY_FILE" ]; then
    export OPENROUTER_API_KEY=$(cat "$KEY_FILE" | tr -d '\r\n ')
fi

if [ -z "$OPENROUTER_API_KEY" ]; then
    echo -e "\033[1;31m=============================================\033[0m"
    echo -e "\033[1;37m🤖 CONFIGURACIÓN DEL AGENTE (DEEPSEEK / OPENROUTER)\033[0m"
    echo -e "\033[1;31m=============================================\033[0m"
    echo "No se encontró tu API Key de OpenRouter."
    echo ""
    read -sp "Por favor pega tu OPENROUTER_API_KEY aquí: " user_key
    echo ""
    if [ -n "$user_key" ]; then
        mkdir -p "$HOME/.config"
        echo "$user_key" > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        export OPENROUTER_API_KEY="$user_key"
        echo -e "\033[1;32m✅ API Key guardada en $KEY_FILE\033[0m"
    else
        echo -e "\033[1;31m❌ No se ingresó ninguna clave. Saliendo...\033[0m"
        read -p "Presiona Enter para cerrar."
        exit 1
    fi
fi

# Banner Estilo Antigravity
clear
echo -e "\033[1;31m"
echo "  ▲  ANTIGRAVITY AGENTIC CLI  ▲  "
echo "============================================="
echo -e "\033[0m\033[1;37m Model: \033[1;33mDeepSeek (OpenRouter)\033[0m"
echo -e "\033[1;37m Engine: \033[1;31mOpen Interpreter Core\033[0m"
echo -e "\033[1;31m=============================================\033[0m"
echo ""

# Ejecutar el agente con DeepSeek en OpenRouter
"$VENV_BIN/interpreter" \
    --model openrouter/deepseek/deepseek-chat \
    --custom_instructions "Eres Antigravity Agent, un asistente de programación agentico avanzado creado para ayudar en la terminal. Responde en español, sé directo, ejecuta herramientas y comandos de forma segura." \
    "$@"
