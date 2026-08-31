#!/bin/sh
# PATH fijo: systemd/NM ejecutan con entorno mínimo y NixOS no tiene
# /bin/bash; los binarios viven en /run/current-system/sw/bin.
export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH"
# Ensure de la IP KVM flotante y de la ruta simetrica al peer.
# Fuente de verdad de la logica KVM; la usa el dispatcher NM (source) y
# un timer systemd (ejecucion directa, safety net ante eventos perdidos).
#
# Que hace:
# - Elige la interfaz KVM: ethernet de casa (IP dentro de 192.168.1.0/24),
#   si no WiFi de casa sin importar el nombre del device (el dock USB
#   ethernet se re-enumera como enp5s0f3u1 / enp5s0f3u2).
# - Asegura que la IP KVM (laptop .240 / desktop .241) viva SOLO en esa
#   interfaz (la quita de las demas).
# - Instala ruta simetrica `PEER_IP/32 dev IFACE src KVM_IP`: las respuestas
#   hacia el peer salen con la IP KVM aunque esta sea secondary. Sin esto,
#   con dos IPs en el mismo subnet (DHCP + KVM estatica), las respuestas
#   salen con la source DHCP → "Connection timed out" (routing asimetrico
#   + rp_filter estricto). El firewall debe tener checkReversePath = "loose".
#
# IPs estaticas (fuera del pool DHCP): laptop 192.168.1.240, desktop 192.168.1.241

WIFI_IF="wlo1"
HOME_SSIDS=("Familia_Infante_PLUS" "Familia Villamil" "Familia Villamil 1")
USER="eztvn"

case "$(hostname)" in
    laptop) LAN_IP="192.168.1.240" ; KVM_IP="192.168.1.240" ; PEER_IP="192.168.1.241" ;;
    desktop) LAN_IP="192.168.1.241" ; KVM_IP="192.168.1.241" ; PEER_IP="192.168.1.240" ;;
    *) exit 0 ;;
esac

# ¿la IP a.b.c.d está dentro de 192.168.1.0/24?
ipaddr_in_home_subnet() {
    local ip="${1%%/*}"
    [ "$(echo "$ip" | cut -d. -f1)" = "192" ] && \
    [ "$(echo "$ip" | cut -d. -f2)" = "168" ] && \
    [ "$(echo "$ip" | cut -d. -f3)" = "1" ]
}

# Interfaz ethernet conectada a la red de casa (IP dentro del subnet KVM 192.168.1.0/24).
home_ethernet_iface() {
    local iface ip
    for iface in /sys/class/net/*; do
        iface="${iface##*/}"
        [ "$iface" = "$WIFI_IF" ] && continue
        nmcli -g GENERAL.TYPE device show "$iface" 2>/dev/null | grep -q '^ethernet$' || continue
        ip=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/ inet /{print $2}')
        if [ -n "$ip" ] && ipaddr_in_home_subnet "$ip"; then
            echo "$iface"
            return 0
        fi
    done
    return 1
}

# WiFi conectado a red de casa (sustituto cuando no hay ethernet).
home_wifi_up() {
    [ -d "/sys/class/net/$WIFI_IF" ] || return 1
    local conn
    conn=$(nmcli -t -f NAME,DEVICE connection show --active \
        | awk -F: -v d="$WIFI_IF" '$2 == d {print $1}')
    for home in "${HOME_SSIDS[@]}"; do
        if [ "$conn" = "$home" ]; then
            return 0
        fi
    done
    return 1
}

restart_lan_mouse() {
    local uid
    uid=$(id -u "$USER" 2>/dev/null) || return 1
    # Asíncrono + timeout: en desktop el stop de lan-mouse puede tardar ~90s
    # (KVM con sesión activa); no debe bloquear dispatcher ni timer.
    su "$USER" -c "XDG_RUNTIME_DIR=/run/user/$uid timeout 20 systemctl --user restart lan-mouse.service" >/dev/null 2>&1 </dev/null &
}

# Idempotente. Return 0 = sin cambios; 1 = hubo cambios (conviene restart).
ensure_kvm() {
    local iface changed=0
    iface=$(home_ethernet_iface)
    [ -z "$iface" ] && home_wifi_up && iface="$WIFI_IF"
    [ -z "$iface" ] && return 0

    # 1. IP KVM en la interfaz elegida (si falta).
    if ! ip -4 addr show dev "$iface" 2>/dev/null | grep -q " $KVM_IP/"; then
        ip addr add "$KVM_IP/24" dev "$iface" 2>/dev/null && changed=1
    fi

    # 2. Quitar la IP KVM de las demás interfaces (evita doble dirección
    #    en el mismo subnet → routing asimétrico).
    for other in /sys/class/net/*; do
        other="${other##*/}"
        [ "$other" = "$iface" ] && continue
        [ -d "/sys/class/net/$other" ] || continue
        if ip -4 addr show dev "$other" 2>/dev/null | grep -q " $KVM_IP/"; then
            ip addr del "$KVM_IP/24" dev "$other" 2>/dev/null && changed=1
        fi
    done

    # 3. Ruta simétrica: al peer se llega por la interfaz KVM y con src KVM_IP.
    if ! ip route show "$PEER_IP/32" 2>/dev/null | grep -q "dev $iface"; then
        ip route replace "$PEER_IP/32" dev "$iface" src "$KVM_IP" 2>/dev/null && changed=1
    fi

    return "$changed"
}

# Ejecucion directa (timer): asegurar y reiniciar lan-mouse solo si cambió.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if ! ensure_kvm; then
        restart_lan_mouse
    fi
    exit 0
fi