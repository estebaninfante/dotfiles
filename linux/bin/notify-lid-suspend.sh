#!/usr/bin/env bash

TOPIC="opencode-laptop"
MESSAGE="Laptop se suspenderá: expiró la protección de tapa (toggle desactivado)."

# Si no hay red, curl falla y suspension continua normalmente.
if curl --fail --silent --show-error --max-time 5 --connect-timeout 2 \
    -X POST "https://ntfy.sh/${TOPIC}" \
    -H "Title: Suspension automatica" \
    -H "Priority: 4" \
    -H "Tags: warning" \
    --data-raw "$MESSAGE" >/dev/null 2>&1; then
    # Give ntfy a moment to deliver before system enters sleep.
    sleep 5
fi
