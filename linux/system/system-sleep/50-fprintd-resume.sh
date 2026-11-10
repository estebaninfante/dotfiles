#!/bin/bash
# Reinicia fprintd al volver de suspensión.
#
# El lock de Omarchy (omarchy.lock / su clon) reintenta pam_fprintd mientras la
# pantalla está bloqueada. Con el lector ELAN 04f3:0c4b (match-on-chip por USB)
# eso termina en transferencias USB que expiran ("bulk_transfer_finish failed:
# transfer timed out"), el sensor trabado y todos los intentos siguientes
# fallando al instante ("device busy", "disabled to prevent overheating", PAM
# code 9). El estado roto vive en el daemon: solo se cura reiniciándolo. Sin
# este hook la huella queda muerta después de cada suspensión y hay que entrar
# con contraseña, que es justo lo que pasaba antes de tenerlo.
#
# systemd-sleep llama con $1 = pre|post y $2 = suspend|hibernate|...

case "${1:-}" in
  post)
    timeout 10 systemctl restart --no-block fprintd 2>/dev/null || true
    ;;
esac

exit 0
