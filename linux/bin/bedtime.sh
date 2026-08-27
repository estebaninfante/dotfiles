#!/usr/bin/env bash
# Apagado 21:00 (higiene de sueno). Lo dispara systemd.timers.bedtime (20:55).
# Escape puntual: bedtime-skip crea /run/bedtime-skip con la fecha de hoy.
set -euo pipefail

SKIP_FILE=/run/bedtime-skip
TODAY=$(date +%F)
UID_USER=$(id -u eztvn 2>/dev/null || echo 1000)

skip() {
  [ -f "$SKIP_FILE" ] && [ "$(cat "$SKIP_FILE")" = "$TODAY" ]
}

notify() {
  # Aviso a la sesion grafica (si hay bus) + wall a todas las terminales.
  local msg="$1"
  runuser -u eztvn -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_USER/bus" \
    notify-send -u critical "Hora de dormir" "$msg" 2>/dev/null || true
  wall "$msg" || true
}

if skip; then
  echo "bedtime: omitido por flag $SKIP_FILE ($TODAY)"
  exit 0
fi

# Ventana estricta: solo apagar si el disparo ocurre desde 20:55.
# Incluye los 5 min de gracia previos a las 21:00 — un guard de solo hora
# (>=21) mataria el disparo principal de las 20:55. Persistent=true
# compensa triggers perdidos al encender la maquina (ej. 4AM) — este
# guard evita que apague en horario normal de uso.
NOW_MIN=$(date +%H%M)
if [ "$NOW_MIN" -lt 2055 ]; then
  echo "bedtime: fuera de ventana (hora $(date +%H:%M)), sin accion"
  exit 0
fi

notify "Apagado en 5 minutos. Corre 'bedtime-skip' para cancelar."

sleep 300

if skip; then
  notify "Apagado de las 21:00 cancelado."
  exit 0
fi

systemctl poweroff
