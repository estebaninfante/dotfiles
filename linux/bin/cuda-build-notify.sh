#!/usr/bin/env bash
# Notifica estado del build CUDA cada 15 min en lenguaje natural (local + ntfy).
set -euo pipefail

STATUS_FILE="$HOME/.local/state/dotfiles/cuda-rebuild-status"
LOG_FILE="$HOME/.local/state/dotfiles/cuda-rebuild.log"
MACHINE=$(cat "$HOME/.config/machine-type" 2>/dev/null || echo "desktop")
NTFY_TOPIC="opencode-${MACHINE}"

if [[ ! -f "$STATUS_FILE" ]]; then
    notify-send "CUDA Build" "No hay build en curso"
    exit 0
fi

STATUS=$(grep '^status=' "$STATUS_FILE" | cut -d= -f2)
START=$(grep '^start=' "$STATUS_FILE" | cut -d= -f2)
ATTEMPT=$(grep '^attempt=' "$STATUS_FILE" | cut -d= -f2)

if [[ "$STATUS" != "running" ]]; then
    notify-send "CUDA Build" "Build terminó o falló (status=$STATUS)"
    exit 0
fi

# Datos
BUILDING_COUNT=$(grep -c "^building " "$LOG_FILE" 2>/dev/null || echo 0)
LAST_RAW=$(grep "^building " "$LOG_FILE" 2>/dev/null | tail -1)
LAST_DRV=$(echo "$LAST_RAW" | sed "s|building '/nix/store/||;s|\.drv'...||")

# Qué se está compilando ahora
COMPILERS=$(ps -ef | grep -E "cc1plus|nvcc|cicc|rustc|clang" | grep -v grep | wc -l)
IS_FIREFOX=$(echo "$LAST_RAW" | grep -c "firefox" || true)
IS_PYTORCH=$(echo "$LAST_RAW" | grep -c "torch\|pytorch" || true)
IS_NCCL=$(echo "$LAST_RAW" | grep -c "nccl" || true)
IS_CUDNN=$(echo "$LAST_RAW" | grep -c "cudnn" || true)
IS_OPENCV=$(echo "$LAST_RAW" | grep -c "opencv" || true)
IS_MAGMA=$(echo "$LAST_RAW" | grep -c "magma" || true)

# Tiempo
START_EPOCH=$(date -d "$START" +%s 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
ELAPSED=$(( (NOW_EPOCH - START_EPOCH) / 60 ))
HOURS=$((ELAPSED / 60))
MINS=$((ELAPSED % 60))

# Carga y RAM
LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs | cut -d, -f1 | xargs)
RAM_USED=$(free -h | awk '/^Mem:/{print $3}')
RAM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')

# nixos-rebuild alive?
NIX_ALIVE="no"
pgrep -f "nixos-rebuild" > /dev/null 2>&1 && NIX_ALIVE="yes"

# Componer mensaje natural
if [[ "$COMPILERS" -eq 0 && "$NIX_ALIVE" == "no" ]]; then
    TITLE="Build CUDA posiblemente terminó"
    MSG="Lleva ${HOURS}h${MINS}min corriendo. No hay procesos de compilación ni nixos-rebuild activos. Puede haber terminado exitosamente o haber caído. Revisa la terminal."
elif [[ "$COMPILERS" -eq 0 && "$NIX_ALIVE" == "yes" ]]; then
    TITLE="Build CUDA — carga baja"
    MSG="Lleva ${HOURS}h${MINS}min. nixos-rebuild sigue vivo pero no hay compiladores activos ahora. Puede estar en linking, descargando, o esperando al daemon. Carga: ${LOAD}."
else
    # Determinar qué se compila
    if [[ "$IS_FIREFOX" -gt 0 ]]; then
        PAQUETE="Firefox (PGO —optimización guiada por perfil, lento por diseño)"
    elif [[ "$IS_PYTORCH" -gt 0 ]]; then
        PAQUETE="PyTorch con CUDA — miles de kernels GPU"
    elif [[ "$IS_NCCL" -gt 0 ]]; then
        PAQUETE="NCCL — comunicaciones GPU multi-nodo"
    elif [[ "$IS_CUDNN" -gt 0 ]]; then
        PAQUETE="cuDNN — primitivas deep learning para GPU"
    elif [[ "$IS_OPENCV" -gt 0 ]]; then
        PAQUETE="OpenCV — visión artificial"
    elif [[ "$IS_MAGMA" -gt 0 ]]; then
        PAQUETE="MAGMA — álgebra lineal GPU"
    else
        PAQUETE="compilación genérica"
    fi

    TITLE="Build CUDA — ${PAQUETE}"
    MSG="Lleva ${HOURS}h${MINS}min. ${COMPILERS} procesos compilando ${PAQUETE}. Carga: ${LOAD}. RAM: ${RAM_USED}/${RAM_TOTAL}. Todo normal."
fi

# Enviar
notify-send -u normal -t 15000 "$TITLE" "$MSG"
curl -s -o /dev/null \
    -H "Title: $TITLE" \
    -H "Priority: low" \
    -H "Tags: wrench" \
    -d "$MSG" \
    "https://ntfy.sh/${NTFY_TOPIC}"
