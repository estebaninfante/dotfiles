#!/usr/bin/env bash
# migrate-to-ubuntu.sh — Script de migración de NixOS a Ubuntu 24.04 LTS
# Ejecutar en Ubuntu 24.04 fresco (post-install, después de primer boot).
# NO requiere sudo para todo — el script pide sudo cuando hace falta.
set -euo pipefail

REPO="$HOME/dotfiles"
DOTFILES_CONFIG="$REPO/linux/config"
DOTFILES_BIN="$REPO/linux/bin"
DOTFILES_HOME="$REPO/linux/home"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Preflight checks ──────────────────────────────────────────
if [[ ! -d "$REPO" ]]; then
    err "Repo no encontrado en $REPO"
    err "Clona primero: git clone <url> ~/dotfiles"
    exit 1
fi

if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    err "Este script es para Ubuntu. Detectado:"
    cat /etc/os-release | head -5
    exit 1
fi

info "=== Migración NixOS → Ubuntu 24.04 LTS ==="
info "Repo: $REPO"
echo ""

# ── FASE 1: Quitar Snap ───────────────────────────────────────
info "Fase 1: Quitando Snap..."
if command -v snap &>/dev/null; then
    # Listar snaps instalados (excepto core/bases que se quitan al final)
    SNAP_LIST=$(snap list 2>/dev/null | awk 'NR>1 {print $1}' | grep -v -E "^(core|bare|snapd|gnome-|gtk-|kde-|firmware-)" || true)
    for snap in $SNAP_LIST; do
        sudo snap remove --purge "$snap" 2>/dev/null || true
    done
    # Quitar daemon
    sudo systemctl disable --now snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
    sudo apt purge -y snapd 2>/dev/null || true
    sudo rm -rf /snap /var/snap /var/lib/snapd "$HOME/snap"
    # Bloquear reinstalación
    echo 'Package: snapd
Pin: release a=*
Pin-Priority: -10' | sudo tee /etc/apt/preferences.d/nosnap.pref >/dev/null
    ok "Snap quitado y bloqueado"
else
    ok "Snap no instalado, skip"
fi

# ── FASE 2: System update + NVIDIA ────────────────────────────
info "Fase 2: Actualizando sistema e instalando NVIDIA..."
sudo apt update && sudo apt upgrade -y

# Detectar GPU NVIDIA
if lspci 2>/dev/null | grep -qi nvidia; then
    info "GPU NVIDIA detectada — instalando driver..."
    sudo ubuntu-drivers install
    sudo apt install -y nvidia-cuda-toolkit nvidia-cudnn
    ok "NVIDIA driver + CUDA toolkit instalados"
else
    warn "No se detectó GPU NVIDIA — skip driver NVIDIA"
fi

# ── FASE 3: Paquetes base ─────────────────────────────────────
info "Fase 3: Instalando paquetes del sistema..."

# Hyprland ecosystem
sudo add-apt-repository -y ppa:hyprland/release
sudo apt update
sudo apt install -y \
    hyprland hyprpaper hypridle hyprlock hyprpolkitagent \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

# System essentials
sudo apt install -y \
    git curl wget build-essential cmake \
    python3 python3-pip python3-venv \
    nodejs npm \
    jq ripgrep fd-find bat eza fzf \
    zip unzip p7zip unrar

# Audio
sudo apt install -y \
    pipewire pipewire-pulse wireplumber \
    pavucontrol pamixer playerctl

# Network
sudo apt install -y \
    network-manager network-manager-gnome \
    bluez blueman \
    openssh-server

# Display / Wayland
sudo apt install -y \
    brightnessctl libnotify-bin \
    wl-clipboard wtype \
    grim slurp swappy \
    xdg-utils

# Apps
sudo apt install -y \
    kitty btop neovim git-delta \
    nautilus gparted \
    vlc mpv

# Fonts
sudo apt install -y \
    fonts-firacode fonts-jetbrains-mono \
    fonts-font-awesome fonts-noto-color-emoji

ok "Paquetes base instalados"

# ── FASE 4: Paquetes que pueden no estar en apt ───────────────
info "Fase 4: Instalando paquetes adicionales..."

# keyd (teclado)
if ! command -v keyd &>/dev/null; then
    info "Instalando keyd desde GitHub..."
    cd /tmp
    git clone https://github.com/rvaiya/keyd.git
    cd keyd
    make && sudo make install
    cd "$HOME"
    ok "keyd instalado"
else
    ok "keyd ya instalado"
fi

# input-remapper
sudo apt install -y input-remapper 2>/dev/null || {
    warn "input-remapper no en apt — instalar manualmente desde GitHub"
}

# Hyprland extras que pueden no estar en apt
for pkg in hyprpaper hypridle hyprlock; do
    if ! command -v "$pkg" &>/dev/null; then
        warn "$pkg no encontrado — instalar desde https://github.com/hyprwm/"
    fi
done

# quickshell
if ! command -v quickshell &>/dev/null; then
    warn "quickshell no encontrado — instalar desde https://quickshell.outfoxxed.me/"
    warn "O usar AppImage si está disponible"
fi

# ── FASE 5: Copiar configs ────────────────────────────────────
info "Fase 5: Copiando configuraciones..."

# Crear directorios destino
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share/fonts"

# Config dirs (symlink directo al repo)
CONFIG_DIRS=(
    hypr waybar kitty nvim kanata fastfetch
    mako swaync swayosd avizo btop gh opencode
    quickshell tmux voice gesturecontrol
)

for dir in "${CONFIG_DIRS[@]}"; do
    src="$DOTFILES_CONFIG/$dir"
    dst="$HOME/.config/$dir"
    if [[ -d "$src" ]]; then
        if [[ -L "$dst" ]]; then
            rm "$dst"
        elif [[ -d "$dst" ]]; then
            rm -rf "$dst"
        fi
        ln -sf "$src" "$dst"
        ok "~/.config/$dir → symlink al repo"
    else
        warn "$src no existe — skip"
    fi
done

# Config files sueltos
CONFIG_FILES=(
    libinput-gestures.conf mimeapps.list
    user-dirs.dirs user-dirs.locale
)

for file in "${CONFIG_FILES[@]}"; do
    src="$DOTFILES_CONFIG/$file"
    dst="$HOME/.config/$file"
    if [[ -f "$src" ]]; then
        ln -sf "$src" "$dst"
        ok "~/.config/$file → symlink"
    fi
done

# Home files
for file in .bashrc .gitconfig; do
    src="$DOTFILES_HOME/$file"
    dst="$HOME/$file"
    if [[ -f "$src" ]]; then
        ln -sf "$src" "$dst"
        ok "~/$file → symlink"
    fi
done

# Scripts
info "Copiando scripts a ~/.local/bin/..."
for script in "$DOTFILES_BIN"/*; do
    if [[ -f "$script" && -x "$script" ]]; then
        name=$(basename "$script")
        ln -sf "$script" "$HOME/.local/bin/$name"
    fi
done
ok "Scripts enlazados ($(ls "$DOTFILES_BIN" | wc -l) scripts)"

# Fonts
if [[ -d "$REPO/linux/fonts/old-london" ]]; then
    ln -sf "$REPO/linux/fonts/old-london" "$HOME/.local/share/fonts/old-london"
    fc-cache -f 2>/dev/null || true
    ok "Fuentes instaladas"
fi

# Lan-mouse config (copy, not symlink — lan-mouse mutates it)
mkdir -p "$HOME/.config/lan-mouse"
cp -n "$DOTFILES_CONFIG/lan-mouse/lan-mouse.pem" "$HOME/.config/lan-mouse/" 2>/dev/null || true
# Detectar máquina
MACHINE=$(cat "$HOME/.config/machine-type" 2>/dev/null || echo "desktop")
cp "$DOTFILES_CONFIG/lan-mouse/config.${MACHINE}.toml" "$HOME/.config/lan-mouse/config.toml"
ok "Lan-mouse config copiada (machine: $MACHINE)"

# input-remapper config (copy, not symlink — GUI mutates it)
mkdir -p "$HOME/.config/input-remapper-2/presets/Nintendo Wii Remote Pro Controller"
cp -n "$DOTFILES_CONFIG/input-remapper-2/config.json" "$HOME/.config/input-remapper-2/" 2>/dev/null || true
cp -n "$DOTFILES_CONFIG/input-remapper-2/presets/Nintendo Wii Remote Pro Controller/desktop.json" \
    "$HOME/.config/input-remapper-2/presets/Nintendo Wii Remote Pro Controller/" 2>/dev/null || true
ok "input-remapper config copiada"

# Machine type
echo "$MACHINE" > "$HOME/.config/machine-type"
ok "Machine type: $MACHINE"

# ── FASE 6: PATH ──────────────────────────────────────────────
info "Fase 6: Configurando PATH..."

# Añadir ~/.local/bin al PATH si no está
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

# ── FASE 7: Systemd units user ────────────────────────────────
info "Fase 7: Configurando systemd user services..."

SYSTEMD_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_DIR"

# dotfiles auto-sync
cat > "$SYSTEMD_DIR/dotfiles-sync.service" << 'EOF'
[Unit]
Description=Dotfiles auto-sync (pull + commit + push)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/home/eztvn/dotfiles/scripts/auto-sync.sh

[Install]
WantedBy=default.target
EOF

cat > "$SYSTEMD_DIR/dotfiles-sync.timer" << 'EOF'
[Unit]
Description=Dotfiles sync periodico

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=default.target
EOF

# quickshell
cat > "$SYSTEMD_DIR/quickshell.service" << 'EOF'
[Unit]
Description=Quickshell panel (QML bar)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do [ -S "/run/user/%U/wayland-1" ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=/usr/local/bin/quickshell --no-duplicate
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=QT_SCALE_FACTOR=1
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# lan-mouse
cat > "$SYSTEMD_DIR/lan-mouse.service" << 'EOF'
[Unit]
Description=LAN-Mouse KVM daemon
After=graphical-session.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'sleep 5'
ExecStart=/usr/local/bin/lan-mouse --capture-backend layer-shell daemon
Restart=always
RestartSec=5
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

# graphical-session-holder
cat > "$SYSTEMD_DIR/graphical-session-holder.service" << 'EOF'
[Unit]
Description=Keep graphical-session.target active (xdg portals)
After=default.target
Wants=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/sleep infinity
Restart=always

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable dotfiles-sync.timer
systemctl --user enable quickshell.service
systemctl --user enable lan-mouse.service
systemctl --user enable graphical-session-holder.service
ok "Systemd user services configurados"

# ── FASE 8: Servicios de sistema ──────────────────────────────
info "Fase 8: Configurando servicios de sistema..."

# keyd
if command -v keyd &>/dev/null; then
    sudo systemctl enable keyd
    ok "keyd habilitado"
fi

# Syncthing
sudo apt install -y syncthing
sudo systemctl enable syncthing@eztvn
ok "Syncthing habilitado"

# Tailscale
if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi
sudo systemctl enable tailscaled
ok "Tailscale habilitado"

# ── FASE 9: AI/ML stack ──────────────────────────────────────
info "Fase 9: Configurando stack de IA..."

# Python venv para AI
mkdir -p "$HOME/.local/share/venvs"
python3 -m venv "$HOME/.local/share/venvs/ai"
source "$HOME/.local/share/venvs/ai/bin/activate"

# PyTorch con CUDA (pre-compilado, SIN build)
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# AI tools comunes
pip install transformers datasets accelerate
pip install opencv-python-headless numpy scipy
pip install openai anthropic

deactivate
ok "AI stack instalado (torch + CUDA pre-compilado)"

# ── FASE 10: Verificación ────────────────────────────────────
echo ""
info "=== Verificación ==="
echo ""

CHECKS=(
    "hyprland:Hyprland"
    "hyprctl:Hyprland IPC"
    "quickshell:Quickshell"
    "keyd:keyd"
    "systemctl:systemd"
    "pipewire:PipeWire"
    "nmcli:NetworkManager"
    "bluetoothctl:Bluetooth"
    "brightnessctl:Brightness"
    "jq:jq"
    "git:Git"
    "python3:Python3"
    "node:Node.js"
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

# NVIDIA check
if command -v nvidia-smi &>/dev/null; then
    ok "NVIDIA driver"
else
    warn "nvidia-smi no encontrado — reiniciar si acabas de instalar drivers"
fi

# CUDA torch check
if python3 -c "import torch; print(f'torch {torch.__version__}, CUDA: {torch.cuda.is_available()}')" 2>/dev/null; then
    ok "PyTorch + CUDA"
else
    warn "PyTorch no encontrado en python3 del sistema — activar venv: source ~/.local/share/venvs/ai/bin/activate"
fi

echo ""
if $ALL_OK; then
    echo -e "${GREEN}=== Migración completada ===${NC}"
else
    echo -e "${YELLOW}=== Migración completada con warnings ===${NC}"
fi

echo ""
info "Próximos pasos:"
info "  1. Reiniciar (para que NVIDIA driver y servicios arranquen)"
info "  2. Copiar secrets: bash ~/dotfiles/scripts/setup-secrets.sh"
info "  3. Configurar Hyprland: añadir exec en ~/.config/hypr/hyprland.lua"
info "  4. Probar: hyprland (desde GDM o TTY)"
info "  5. Activar venv AI: source ~/.local/share/venvs/ai/bin/activate"
echo ""
info "Para desactivar auto-sync (evita conflictos mientras migras):"
info "  touch ~/.local/state/dotfiles/skip-auto-rebuild"
echo ""
