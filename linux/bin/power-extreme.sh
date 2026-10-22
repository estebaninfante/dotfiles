#!/usr/bin/env bash
# power-extreme.sh — modo de ahorro extremo para batería.
#
# Apaga TODO servicio de fondo que no sea imprescindible para la sesión o para
# entrar por SSH: modelos locales (RAM/VRAM a cero), voz, KVM/streaming, agentes
# y servidores, timers periódicos, impresión, docker, bluetooth. Pone
# power-saver, brillo 25 %, luz del teclado apagada, pantalla 60 s y libera las
# cachés del kernel. Solo quedan: Tailscale, sshd, red, sesión gráfica, entrada
# y los servicios del sistema.
#
# Al enchufar el cargador se sale solo (power-session-guard.service llama `off`).
#
# Uso:
#   power-extreme.sh on|off|toggle|status
#   power-extreme.sh on --auto    no falla si está con corriente
#
# POWER_EXTREME_KEEP_SEAT=1 conserva la silla del agente (rig-main-seat) en vez
# de matarla. Sirve para pruebas y para quien quiera seguir hablando con el
# agente mientras el modo está activo.
#
# Documentación: docs/energia-laptop-82y5.md §8
# Verificación:  scripts/verify/energia.sh
set -uo pipefail

BIN_DIR="$HOME/.local/bin"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/power-extreme"
FLAG="$STATE_DIR/on"
RUNNING="$STATE_DIR/services.running"
TIMERS_ON="$STATE_DIR/timers.running"
SYSTEM_ON="$STATE_DIR/system.running"
BRIGHT_SAVE="$STATE_DIR/brightness"
LED_SAVE="$STATE_DIR/kbd-led"
IDLE_SAVE="$STATE_DIR/idle"
HYPR_SAVE="$STATE_DIR/hypr"
VOICE_DROPIN="$HOME/.config/systemd/user/voice-daemon.service.d/extreme-cpu.conf"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
KBD_LED="/sys/class/leds/platform::kbd_backlight"
BRIGHT_PCT=25
IDLE_SCREENSAVER=60 # antes 150
IDLE_LOCK=180       # antes 300

# ── qué se apaga ──────────────────────────────────────────────────────────
# Servicios de usuario. NO incluir acá lo que sostiene la sesión, la entrada o
# la red/SSH: pipewire/wireplumber (los reactiva el socket si algo pide audio),
# omarchy-shell, omarchy-sleep-lock, hypridle, hyprpolkitagent,
# omarchy-fcitx5, omarchy-recover-internal-monitor, gnome-keyring (agente SSH),
# dbus, power-session-guard y NetworkManager.
STOP_USER_UNITS=(
  # voz de entrada y modelos locales (lo más caro: micrófono + CUDA)
  omar-listen.service omar-whisper.service omar-pill.service
  omar-surface.service omar-glow.service
  voice-key-listener.service voice-pi-shim.service
  kokoro-tts.service ollama.service
  # KVM, streaming y escritorio remoto
  lan-mouse.service lan-mouse-auto.service sunshine.service
  weylus.service weylus-tablet.service
  hypr-remote.service hypr-outline.service present-remote.service
  # agentes y servidores de desarrollo (incluida la silla del agente: sin ella
  # no queda ningún agente vivo, que es justo lo que pide el modo; para
  # conservarla, POWER_EXTREME_KEEP_SEAT=1)
  rig-main-seat.service rig-discord-bot.service rig-telegram-bot.service
  dsh-web.service agentes-platform-main.service
  agentes-platform-developing.service zentro-developing.service
  openclaw-gateway.service speeedy.service vision-gui.service
  ohm.service foldertinder.service omarchy-crash-watch.service
  airbnb-trip-compare.service talk-command.service
  # audio de micrófono procesado, entrada e input automation
  mic-bt-fx.service mic-gain.service audio-jack-guard.service
  ydotoold.service mnt-blackmagic.service
  # salida de voz (deja avisos sonoros apagados; queda el aviso de escritorio)
  voice-daemon.service omarchy-migrate-notify.service
)

# Escape para pruebas o para conservar el agente mientras el modo está activo.
if [ "${POWER_EXTREME_KEEP_SEAT:-0}" = "1" ]; then
  _keep=()
  for _u in "${STOP_USER_UNITS[@]}"; do
    [ "$_u" = "rig-main-seat.service" ] || _keep+=("$_u")
  done
  STOP_USER_UNITS=("${_keep[@]}")
  unset _keep _u
fi

# Timers y paths: son los que despiertan la CPU cada pocos minutos (el de
# wallpaper corre cada 20 s).
STOP_TIMERS=(
  wallpaper-power-guard.timer dev-sync.timer dotfiles-sync.timer
  ai-chats-sync.timer harness-research.timer res-budget.timer
  res-reap.timer rig-db-sync.timer tmux-reap.timer lan-mouse-auto.timer
)
STOP_PATHS=(ai-chats-ingest.path lan-mouse-sync.path)

# Servicios del sistema. No se tocan red (NetworkManager, tailscaled, sshd),
# logind, udev ni lo que sostiene la sesión.
STOP_SYSTEM_UNITS=(
  syncthing@eztvn.service cups.service avahi-daemon.service
  docker.service docker.socket bluetooth.service
)

# ── helpers ───────────────────────────────────────────────────────────────
log() { logger -t power-extreme -- "$*" 2>/dev/null || true; }

notify() { # notify <título> <cuerpo>
  if [ -x "$BIN_DIR/notify" ]; then
    "$BIN_DIR/notify" -g "󰂄" -u low --app-name Energia "$1" "$2" >/dev/null 2>&1 || true
  else
    notify-send "$1" "$2" >/dev/null 2>&1 || true
  fi
}

on_battery() {
  local p
  for p in /sys/class/power_supply/*/online; do
    [ -f "$p" ] || continue
    case "$p" in */BAT*) continue ;; esac
    [ "$(cat "$p" 2>/dev/null)" = "1" ] && return 1
  done
  return 0
}

is_on() { [ -f "$FLAG" ]; }

have_root() { sudo -n true 2>/dev/null; }

bt_has_device() {
  command -v bluetoothctl >/dev/null 2>&1 || return 1
  timeout 3 bluetoothctl devices Connected 2>/dev/null | grep -q '^Device '
}

read_list() { [ -f "$1" ] && grep -v '^$' "$1" || true; }

# ── brillo / LED / idle ───────────────────────────────────────────────────
br_get() { sudo -n brightnessctl --class=backlight get 2>/dev/null; }
br_max() { sudo -n brightnessctl --class=backlight max 2>/dev/null; }
br_set() { sudo -n brightnessctl --class=backlight set "$1" >/dev/null 2>&1; }

led_save() {
  [ -r "$KBD_LED/brightness" ] || return 0
  cat "$KBD_LED/brightness" >"$LED_SAVE" 2>/dev/null || true
}
led_set() {
  [ -e "$KBD_LED/brightness" ] || return 0
  # sysfs es de root: no alcanza con [ -w ] como usuario; se intenta con sudo.
  echo "$1" | sudo -n tee "$KBD_LED/brightness" >/dev/null 2>&1 || true
}

# Guarda y fija los timeouts de idle de omarchy-shell (shell.json, recarga en
# caliente). Se toca solo el bloque "idle" para no reformatear el archivo.
idle_save() {
  [ -f "$SHELL_JSON" ] || return 0
  python3 - "$SHELL_JSON" >"$IDLE_SAVE" <<'PY' 2>/dev/null || true
import json, re, sys
t = open(sys.argv[1]).read()
m = re.search(r'"idle"\s*:\s*\{[^}]*\}', t)
if m:
    b = m.group(0)
    s = re.search(r'"screensaver"\s*:\s*(\d+)', b)
    l = re.search(r'"lock"\s*:\s*(\d+)', b)
    print(s.group(1) if s else "", l.group(1) if l else "")
PY
}

idle_set() { # idle_set <screensaver> <lock>
  [ -f "$SHELL_JSON" ] || return 0
  python3 - "$SHELL_JSON" "$1" "$2" <<'PY' 2>/dev/null || true
import re, sys
p, s, l = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(p).read()
m = re.search(r'"idle"\s*:\s*\{[^}]*\}', t)
if not m:
    raise SystemExit(0)
b = re.sub(r'("screensaver"\s*:\s*)\d+', r'\g<1>' + s, m.group(0))
b = re.sub(r'("lock"\s*:\s*)\d+', r'\g<1>' + l, b)
open(p, 'w').write(t[:m.start()] + b + t[m.end():])
PY
}

idle_restore() {
  local s l
  [ -f "$IDLE_SAVE" ] || return 0
  read -r s l <"$IDLE_SAVE" || true
  [ -n "${s:-}" ] && [ -n "${l:-}" ] && idle_set "$s" "$l"
}

# ── barra y compositor ────────────────────────────────────────────────────
# Widgets de la barra que sondean o animan sin parar. Se pausan por IPC; si la
# barra arranca con el modo activo, cada widget lee el flag y arranca pausado.
#   eztvn.wave         cava a 60 fps: quickshell redibuja siempre
#   eztvn.mic          parec con el micrófono abierto + pactl cada segundo
#   eztvn.hypr-outline bash + 2 curl cada 350 ms contra hypr-remote (parado)
#   eztvn.modo-voz     CLI `voice` (Python) cada 2 s; la voz está parada
#   eztvn.pi-tts       ídem
#   services           LED que pulsa en bucle con servicios caídos (lo están
#                      a propósito) + sondeo cada 3 s → cada 60 s
#   eztvn.cpu-heatmap  script + animación cada 1 s → cada 10 s
#   vm.sysmem          script + nvidia-smi cada 2 s → cada 10 s
SHELL_WIDGETS=(eztvn.wave eztvn.mic eztvn.hypr-outline eztvn.modo-voz eztvn.pi-tts
  services eztvn.cpu-heatmap vm.sysmem)
shell_widgets() { # shell_widgets pause|resume
  local w
  command -v qs >/dev/null 2>&1 || return 0
  for w in "${SHELL_WIDGETS[@]}"; do
    timeout 3 qs ipc -n -p "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
      call "$w" "$1" >/dev/null 2>&1 || true
  done
}

# Animaciones, sombras y blur del compositor: cada animación son decenas de
# frames a 60 Hz. Se guardan los valores para devolverlos exactos (no se usa
# `hyprctl reload`: volvería a correr el autostart).
hypr_get() { hyprctl getoption "$1" 2>/dev/null | awk '/^bool:/{print $2; exit}'; }
hypr_lite_on() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  printf '%s %s %s\n' "$(hypr_get animations:enabled)" \
    "$(hypr_get decoration:shadow:enabled)" "$(hypr_get decoration:blur:enabled)" >"$HYPR_SAVE"
  hyprctl eval 'hl.config({animations={enabled=false}, decoration={shadow={enabled=false}, blur={enabled=false}}})' \
    >/dev/null 2>&1 || true
}
hypr_lite_off() {
  local a s b
  [ -f "$HYPR_SAVE" ] || return 0
  read -r a s b <"$HYPR_SAVE" || true
  [ -n "${a:-}" ] && [ -n "${s:-}" ] && [ -n "${b:-}" ] || return 0
  hyprctl eval "hl.config({animations={enabled=$a}, decoration={shadow={enabled=$s}, blur={enabled=$b}}})" \
    >/dev/null 2>&1 || true
}

# La dGPU solo suspende si nadie tiene /dev/nvidia* abierto. Hyprland la abre al
# arrancar y no la suelta en caliente; env.lua la deja fuera cuando la sesión
# arranca con el modo activo, así que hace falta cerrar sesión y volver a entrar.
dgpu_held() {
  local gpu=/sys/bus/pci/devices/0000:01:00.0/power/runtime_status
  [ -r "$gpu" ] && [ "$(cat "$gpu")" = "active" ] &&
    sudo -n fuser /dev/nvidia0 /dev/nvidiactl >/dev/null 2>&1
}

# ── voz en CPU ────────────────────────────────────────────────────────────
# Sin esto, el primer aviso hablado arranca Kokoro en CUDA y deja la dGPU
# despierta el resto de la sesión. Con CUDA_VISIBLE_DEVICES vacío, torch usa CPU.
voice_cpu_on() {
  mkdir -p "$(dirname "$VOICE_DROPIN")"
  cat >"$VOICE_DROPIN" <<'EOF'
# Generado por power-extreme.sh (modo ahorro extremo): Kokoro en CPU para no
# despertar la dGPU. Se borra al salir del modo.
[Service]
Environment=CUDA_VISIBLE_DEVICES=
EOF
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user is-active --quiet voice-daemon.service &&
    systemctl --user try-restart voice-daemon.service >/dev/null 2>&1 || true
}

voice_cpu_off() {
  rm -f "$VOICE_DROPIN"
  rmdir "$(dirname "$VOICE_DROPIN")" 2>/dev/null || true
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user is-active --quiet voice-daemon.service &&
    systemctl --user try-restart voice-daemon.service >/dev/null 2>&1 || true
}

# ── encendido ─────────────────────────────────────────────────────────────
engage() {
  local auto="${1:-}" u t s bt_skip=0

  if is_on; then
    echo "El modo ahorro extremo ya está activo."
    return 0
  fi

  if ! on_battery; then
    if [ "$auto" = "--auto" ]; then
      return 0
    fi
    echo "Estás con corriente. El modo extremo es para batería: desconectá el cargador." >&2
    return 1
  fi

  mkdir -p "$STATE_DIR"

  # 1) Respaldar qué estaba corriendo, para poder volver exacto.
  : >"$RUNNING"; : >"$TIMERS_ON"; : >"$SYSTEM_ON"
  for u in "${STOP_USER_UNITS[@]}"; do
    systemctl --user is-active --quiet "$u" && echo "$u" >>"$RUNNING"
  done
  for t in "${STOP_TIMERS[@]}" "${STOP_PATHS[@]}"; do
    systemctl --user is-active --quiet "$t" && echo "$t" >>"$TIMERS_ON"
  done
  bt_has_device && bt_skip=1
  for s in "${STOP_SYSTEM_UNITS[@]}"; do
    [ "$s" = "bluetooth.service" ] && [ "$bt_skip" = 1 ] && continue
    systemctl is-active --quiet "$s" && echo "$s" >>"$SYSTEM_ON"
  done

  br_get >"$BRIGHT_SAVE" 2>/dev/null || true
  led_save
  idle_save

  # 2) Marcar primero: si algo falla después, `off` sabe qué deshacer.
  touch "$FLAG"
  log "on: $(wc -l <"$RUNNING") servicios, $(wc -l <"$TIMERS_ON") timers, $(wc -l <"$SYSTEM_ON") del sistema"

  # 3) Perfil + palancas del kernel (las aplica el guard, que ya las conoce).
  "$BIN_DIR/power-mode.sh" power-saver >/dev/null 2>&1 || true
  sudo -n systemctl start battery-power-guard.service >/dev/null 2>&1 || true

  # 4) Voz en CPU (por si algo la arranca después), brillo, teclado, pantalla.
  #    Todo esto va ANTES de parar servicios: si el modo se lanza desde dentro
  #    de la silla del agente, al pararla muere este mismo proceso.
  voice_cpu_on
  local max
  max="$(br_max)"
  if [ -n "${max:-}" ]; then
    br_set $((max * BRIGHT_PCT / 100))
  fi
  led_set 0
  idle_set "$IDLE_SCREENSAVER" "$IDLE_LOCK"
  shell_widgets pause
  hypr_lite_on

  # 5) Parar la actividad de fondo. Primero timers y servicios del sistema;
  #    los del usuario al final (uno de ellos puede matar este proceso).
  if [ -s "$TIMERS_ON" ]; then
    # shellcheck disable=SC2046
    systemctl --user stop $(read_list "$TIMERS_ON") >/dev/null 2>&1 || true
  fi
  if have_root; then
    if [ -s "$SYSTEM_ON" ]; then
      # shellcheck disable=SC2046
      sudo -n systemctl stop $(read_list "$SYSTEM_ON") >/dev/null 2>&1 || true
    fi
    # Soltar cachés del kernel: es memoria reclamable, pero el modo busca el
    # mínimo y así `free` refleja lo que realmente queda en uso.
    sudo -n sync
    echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
  else
    log "sin sudo: no se pudieron parar servicios del sistema"
  fi

  log "on: aplicado (power-saver, brillo ${BRIGHT_PCT}%, idle ${IDLE_SCREENSAVER}/${IDLE_LOCK})"
  local dgpu_msg=""
  dgpu_held && dgpu_msg=" Cerrá sesión y volvé a entrar para apagar la dGPU (≈8-10 W más)."
  notify "Ahorro extremo activo" \
    "IA local, voz, KVM, agentes y timers apagados. Solo SSH/Tailscale. Brillo ${BRIGHT_PCT}%, pantalla ${IDLE_SCREENSAVER}s.${dgpu_msg}"
  echo "Modo ahorro extremo ACTIVO. Se sale al enchufar el cargador (o «power-extreme.sh off»).${dgpu_msg}"

  # lan-mouse deja el socket al parar: sin borrarlo, moonlight.lua y la barra
  # creen que el daemon sigue vivo. Va antes de parar los servicios del usuario
  # (uno de ellos puede matar este proceso); el daemon lo recrea al arrancar.
  if grep -qx lan-mouse.service "$RUNNING" 2>/dev/null; then
    systemctl --user stop lan-mouse.service >/dev/null 2>&1 || true
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/lan-mouse-socket.sock"
  fi

  if [ -s "$RUNNING" ]; then
    # shellcheck disable=SC2046
    systemctl --user stop $(read_list "$RUNNING") >/dev/null 2>&1 || true
  fi
}

# ── apagado ───────────────────────────────────────────────────────────────
release() {
  local u t s

  if ! is_on; then
    echo "El modo ahorro extremo no está activo."
    return 0
  fi

  rm -f "$FLAG"
  log "off: restaurando"

  # 1) Devolver brillo, teclado y pantalla a como estaban.
  local b
  b="$(cat "$BRIGHT_SAVE" 2>/dev/null || true)"
  [ -n "${b:-}" ] && br_set "$b"
  local l
  l="$(cat "$LED_SAVE" 2>/dev/null || true)"
  [ -n "${l:-}" ] && led_set "$l"
  idle_restore
  voice_cpu_off
  shell_widgets resume
  hypr_lite_off

  # 2) Volver a levantar lo que estaba corriendo.
  if [ -s "$RUNNING" ]; then
    # shellcheck disable=SC2046
    systemctl --user start $(read_list "$RUNNING") >/dev/null 2>&1 || true
  fi
  if [ -s "$TIMERS_ON" ]; then
    # shellcheck disable=SC2046
    systemctl --user start $(read_list "$TIMERS_ON") >/dev/null 2>&1 || true
  fi
  if have_root && [ -s "$SYSTEM_ON" ]; then
    # shellcheck disable=SC2046
    sudo -n systemctl start $(read_list "$SYSTEM_ON") >/dev/null 2>&1 || true
  fi

  # 3) Que el guard re-evalúe (batería: power-saver y cap normal de 50 %).
  sudo -n systemctl start battery-power-guard.service >/dev/null 2>&1 || true

  rm -f "$RUNNING" "$TIMERS_ON" "$SYSTEM_ON" "$BRIGHT_SAVE" "$LED_SAVE" "$IDLE_SAVE" "$HYPR_SAVE"
  log "off: restaurado"
  notify "Ahorro extremo desactivado" "Servicios, brillo y pantalla vueltos a la normalidad."
  echo "Modo ahorro extremo DESACTIVADO."
}

# ── estado ────────────────────────────────────────────────────────────────
status() {
  local src="batería"
  on_battery || src="corriente"
  local prof
  prof="$("$BIN_DIR/power-mode.sh" status 2>/dev/null | sed -n 's/.*Perfil: //p')"
  printf 'Modo ahorro extremo: %s\n' "$(is_on && echo ACTIVO || echo apagado)"
  printf 'Fuente: %s   Perfil: %s   Batería: %s%%\n' "$src" "${prof:-?}" \
    "$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo '?')"
  local max cur
  max="$(br_max)"; cur="$(br_get)"
  [ -n "${max:-}" ] && [ -n "${cur:-}" ] &&
    printf 'Brillo: %d%%   Luz del teclado: %s\n' "$((cur * 100 / max))" \
      "$(cat "$KBD_LED/brightness" 2>/dev/null || echo '?')"
  local gpu=/sys/bus/pci/devices/0000:01:00.0/power/runtime_status
  local idle
  idle="$(python3 - "$SHELL_JSON" <<'PY' 2>/dev/null
import json, sys
try:
    i = json.load(open(sys.argv[1])).get('idle', {})
    print("%s %s" % (i.get('screensaver', '?'), i.get('lock', '?')))
except Exception:
    pass
PY
)"
  [ -n "$idle" ] && printf 'Pantalla: %s   Bloqueo: %s (segundos)\n' $idle
  printf 'Servicios parados: %s   Timers: %s   Del sistema: %s\n' \
    "$([ -f "$RUNNING" ] && wc -l <"$RUNNING" || echo 0)" \
    "$([ -f "$TIMERS_ON" ] && wc -l <"$TIMERS_ON" || echo 0)" \
    "$([ -f "$SYSTEM_ON" ] && wc -l <"$SYSTEM_ON" || echo 0)"
  printf 'Voz en CPU (drop-in): %s\n' "$([ -f "$VOICE_DROPIN" ] && echo sí || echo no)"
  if [ -r "$gpu" ]; then
    printf 'dGPU: %s' "$(cat "$gpu")"
    is_on && dgpu_held && printf ' (la tiene el compositor: cerrá sesión y volvé a entrar)'
    printf '\n'
  fi
  free | awk '/^Mem:/{printf "RAM: %.1f GB en uso de %.1f GB\n", $3/1048576, $2/1048576}'
  nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null |
    awk '{print "VRAM: "$0}'
  printf 'SSH: sshd %s   Tailscale: %s   Red: %s\n' \
    "$(systemctl is-active sshd 2>/dev/null)" \
    "$(systemctl is-active tailscaled 2>/dev/null)" \
    "$(systemctl is-active NetworkManager 2>/dev/null)"
  [ -r /sys/class/power_supply/BAT0/power_now ] &&
    awk '{printf "Consumo: %.1f W\n", $1 / 1000000}' /sys/class/power_supply/BAT0/power_now
}

case "${1:-status}" in
  on) engage "${2:-}" ;;
  off) release ;;
  toggle) is_on && release || engage ;;
  status) status ;;
  *)
    echo "Uso: power-extreme.sh [on|off|toggle|status]" >&2
    exit 1
    ;;
esac
