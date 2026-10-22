#!/usr/bin/env bash
# power-extreme.sh — modo de ahorro extremo para batería.
#
# Apaga lo que no hace falta para trabajar (voz de entrada, modelos locales,
# KVM/streaming, agentes y servidores de desarrollo, timers periódicos), pone
# power-saver, capa el brillo al 25 %, apaga la luz del teclado y acorta el
# apagado de pantalla. La SALIDA de voz sigue viva: el daemon de voz se reinicia
# con CUDA_VISIBLE_DEVICES="" para que Kokoro corra en CPU y no despierte la
# dGPU (que es ~8-10 W, ver docs/energia-laptop-82y5.md §4.1).
#
# Al enchufar el cargador se sale solo (power-session-guard.service llama `off`).
# Y a <=10 % de batería entra solo (hook omarchy battery-low).
#
# Uso:
#   power-extreme.sh on|off|toggle|status
#   power-extreme.sh on --auto    no falla si está con corriente (hook)
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
VOICE_DROPIN="$HOME/.config/systemd/user/voice-daemon.service.d/extreme-cpu.conf"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
KBD_LED="/sys/class/leds/platform::kbd_backlight"
BRIGHT_PCT=25
IDLE_SCREENSAVER=60 # antes 150
IDLE_LOCK=180       # antes 300

# ── qué se apaga ──────────────────────────────────────────────────────────
# Servicios de usuario. NO incluir acá: pipewire, wireplumber, omarchy-shell,
# omarchy-sleep-lock, hypridle, hyprpolkitagent, omarchy-fcitx5,
# gnome-keyring, dbus, NetworkManager y voice-daemon (salida de voz: queda
# dormido y es el canal para avisar; su Kokoro pasa a CPU).
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
  # agentes y servidores de desarrollo. rig-main-seat NO va acá a propósito:
  # es la silla que hospeda esta sesión y el canal para pedir que se salga del
  # modo. Su costo en reposo es ~0; matarla dejaría al usuario sin agente.
  rig-discord-bot.service rig-telegram-bot.service
  dsh-web.service agentes-platform-main.service
  agentes-platform-developing.service zentro-developing.service
  openclaw-gateway.service speeedy.service vision-gui.service
  ohm.service foldertinder.service omarchy-crash-watch.service
  airbnb-trip-compare.service talk-command.service
  # audio de micrófono procesado e input automation
  mic-bt-fx.service mic-gain.service ydotoold.service mnt-blackmagic.service
)

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

  # 3) Parar la actividad de fondo.
  if [ -s "$TIMERS_ON" ]; then
    # shellcheck disable=SC2046
    systemctl --user stop $(read_list "$TIMERS_ON") >/dev/null 2>&1 || true
  fi
  if [ -s "$RUNNING" ]; then
    # shellcheck disable=SC2046
    systemctl --user stop $(read_list "$RUNNING") >/dev/null 2>&1 || true
  fi
  if have_root; then
    if [ -s "$SYSTEM_ON" ]; then
      # shellcheck disable=SC2046
      sudo -n systemctl stop $(read_list "$SYSTEM_ON") >/dev/null 2>&1 || true
    fi
  else
    log "sin sudo: no se pudieron parar servicios del sistema"
  fi

  # 4) Perfil + palancas del kernel (las aplica el guard, que ya las conoce).
  "$BIN_DIR/power-mode.sh" power-saver >/dev/null 2>&1 || true
  sudo -n systemctl start battery-power-guard.service >/dev/null 2>&1 || true

  # 5) Voz en CPU, brillo, teclado, pantalla.
  voice_cpu_on
  local max
  max="$(br_max)"
  if [ -n "${max:-}" ]; then
    br_set $((max * BRIGHT_PCT / 100))
  fi
  led_set 0
  idle_set "$IDLE_SCREENSAVER" "$IDLE_LOCK"

  log "on: aplicado (power-saver, brillo ${BRIGHT_PCT}%, idle ${IDLE_SCREENSAVER}/${IDLE_LOCK})"
  notify "Ahorro extremo activo" \
    "IA local, KVM, streaming y agentes apagados. Brillo ${BRIGHT_PCT}%, pantalla ${IDLE_SCREENSAVER}s. Se sale al enchufar."
  echo "Modo ahorro extremo ACTIVO. Se sale al enchufar el cargador (o «power-extreme.sh off»)."
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

  rm -f "$RUNNING" "$TIMERS_ON" "$SYSTEM_ON" "$BRIGHT_SAVE" "$LED_SAVE" "$IDLE_SAVE"
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
  [ -r "$gpu" ] && printf 'dGPU: %s\n' "$(cat "$gpu")"
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
