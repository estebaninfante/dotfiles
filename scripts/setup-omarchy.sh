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

# ══════════════════════════════════════════════════════════════
# FASE 7: keyd (teclado)
# ══════════════════════════════════════════════════════════════
header "Fase 7: keyd"

if command -v keyd &>/dev/null; then
    sudo mkdir -p /etc/keyd
    sudo cp "$DOTFILES_SYSTEM/keyd/default.conf" /etc/keyd/default.conf
    sudo systemctl enable keyd
    sudo systemctl restart keyd
    ok "keyd configurado y habilitado"
else
    warn "keyd no encontrado — instalar con: yay -S keyd"
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
ExecStart=/usr/libexec/hyprpolkitagent
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=QT_QUICK_CONTROLS_STYLE=default
Restart=on-failure
RestartSec=3

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

# Parche local de hyprexpo (SOLO desktop: grilla 3D/fisheye). Laptop corre el
# plugin stock; saltar si no es desktop.
if [[ "$MACHINE" == "desktop" ]]; then
    if [[ -f "$HOME/.config/hypr/hyprland.lua" ]] && command -v hyprctl &>/dev/null; then
        if hyprctl plugin list 2>/dev/null | grep -qi "hyprexpo"; then
            ok "hyprexpo cargado (parche 3D desktop)"
        else
            warn "hyprexpo no cargado — correr: ~/.local/bin/hyprexpo-rebuild.sh"
        fi
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
if [[ "$MACHINE" == "laptop" ]]; then
    info "Laptop: hyprexpo stock (grilla plana, sin parche 3D/fisheye)."
else
    info "Desktop: parche local hyprexpo (grilla 3D/fisheye). Rebuild: ~/.local/bin/hyprexpo-rebuild.sh"
fi
echo ""
