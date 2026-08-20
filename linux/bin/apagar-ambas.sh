#!/usr/bin/env bash
# Shutdown both machines simultaneously.
# SSH to the other machine first, then local shutdown.
# This avoids lan-mouse capturing input when one dies first.
set -euo pipefail

MACHINE="${1:-$(cat ~/.config/machine-type 2>/dev/null || hostname -s)}"

if [[ "$MACHINE" == "laptop" ]]; then
  OTHER="desktop"
else
  OTHER="laptop"
fi

# Confirm via rofi
choice=$(printf "Apagar AMBAS (%s + %s)\nSolo esta maquina" "$MACHINE" "$OTHER" | rofi -dmenu -p "Power Off" -mesg "⚠ Se apagarán ambas máquinas")
case "$choice" in
  *AMBAS*)
    # SSH shutdown to the other machine first
    # shutdown is async on the remote side — command is received and scheduled
    # even if the SSH connection drops when this machine goes down
    notify-send -u critical "Apagando" "Enviando shutdown a $OTHER..."
    ssh "eztvn@$OTHER" "sudo /run/current-system/sw/bin/systemctl poweroff" 2>/dev/null || true
    sleep 2
    # Local shutdown
    systemctl poweroff
    ;;
  *Solo*)
    systemctl poweroff
    ;;
  *)
    exit 0
    ;;
esac
