#!/usr/bin/env bash
# setup-omarchy.sh — Configurar dotfiles custom sobre Omarchy
# Ejecutar DESPUES de instalar Omarchy (ISO o manual).
# Un solo comando: clona repo + instala deps + symlinks + services.
set -euo pipefail

REPO="$HOME/dotfiles"
DOTFILES_CONFIG="$REPO/linux/config"
DOTFILES_BIN="$REPO/linux/bin"
DOTFILES_HOME="$REPO/linux/home"
DOTFILES_SYSTEM="$REPO/linux/system"
DOTFILES_XKB="$REPO/linux/xkb"

# ── Colores ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
header(){ echo -e "\n${BOLD}═══ $1 ═══${NC}"; }

# ── Detectar si es Omarchy/Arch ────────────────────────────────
if [[ ! -f /etc/arch-release ]] && ! grep -qi "arch\|omarchy" /etc/os-release 2>/dev/null; then
    err "Este script es para Omarchy/Arch Linux."
    cat /etc/os-release 2>/dev/null | head -5
    exit 1
fi

# ── Detectar si Omarchy esta instalado ─────────────────────────
if [[ ! -d /usr/share/omarchy ]]; then
    warn "Omarchy no detectado (/usr/share/omarchy no existe)."
    warn "Asegurate de haber instalado Omarchy primero."
    echo ""
    read -p "Continuar de todas formas? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

header "Setup Omarchy — Dotfiles custom"
info "Repo: $REPO"
echo ""

# ── Preflight: clonar repo si no existe ────────────────────────
if [[ ! -d "$REPO" ]]; then
    info "Clonando dotfiles..."
    git clone https://github.com/estebaninfante/dotfiles.git "$REPO"
    ok "Repo clonado en $REPO"
else
    info "Repo ya existe en $REPO"
    cd "$REPO" && git pull --ff-only 2>/dev/null || true
fi

# ── Detectar maquina por hardware (laptop|desktop) ─────────────
# CRITICO: no confiar en el default ni en un archivo previo. En fresh install
# `machine-type` no existe; usar "desktop" por defecto configuraria mal la
# laptop (fue exactamente el bug que detect-machine.sh previene).
if [[ -x "$REPO/scripts/detect-machine.sh" ]]; then
    MACHINE=$(bash "$REPO/scripts/detect-machine.sh")
else
    MACHINE=$(cat "$HOME/.config/machine-type" 2>/dev/null || echo "desktop")
fi
info "Maquina detectada: ${BOLD}$MACHINE${NC}"

# ══════════════════════════════════════════════════════════════
# FASE 1: AUR helper (yay)
# ══════════════════════════════════════════════════════════════
header "Fase 1: AUR helper"

if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
    info "Instalando yay..."
    sudo pacman -S --needed --noconfirm git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd "$HOME"
    ok "yay instalado"
elif command -v yay &>/dev/null; then
    ok "yay ya instalado"
else
    ok "paru ya instalado"
fi

AUR_HELPER=$(command -v yay || command -v paru)

# ══════════════════════════════════════════════════════════════
# FASE 2: Paquetes del sistema
# ══════════════════════════════════════════════════════════════
header "Fase 2: Paquetes del sistema"

# Paquetes core que Omarchy NO trae. Los que ya vienen con Omarchy
# (hyprland, uwsm, networkmanager, bluetooth base, etc.) se omiten.
EXTRA_PKGS=(
    # Hyprland
    hyprpaper hypridle hyprlock hyprpolkitagent hyprpicker hyprsunset
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

    # Terminal & shell
    kitty foot tmux starship zoxide fish

    # CLI & utilities
    fastfetch btop bat eza fd ripgrep fzf lazygit git-delta yq ncdu duf htop socat evtest
    unzip zip p7zip unrar rsync tldr tree whois plocate
    curl wget openssh jq gh imagemagick

    # Audio
    pamixer playerctl brightnessctl libnotify alsa-utils

    # Red / Bluetooth
    network-manager-applet bluez bluez-utils blueman

    # Malla + sync entre maquinas (FASE 9 los habilita si existen)
    tailscale syncthing

    # Wayland
    wl-clipboard wtype grim slurp swappy dotool

    # UI Omarchy (barra + widgets; la barra activa es la de Omarchy)
    swaync swayosd mako avizo waybar

    # Fonts
    noto-fonts noto-fonts-emoji noto-fonts-cjk woff2-font-awesome ttf-jetbrains-mono-nerd-basic

    # Apps
    nautilus dolphin gvfs-mtp gvfs-smb vlc mpv firefox tesseract tesseract-data-eng

    # TTS (motor de fallback)
    espeak-ng sox
)

TO_INSTALL=()
for pkg in "${EXTRA_PKGS[@]}"; do
    pacman -Qi "$pkg" &>/dev/null 2>&1 || TO_INSTALL+=("$pkg")
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    info "Instalando ${#TO_INSTALL[@]} paquetes base..."
    # Intento en bloque; si algun nombre no existe, reintenta uno por uno para
    # no abortar todo el setup por un solo paquete.
    sudo pacman -S --needed --noconfirm "${TO_INSTALL[@]}" \
        || for pkg in "${TO_INSTALL[@]}"; do
               sudo pacman -S --needed --noconfirm "$pkg" || warn "paquete no instalado: $pkg"
           done
    ok "Paquetes base procesados"
else
    ok "Todos los paquetes base ya instalados"
fi

# Paquetes AUR (el helper tambien resuelve paquetes de repo)
AUR_PKGS=(
    keyd
    brave-bin
    discord
    telegram-desktop
    obsidian
    qbittorrent
    moonlight-qt
    lan-mouse
    piper-tts-bin
    yt-dlp
    localsend-bin
    opencode-bin
    mise-bin
    handy-bin
    wayfreeze
    sunshine
)

# Gestos de touchpad (solo laptop)
if [[ "$MACHINE" == "laptop" ]]; then
    AUR_PKGS+=( libinput-gestures )
fi

AUR_TO_INSTALL=()
for pkg in "${AUR_PKGS[@]}"; do
    pacman -Qi "$pkg" &>/dev/null 2>&1 || AUR_TO_INSTALL+=("$pkg")
done

if [[ ${#AUR_TO_INSTALL[@]} -gt 0 ]]; then
    info "Instalando ${#AUR_TO_INSTALL[@]} paquetes AUR..."
    $AUR_HELPER -S --needed --noconfirm "${AUR_TO_INSTALL[@]}" \
        || for pkg in "${AUR_TO_INSTALL[@]}"; do
               $AUR_HELPER -S --needed --noconfirm "$pkg" || warn "AUR no instalado: $pkg"
           done
    ok "Paquetes AUR procesados"
else
    ok "Todos los paquetes AUR ya instalados"
fi

# ══════════════════════════════════════════════════════════════
# FASE 3: Hyprland config (reemplaza defaults de Omarchy)
# ══════════════════════════════════════════════════════════════
header "Fase 3: Hyprland config"

# Nuestro hyprland.lua + modulos reemplazan los defaults de Omarchy.
# El symlink a ~/.config/hypr lo aplica scripts/link-dotfiles.sh en Fase 5
# (repo = fuente de verdad). Aqui solo aseguramos que el dir exista.
mkdir -p "$HOME/.config/hypr"
ok "Hyprland config (symlink en Fase 5)"

# ══════════════════════════════════════════════════════════════
# FASE 4: Omarchy shell (barra activa)
# ══════════════════════════════════════════════════════════════
header "Fase 4: Omarchy shell"

# IMPORTANTE: la barra que se usa es la de OMARCHY, no el quickshell custom de
# los dotfiles. hyprland.lua la lanza con `omarchy-launch-shell`. NO se
# deshabilita omarchy-shell ni se habilita un quickshell.service propio (eso
# fue un enfoque viejo que dejaba dos barras peleando).
#
# El quickshell del repo se mantiene symlinkeado (link-dotfiles.sh) como
# referencia/backup, pero sin servicio systemd que lo arranque.
if [[ ! -d /usr/share/omarchy/shell ]]; then
    warn "Omarchy shell no encontrado en /usr/share/omarchy/shell"
    warn "Verifica la instalacion de Omarchy (omarchy-launch-shell)."
fi

# Asegurar que servicios viejos de quickshell no queden habilitados.
if systemctl --user is-enabled quickshell.service &>/dev/null 2>&1; then
    systemctl --user stop quickshell.service 2>/dev/null || true
    systemctl --user disable quickshell.service 2>/dev/null || true
    ok "quickshell.service (viejo) deshabilitado"
fi
rm -f "$HOME/.config/systemd/user/quickshell.service" 2>/dev/null || true

# mako es un demonio de notificaciones viejo que puede ganarle el bus
# (org.freedesktop.Notifications) al shell de Omarchy. Cuando eso pasa, las
# notificaciones salen con el estilo viejo de mako (p. ej. el borde rojo de
# ~/.config/mako/config) en vez de las del shell. Se enmascara para que el
# shell de Omarchy tome siempre las notificaciones.
if [[ -f /usr/lib/systemd/user/mako.service ]]; then
    if [[ "$(systemctl --user is-enabled mako.service 2>/dev/null)" != "masked" ]]; then
        systemctl --user stop mako.service 2>/dev/null || true
        systemctl --user mask mako.service 2>/dev/null || true
        ok "mako.service enmascarado (notificaciones por el shell de Omarchy)"
    fi
fi

ok "Omarchy shell activo (via omarchy-launch-shell en autostart de Hyprland)"

# ══════════════════════════════════════════════════════════════
# FASE 5: Configs (symlink al repo)
# ══════════════════════════════════════════════════════════════
header "Fase 5: Configs y symlinks"

mkdir -p "$HOME/.config" "$HOME/.local/bin"

# Todo el inventario de symlinks (config dirs, archivos sueltos, home files,
# scripts) vive en un unico script idempotente. Repo = fuente de verdad.
if [ -x "$REPO/scripts/link-dotfiles.sh" ]; then
    bash "$REPO/scripts/link-dotfiles.sh"
    ok "Symlinks aplicados via link-dotfiles.sh"
else
    err "Falta scripts/link-dotfiles.sh — no se pudieron crear symlinks"
fi

# ══════════════════════════════════════════════════════════════
# FASE 6: Scripts
# ══════════════════════════════════════════════════════════════
header "Fase 6: Scripts"

# Todos los scripts de linux/bin ya quedaron enlazados en Fase 5
# via link-dotfiles.sh (no clobbea archivos reales de Omarchy).
ok "Scripts enlazados (inventario completo via link-dotfiles.sh)"

# Parche local de hyprexpo (grilla 3D/fisheye): AMBAS maquinas corren el mismo
# .so parcheado (laptop = desktop). El script clona el commit fijado, aplica
# linux/patches/hyprexpo-local.patch y hace make. Necesita los headers de
# hyprland (`pkg-config hyprland`), que ya trae el paquete hyprland.
if [[ -x "$DOTFILES_BIN/hyprexpo-rebuild.sh" ]] && command -v make &>/dev/null; then
    info "Compilando hyprexpo parcheado (grilla 3D/fisheye)..."
    if bash "$DOTFILES_BIN/hyprexpo-rebuild.sh"; then
        ok "hyprexpo parcheado instalado (/var/cache/hyprpm/$USER/hyprexpo/hyprexpo.so)"
    else
        warn "hyprexpo no compilo — reintentar: ~/.local/bin/hyprexpo-rebuild.sh"
    fi
else
    warn "Falta make o hyprexpo-rebuild.sh — hyprexpo quedara stock"
fi

# ══════════════════════════════════════════════════════════════
# FASE 7: keyd (teclado)
# ══════════════════════════════════════════════════════════════
header "Fase 7: keyd"

if command -v keyd &>/dev/null; then
    sudo mkdir -p /etc/keyd
    sudo cp "$DOTFILES_SYSTEM/keyd/default.conf" /etc/keyd/default.conf
    # Config por-dispositivo (control remoto de presentaciones, etc.)
    for kconf in "$DOTFILES_SYSTEM"/keyd/*.conf; do
        [[ "$(basename "$kconf")" == "default.conf" ]] && continue
        sudo cp "$kconf" "/etc/keyd/$(basename "$kconf")"
    done
    sudo systemctl enable keyd
    sudo systemctl restart keyd
    ok "keyd configurado y habilitado"
else
    warn "keyd no encontrado — instalar con: yay -S keyd"
fi

if [[ -f "$DOTFILES_SYSTEM/system-sleep/keyd-resume.sh" ]]; then
    sudo install -o root -g root -m 755 \
        "$DOTFILES_SYSTEM/system-sleep/keyd-resume.sh" \
        /usr/lib/systemd/system-sleep/keyd-resume.sh
    ok "hook system-sleep keyd-resume instalado (re-inicia keyd al despertar)"
else
    warn "Falta $DOTFILES_SYSTEM/system-sleep/keyd-resume.sh"
fi

# `keyd monitor` (voice-key-listener, present-remote) abre los dispositivos
# virtuales de keyd directo; sin permiso falla en silencio y la tecla física de
# Windows nunca llega. Grupo `input` (vía estándar, requiere re-login) + regla
# udev que fija la ACL al crear el dispositivo (al instante y tras reiniciar keyd).
if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx input; then
    ok "usuario ya en grupo input"
else
    sudo usermod -aG input "$USER" \
        && ok "usuario agregado al grupo input (re-login para que tome efecto)" \
        || warn "no pude agregar $USER al grupo input"
fi
if [[ -f "$DOTFILES_SYSTEM/udev/80-keyd-input.rules" ]]; then
    sed "s|@USER@|$USER|g" "$DOTFILES_SYSTEM/udev/80-keyd-input.rules" \
        | sudo tee /etc/udev/rules.d/80-keyd-input.rules >/dev/null
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger --subsystem-match=input 2>/dev/null || true
    ok "udev 80-keyd-input instalado (keyd monitor accesible)"
else
    warn "Falta $DOTFILES_SYSTEM/udev/80-keyd-input.rules"
fi

# Layout XKB custom (dvk_prog): hyprland.lua lo usa como layout principal
# (kb_layout = "dvk_prog,es,us"). Sin el archivo de simbolos instalado,
# Hyprland cae a "us" (teclado roto tras fresh install).
XKB_SYMBOLS="/usr/share/X11/xkb/symbols/dvk_prog"
if [[ -f "$DOTFILES_XKB/dvk_prog" ]]; then
    if [[ -f "$XKB_SYMBOLS" ]] && diff -q "$DOTFILES_XKB/dvk_prog" "$XKB_SYMBOLS" &>/dev/null; then
        ok "XKB dvk_prog ya instalado"
    else
        sudo install -o root -g root -m 644 "$DOTFILES_XKB/dvk_prog" "$XKB_SYMBOLS"
        ok "XKB dvk_prog instalado en /usr/share/X11/xkb/symbols/"
    fi
else
    warn "Falta linux/xkb/dvk_prog — el layout custom no quedara disponible (hyprland cae a us)"
fi

# ══════════════════════════════════════════════════════════════
# FASE 8: Systemd user services
# ══════════════════════════════════════════════════════════════
header "Fase 8: Systemd user services"

SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

# graphical-session-holder: REMOVIDO — uwsm gestiona graphical-session.target.
# Con uwsm, este service choca: arranca antes del compositor, activa el target,
# y uwsm aborta pensando que ya hay una sesión gráfica (pantalla negra).
# Solo necesario en setups sin uwsm.

# lan-mouse
cat > "$SYSTEMD_DIR/lan-mouse.service" << 'EOF'
[Unit]
Description=LAN-Mouse KVM daemon
After=graphical-session.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'sleep 5'
ExecStart=/usr/bin/lan-mouse --capture-backend layer-shell daemon
Restart=always
RestartSec=5
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

# hyprpolkitagent
cat > "$SYSTEMD_DIR/hyprpolkitagent.service" << 'EOF'
[Unit]
Description=Hyprland polkit authentication agent
After=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'for i in $(seq 1 60); do [ -S "/run/user/%U/wayland-1" ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=/usr/lib/hyprpolkitagent/hyprpolkitagent
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=QT_QUICK_CONTROLS_STYLE=default
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# sunshine (NO se habilita: autoStart=false; lo arranca hyprland.lua post-login)
cat > "$SYSTEMD_DIR/sunshine.service" << 'EOF'
[Unit]
Description=Sunshine Game Streaming Host
After=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'for i in $(seq 1 60); do [ -S "/run/user/%U/wayland-1" ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=/usr/bin/sunshine
Restart=on-failure
RestartSec=3
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_CURRENT_DESKTOP=Hyprland

[Install]
WantedBy=graphical-session.target
EOF

# voice-daemon
cat > "$SYSTEMD_DIR/voice-daemon.service" << 'EOF'
[Unit]
Description=Voice daemon (TTS queue + playback)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/home/eztvn/.local/bin/voice-daemon
Restart=on-failure
RestartSec=3
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_SESSION_TYPE=wayland
Environment=PULSE_SERVER=unix:/run/user/%U/pulse/native

[Install]
WantedBy=graphical-session.target
EOF

# Enable services (sin quickshell: la barra es la de Omarchy)
systemctl --user daemon-reload
for svc in lan-mouse hyprpolkitagent voice-daemon; do
    systemctl --user enable "$svc" 2>/dev/null && ok "$svc habilitado" || warn "$svc no pudo habilitarse"
done

# talk-command (wake-word "dime"): DESHABILITADO a propósito.
# Se enmascara para que NADA lo reactive solo (ni enable, ni preset-all, ni
# este script). Para volver atrás a mano: scripts/setup-wake.sh
systemctl --user mask talk-command.service 2>/dev/null \
    && ok "talk-command enmascarado (nunca se habilita solo)" \
    || warn "talk-command no pudo enmascararse"

# ══════════════════════════════════════════════════════════════
# FASE 9: Servicios de sistema
# ══════════════════════════════════════════════════════════════
header "Fase 9: Servicios de sistema"

if command -v syncthing &>/dev/null; then
    sudo systemctl enable syncthing@eztvn 2>/dev/null || true
    ok "Syncthing habilitado"
fi

if command -v tailscale &>/dev/null; then
    sudo systemctl enable tailscaled 2>/dev/null || true
    ok "Tailscale habilitado"
fi

# LAN-Mouse KVM: IP flotante (laptop .240 / desktop .241) en la interfaz de
# casa preferida + ruta simetrica al peer, para que el KVM vaya por el cable
# cuando hay cable. Fuentes en linux/system/NetworkManager/ (dispatcher +
# kvm-ensure.sh) y linux/system/systemd/ (timer de safety net).
if [[ -f "$DOTFILES_SYSTEM/NetworkManager/kvm-ensure.sh" ]] && \
   [[ -f "$DOTFILES_SYSTEM/NetworkManager/dispatcher.d/90-lan-mouse" ]]; then
    sudo install -o root -g root -m 0755 \
        "$DOTFILES_SYSTEM/NetworkManager/kvm-ensure.sh" \
        /etc/NetworkManager/kvm-ensure.sh
    sudo install -o root -g root -m 0755 \
        "$DOTFILES_SYSTEM/NetworkManager/dispatcher.d/90-lan-mouse" \
        /etc/NetworkManager/dispatcher.d/90-lan-mouse
    # Replica perfiles WiFi entre las dos máquinas al conectar una red.
    if [[ -f "$DOTFILES_SYSTEM/NetworkManager/dispatcher.d/91-wifi-sync" ]]; then
        sudo install -o root -g root -m 0755 \
            "$DOTFILES_SYSTEM/NetworkManager/dispatcher.d/91-wifi-sync" \
            /etc/NetworkManager/dispatcher.d/91-wifi-sync
    else
        warn "Falta linux/system/NetworkManager/dispatcher.d/91-wifi-sync"
    fi
    if [[ -f "$DOTFILES_SYSTEM/systemd/kvm-ensure.service" ]] && \
       [[ -f "$DOTFILES_SYSTEM/systemd/kvm-ensure.timer" ]]; then
        sudo install -o root -g root -m 0644 \
            "$DOTFILES_SYSTEM/systemd/kvm-ensure.service" \
            /etc/systemd/system/kvm-ensure.service
        sudo install -o root -g root -m 0644 \
            "$DOTFILES_SYSTEM/systemd/kvm-ensure.timer" \
            /etc/systemd/system/kvm-ensure.timer
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo systemctl enable --now kvm-ensure.timer 2>/dev/null || true
        ok "kvm-ensure (dispatcher NM + timer systemd) instalado"
    else
        warn "Falta $DOTFILES_SYSTEM/systemd/kvm-ensure.service/.timer"
    fi
    if [[ -f "$DOTFILES_SYSTEM/sysctl/99-lan-mouse.conf" ]]; then
        sudo install -o root -g root -m 0644 \
            "$DOTFILES_SYSTEM/sysctl/99-lan-mouse.conf" \
            /etc/sysctl.d/99-lan-mouse.conf
        sudo sysctl --system >/dev/null 2>&1 || true
        ok "rp_filter loose (linux/system/sysctl/99-lan-mouse.conf)"
    else
        warn "Falta $DOTFILES_SYSTEM/sysctl/99-lan-mouse.conf"
    fi
else
    warn "Falta linux/system/NetworkManager/{kvm-ensure.sh,dispatcher.d/90-lan-mouse}"
fi

# Power guard: aplica ahorro (bateria) vs rendimiento (AC) al cambiar de fuente.
# Sin esto, hyprland.lua/monitors.lua quedan en modo AC (120Hz, blur, anims) y
# no hay `hyprctl reload` que re-evalue el estado -> consumo alto en bateria.
#   system: battery-power-guard.service + udev 99-power-source.rules
#   user:   power-session-guard.service (hyprctl reload + sunshine)
if [[ -f "$DOTFILES_SYSTEM/systemd/battery-power-guard.service" ]]; then
    sudo install -o root -g root -m 644 \
        "$DOTFILES_SYSTEM/systemd/battery-power-guard.service" \
        /etc/systemd/system/battery-power-guard.service
    sudo install -o root -g root -m 644 \
        "$DOTFILES_SYSTEM/udev/99-power-source.rules" \
        /etc/udev/rules.d/99-power-source.rules
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable battery-power-guard.service 2>/dev/null || true
    sudo systemctl start battery-power-guard.service 2>/dev/null || true
    ok "battery-power-guard (systemd + udev) instalado y habilitado"
else
    warn "Falta $DOTFILES_SYSTEM/systemd/battery-power-guard.service"
fi

# Bluetooth sin autosuspend USB: el adaptador MediaTek del laptop corta el
# audio de las llamadas (SCO/HFP) cuando se suspende. Ver el propio archivo.
if [[ -f "$DOTFILES_SYSTEM/udev/99-bt-no-autosuspend.rules" ]]; then
    sudo install -o root -g root -m 644 \
        "$DOTFILES_SYSTEM/udev/99-bt-no-autosuspend.rules" \
        /etc/udev/rules.d/99-bt-no-autosuspend.rules
    sudo udevadm control --reload-rules 2>/dev/null || true
    ok "udev 99-bt-no-autosuspend instalado (Bluetooth siempre encendido)"
else
    warn "Falta $DOTFILES_SYSTEM/udev/99-bt-no-autosuspend.rules"
fi

# Bench de reposo: mide el consumo al arrancar (solo en bateria) y lo guarda en
# /var/log/power-idle.tsv para comparar entre boots/cambios. Ver
# docs/energia-laptop-82y5.md y scripts/verify/energia.sh.
if [[ -f "$DOTFILES_SYSTEM/systemd/power-idle-bench.service" ]]; then
    sudo install -o root -g root -m 644 \
        "$DOTFILES_SYSTEM/systemd/power-idle-bench.service" \
        /etc/systemd/system/power-idle-bench.service
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable power-idle-bench.service 2>/dev/null || true
    ok "power-idle-bench (systemd) instalado y habilitado"
else
    warn "Falta $DOTFILES_SYSTEM/systemd/power-idle-bench.service"
fi

if [[ -f "$DOTFILES_SYSTEM/systemd-user/power-session-guard.service" ]]; then
    systemctl --user enable --now power-session-guard.service 2>/dev/null || true
    ok "power-session-guard (user) habilitado"
else
    warn "Falta $DOTFILES_SYSTEM/systemd-user/power-session-guard.service"
fi

if [[ -f "$DOTFILES_SYSTEM/systemd-user/linux-wallpaperengine.service" ]]; then
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/linux-wallpaperengine.service" "$SYSTEMD_DIR/linux-wallpaperengine.service"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "linux-wallpaperengine.service instalado (arranca con: wallpaper-switch.sh use video)"
else
    warn "Falta $DOTFILES_SYSTEM/systemd-user/linux-wallpaperengine.service"
fi

if [[ -f "$DOTFILES_SYSTEM/systemd-user/wallpaper-power-guard.service" ]] && [[ -f "$DOTFILES_SYSTEM/systemd-user/wallpaper-power-guard.timer" ]]; then
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/wallpaper-power-guard.service" "$SYSTEMD_DIR/wallpaper-power-guard.service"
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/wallpaper-power-guard.timer" "$SYSTEMD_DIR/wallpaper-power-guard.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now wallpaper-power-guard.timer 2>/dev/null || true
    ok "wallpaper-power-guard (user) habilitado (bateria -> frame, AC -> fuente)"
else
    warn "Falta $DOTFILES_SYSTEM/systemd-user/wallpaper-power-guard.service/.timer"
fi

if [[ -f "$DOTFILES_SYSTEM/systemd-user/ai-chats-sync.service" ]] && [[ -f "$DOTFILES_SYSTEM/systemd-user/ai-chats-sync.timer" ]] && [[ -f "$DOTFILES_SYSTEM/systemd-user/ai-chats-ingest.path" ]]; then
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/ai-chats-sync.service" "$SYSTEMD_DIR/ai-chats-sync.service"
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/ai-chats-sync.timer" "$SYSTEMD_DIR/ai-chats-sync.timer"
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/ai-chats-ingest.path" "$SYSTEMD_DIR/ai-chats-ingest.path"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now ai-chats-sync.timer ai-chats-ingest.path 2>/dev/null || true
    ok "ai-chats (user) habilitado (ingesta + embeddings periodicos)"
else
    warn "Falta $DOTFILES_SYSTEM/systemd-user/ai-chats-sync.service/.timer/.path"
fi

if [[ -f "$DOTFILES_SYSTEM/systemd-user/agentes-platform-main.service" ]] && [[ -f "$DOTFILES_SYSTEM/systemd-user/agentes-platform-developing.service" ]]; then
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/agentes-platform-main.service" "$SYSTEMD_DIR/agentes-platform-main.service"
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/agentes-platform-developing.service" "$SYSTEMD_DIR/agentes-platform-developing.service"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now agentes-platform-main.service agentes-platform-developing.service 2>/dev/null || true
    ok "agentes-platform (user) habilitado (main 10000->3031, developing 10001->3040)"
else
    warn "Falta $DOTFILES_SYSTEM/systemd-user/agentes-platform-*.service"
fi

if [[ -f "$DOTFILES_SYSTEM/systemd-user/rig-main-seat.service" ]]; then
    install -m 0644 "$DOTFILES_SYSTEM/systemd-user/rig-main-seat.service" "$SYSTEMD_DIR/rig-main-seat.service"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now rig-main-seat.service 2>/dev/null || true
    ok "rig-main-seat (user) habilitado (silla residente de main)"
else
    warn "Falta $DOTFILES_SYSTEM/systemd-user/rig-main-seat.service"
fi

# Sudoers: permite al panel de bateria (eztvn.power) reiniciar el guard al
# cambiar de perfil sin pedir password.
if [[ -f "$DOTFILES_SYSTEM/sudoers.d/power-guard" ]]; then
    sudo install -o root -g root -m 0440 \
        "$DOTFILES_SYSTEM/sudoers.d/power-guard" \
        /etc/sudoers.d/power-guard
    ok "sudoers power-guard instalado (NOPASSWD systemctl)"
else
    warn "Falta $DOTFILES_SYSTEM/sudoers.d/power-guard"
fi

# ══════════════════════════════════════════════════════════════
# FASE 10: Configs especiales (copy, no symlink)
# ══════════════════════════════════════════════════════════════
header "Fase 10: Configs especiales"

# Lan-mouse (writable — muta config.toml al guardar estado)
mkdir -p "$HOME/.config/lan-mouse"
cp -n "$DOTFILES_CONFIG/lan-mouse/lan-mouse.pem" "$HOME/.config/lan-mouse/" 2>/dev/null || true
cp "$DOTFILES_CONFIG/lan-mouse/config.${MACHINE}.toml" "$HOME/.config/lan-mouse/config.toml"
ok "Lan-mouse config copiada (machine: $MACHINE)"

# Machine type
echo "$MACHINE" > "$HOME/.config/machine-type"
ok "Machine type: $MACHINE"

# Hook theme-set: unica fuente del fondo (symlink canonico de Omarchy) ->
# hyprpaper.conf + recarga Hyprland (refresca hyprexpo). Sin esto, cambiar el
# wallpaper con `omarchy theme bg set` deja hyprpaper/hyprexpo con el anterior.
if command -v omarchy &>/dev/null && [[ -f "$DOTFILES_BIN/sync-wallpaper.sh" ]]; then
    if omarchy hook install theme-set "$DOTFILES_BIN/sync-wallpaper.sh" >/dev/null 2>&1; then
        ok "Hook theme-set instalado (sync-wallpaper.sh)"
    else
        warn "No se pudo instalar el hook theme-set"
    fi
else
    warn "omarchy no disponible — hook theme-set no instalado"
fi

# Sincronizar el fondo una vez: deja hyprpaper.conf apuntando al fondo canonico
# actual (hyprctl reload falla en silencio si Hyprland aun no corre en el setup).
if [[ -x "$DOTFILES_BIN/sync-wallpaper.sh" ]]; then
    if "$DOTFILES_BIN/sync-wallpaper.sh" >/dev/null 2>&1; then
        ok "Wallpaper sincronizado al fondo canonico"
    else
        warn "No se pudo sincronizar el wallpaper (se hara al fijar un tema)"
    fi
fi

# ══════════════════════════════════════════════════════════════
# FASE 10.5: Config del shell de Omarchy (barra, plugins, tema)
# ══════════════════════════════════════════════════════════════
header "Fase 10.5: Config Omarchy (barra/plugins/tema)"

# La barra activa es la de Omarchy: su config vive en ~/.config/omarchy (NO en
# symlinks). omarchy-sync.sh importa shell.json/shell.toml, plugins locales,
# branding, hooks y reinstala plugins/temas desde git. Sin esto, la laptop
# arranca con la barra default de Omarchy.
if [[ -x "$REPO/scripts/omarchy-sync.sh" ]] && command -v omarchy &>/dev/null; then
    if bash "$REPO/scripts/omarchy-sync.sh" import; then
        ok "Config Omarchy importada (barra eztvn.bar)"
    else
        warn "No se pudo importar la config de Omarchy"
    fi
else
    warn "omarchy-sync.sh no disponible u omarchy ausente — barra default"
fi

# ══════════════════════════════════════════════════════════════
# FASE 10.7: Read Aloud de Zotero (Kokoro local)
# ══════════════════════════════════════════════════════════════
header "Fase 10.7: Read Aloud (Kokoro local)"

# Kokoro como voz local de Zotero (vía speech-dispatcher): paquetes, venv,
# módulo /etc, unit kokoro-tts.service y verificación. Idempotente.
# SKIP_KOKORO=1 lo omite (p.ej. instalación rápida sin descargar el modelo).
if [[ -x "$REPO/scripts/setup-kokoro-reader.sh" ]]; then
    if SKIP_KOKORO="${SKIP_KOKORO:-0}" bash "$REPO/scripts/setup-kokoro-reader.sh"; then
        ok "Read Aloud: Kokoro local listo (Zotero → Local)"
    else
        warn "setup-kokoro-reader falló — reintentá con scripts/setup-kokoro-reader.sh"
    fi
else
    warn "Falta scripts/setup-kokoro-reader.sh"
fi

# ══════════════════════════════════════════════════════════════
# FASE 11: PATH
# ══════════════════════════════════════════════════════════════
header "Fase 11: PATH"

if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" << 'PATHEOF'

# dotfiles: ~/.local/bin en PATH
if [ -d "$HOME/.local/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) PATH="$HOME/.local/bin:$PATH" ;;
    esac
    export PATH
fi
PATHEOF
    ok "PATH actualizado en .bashrc"
else
    ok "PATH ya configurado"
fi

# ══════════════════════════════════════════════════════════════
# FASE 12: Verificación
# ══════════════════════════════════════════════════════════════
header "Fase 12: Verificación"

CHECKS=(
    "hyprland:Hyprland"
    "quickshell:Quickshell (barra Omarchy)"
    "keyd:keyd"
    "systemctl:systemd"
    "brightnessctl:Brightness"
    "jq:jq"
    "git:Git"
    "kitty:Kitty"
    "nvim:Neovim"
    "tmux:tmux"
    "starship:Starship"
    "zoxide:Zoxide"
)

ALL_OK=true
for check in "${CHECKS[@]}"; do
    cmd="${check%%:*}"
    name="${check##*:}"
    if command -v "$cmd" &>/dev/null; then
        ok "$name"
    else
        err "$name NO encontrado"
        ALL_OK=false
    fi
done

# Omarchy shell check
if [[ -d /usr/share/omarchy/shell ]]; then
    ok "Omarchy shell (barra activa)"
else
    warn "Omarchy shell no detectado en /usr/share/omarchy/shell"
fi

# Hyprland config check
if [[ -f "$HOME/.config/hypr/hyprland.lua" ]]; then
    ok "Hyprland Lua config"
else
    err "Hyprland Lua config NO encontrado"
    ALL_OK=false
fi

# Parche local de hyprexpo (grilla 3D/fisheye). AMBAS maquinas corren el mismo
# .so parcheado instalado en /var/cache/hyprpm/$USER/hyprexpo/hyprexpo.so.
if [[ -f "$HOME/.config/hypr/hyprland.lua" ]] && command -v hyprctl &>/dev/null; then
    if hyprctl plugin list 2>/dev/null | grep -qi "hyprexpo"; then
        ok "hyprexpo cargado (parche 3D/fisheye)"
    else
        warn "hyprexpo no cargado — correr: ~/.local/bin/hyprexpo-rebuild.sh + reiniciar Hyprland"
    fi
fi

echo ""
if $ALL_OK; then
    echo -e "${GREEN}${BOLD}═══ Setup completado ═══${NC}"
else
    echo -e "${YELLOW}${BOLD}═══ Setup completado con warnings ═══${NC}"
fi

echo ""
info "Proximos pasos:"
info "  1. Reiniciar (para keyd + servicios)"
info "  2. Copiar secrets: bash ~/dotfiles/scripts/setup-secrets.sh"
info "  3. Probar Hyprland: login desde SDDM"
echo ""
info "La barra es la de Omarchy (omarchy-launch-shell, en el autostart)."
info "Maquina: ${MACHINE} (machine-type escrito en ~/.config/machine-type)."
info "hyprexpo: parche 3D/fisheye en ambas maquinas. Rebuild: ~/.local/bin/hyprexpo-rebuild.sh"
echo ""
