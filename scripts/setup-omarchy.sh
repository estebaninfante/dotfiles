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
DOTFILES_PATCHES="$REPO/linux/patches"

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
    git clone https://github.com/eztvn/dotfiles.git "$REPO"
    ok "Repo clonado en $REPO"
else
    info "Repo ya existe en $REPO"
    cd "$REPO" && git pull --ff-only 2>/dev/null || true
fi

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

# Paquetes que Omarchy NO trae y el usuario necesita
EXTRA_PKGS=(
    # Hyprland extras
    hyprpaper hypridle hyprlock hyprpolkitagent
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

    # Terminal & shell
    kitty tmux starship zoxide fish

    # Editores
    neovim

    # Utilities
    fastfetch btop bat eza fd ripgrep fzf lazygit delta
    yq ncdu duf htop socat evtest
    unzip zip p7zip unrar rsync tldr tree
    curl wget openssh jq

    # Audio
    pipewire pipewire-pulse wireplumber
    pamixer playerctl brightnessctl libnotify

    # Network
    network-manager network-manager-gnome
    bluez blueman

    # Wayland
    wl-clipboard wtype grim slurp swappy
    networkmanagerapplet

    # Fonts
    ttf-jetbrains-mono ttf-fira-code noto-fonts noto-fonts-emoji
    ttf-font-awesome powerline-fonts ttf-jetbrains-mono-nerd

    # Apps
    neovim btop
    nautilus gparted
    vlc mpv

    # Dev
    git gh nodejs npm python python-pip
    gcc make cmake clang rust cargo go jdk maven

    # Gaming
    steam gamemode

    # Virtualization
    virt-manager qemu-full docker docker-compose
)

# Filtrar solo los que no estan
TO_INSTALL=()
for pkg in "${EXTRA_PKGS[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null 2>&1; then
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    info "Instalando ${#TO_INSTALL[@]} paquetes..."
    sudo pacman -S --needed --noconfirm "${TO_INSTALL[@]}"
    ok "Paquetes base instalados"
else
    ok "Todos los paquetes base ya instalados"
fi

# Paquetes AUR
AUR_PKGS=(
    keyd
    input-remapper
    brave-bin
    google-chrome
    discord
    telegram-desktop
    obsidian
    spotify
    libreoffice-still
    ttf-jetbrains-mono-nerd
    hyprpaper
    # Editors
    zed-editor
    # Gaming
    heroic-games-launcher-bin
    lutris
    wine-wow64
    dxvk-bin
    protontricks
    mangohud
    vulkan-tools
    # KVM
    lan-mouse-bin
    # Voice
    piper-tts-bin
    # Apps
    obs-studio
    gimp
    inkscape
    audacity
    yt-dlp
    ffmpeg
    localsend-bin
    qbittorrent
    nextcloud-client
    filezilla
    calibre
    teams-for-linux-bin
    moonlight-qt
    # AI
    opencode-bin
    # Clipboard
    wl-clipboard
    # Utilities
    nerd-fonts-jetbrains-mono
)

AUR_TO_INSTALL=()
for pkg in "${AUR_PKGS[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null 2>&1; then
        AUR_TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#AUR_TO_INSTALL[@]} -gt 0 ]]; then
    info "Instalando ${#AUR_TO_INSTALL[@]} paquetes AUR..."
    $AUR_HELPER -S --needed --noconfirm "${AUR_TO_INSTALL[@]}" || {
        warn "Algunos paquetes AUR fallaron — instalar manualmente"
    }
    ok "Paquetes AUR instalados"
else
    ok "Todos los paquetes AUR ya instalados"
fi

# ══════════════════════════════════════════════════════════════
# FASE 3: Copiar/configurar hyprland (reemplaza defaults de Omarchy)
# ══════════════════════════════════════════════════════════════
header "Fase 3: Hyprland config"

# Omarchy pone sus configs en ~/.config/hypr/ (Lua mode).
# Nuestro hyprland.lua reemplaza los defaults de Omarchy.
# IMPORTANTE: NO symlink — copiar (Omarchy puede regenerar en updates).
mkdir -p "$HOME/.config/hypr"
cp -ru "$DOTFILES_CONFIG/hypr/." "$HOME/.config/hypr/"
ok "Hyprland config copiada (reemplaza defaults de Omarchy)"

# ══════════════════════════════════════════════════════════════
# FASE 4: Quickshell custom (reemplaza omarchy-shell)
# ══════════════════════════════════════════════════════════════
header "Fase 4: Quickshell custom"

# Omarchy usa omarchy-shell (proceso QML propio con plugins).
# Nuestro quickshell es completamente custom (bar + menus + launcher).
# Estrategia: deshabilitar omarchy-shell, usar nuestro quickshell.

# 4a. Deshabilitar omarchy-shell si existe
if systemctl --user is-enabled omarchy-shell.service &>/dev/null 2>&1; then
    systemctl --user stop omarchy-shell.service 2>/dev/null || true
    systemctl --user disable omarchy-shell.service 2>/dev/null || true
    ok "omarchy-shell deshabilitado"
fi

# Si omarchy-shell se lanza desde hyprland autostart, lo quitamos
if [[ -f "$HOME/.config/hypr/autostart.lua" ]]; then
    if grep -q "omarchy" "$HOME/.config/hypr/autostart.lua" 2>/dev/null; then
        # Backup y quitar lineas de omarchy-shell del autostart
        cp "$HOME/.config/hypr/autostart.lua" "$HOME/.config/hypr/autostart.lua.bak"
        sed -i '/omarchy-shell/d' "$HOME/.config/hypr/autostart.lua"
        ok "omarchy-shell removido del autostart"
    fi
fi

# 4b. Symlink nuestro quickshell
rm -rf "$HOME/.config/quickshell" 2>/dev/null || true
ln -sf "$DOTFILES_CONFIG/quickshell" "$HOME/.config/quickshell"
ok "~/.config/quickshell → symlink al repo"

# 4c. Asegurar que nuestro quickshell se lanza (via systemd user service)
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/quickshell.service" << 'QSEOF'
[Unit]
Description=Quickshell panel (custom QML bar)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do [ -S "/run/user/%U/wayland-1" ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=quickshell --no-duplicate
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=QT_SCALE_FACTOR=1
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
QSEOF

systemctl --user daemon-reload
systemctl --user enable quickshell.service
ok "quickshell.service habilitado"

# ══════════════════════════════════════════════════════════════
# FASE 5: Configs (symlink al repo)
# ══════════════════════════════════════════════════════════════
header "Fase 5: Configs"

mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/fonts"

# Config dirs — symlink directo al repo
CONFIG_DIRS=(
    kitty nvim kanata fastfetch
    mako swaync swayosd avizo btop gh opencode
    tmux voice gesturecontrol
)

for dir in "${CONFIG_DIRS[@]}"; do
    src="$DOTFILES_CONFIG/$dir"
    dst="$HOME/.config/$dir"
    if [[ -d "$src" ]]; then
        rm -rf "$dst" 2>/dev/null || true
        ln -sf "$src" "$dst"
        ok "~/.config/$dir → symlink"
    fi
done

# NOTA: waybar NO se symlinkea — Omarchy usa su propio shell.
# Si el usuario quiere waybar, descomentar:
# rm -rf "$HOME/.config/waybar" 2>/dev/null || true
# ln -sf "$DOTFILES_CONFIG/waybar" "$HOME/.config/waybar"

# Config files sueltos
for file in libinput-gestures.conf mimeapps.list user-dirs.dirs user-dirs.locale; do
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

# ══════════════════════════════════════════════════════════════
# FASE 6: Scripts
# ══════════════════════════════════════════════════════════════
header "Fase 6: Scripts"

mkdir -p "$HOME/.local/bin"

# Detectar machine type (default: desktop para Omarchy —通常 instalado en escritorio)
MACHINE=$(cat "$HOME/.config/machine-type" 2>/dev/null || echo "desktop")

# Scripts excluidos (NixOS-specific o no aplican en Omarchy)
EXCLUDE_SCRIPTS=(
    "refind-check.sh"       # rEFInd es NixOS-specific
    "cuda-rebuild.sh"       # NixOS rebuild
    "cuda-error-loop.sh"    # NixOS rebuild
    "cuda-watchdog.sh"      # NixOS rebuild
    "cuda-build-notify.sh"  # NixOS rebuild
)

# Laptop-only scripts
LAPTOP_SCRIPTS=(
    "toggle-lid.sh" "lid-inhibit-waybar.sh" "waybar-battery-top"
    "gpu-mode.sh"
)

COUNT=0
for script in "$DOTFILES_BIN"/*; do
    if [[ ! -f "$script" ]]; then continue; fi
    name=$(basename "$script")

    # Skip exclusions
    skip=false
    for ex in "${EXCLUDE_SCRIPTS[@]}"; do
        [[ "$name" == "$ex" ]] && skip=true && break
    done
    $skip && continue

    # Skip laptop-only on desktop
    if [[ "$MACHINE" == "desktop" ]]; then
        for lp in "${LAPTOP_SCRIPTS[@]}"; do
            [[ "$name" == "$lp" ]] && skip=true && break
        done
        $skip && continue
    fi

    ln -sf "$script" "$HOME/.local/bin/$name"
    ((COUNT++)) || true
done
ok "Scripts enlazados ($COUNT scripts)"

# ══════════════════════════════════════════════════════════════
# FASE 7: keyd (teclado)
# ══════════════════════════════════════════════════════════════
header "Fase 7: keyd"

if command -v keyd &>/dev/null; then
    # Copiar config
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

# clipboard-sync
cat > "$SYSTEMD_DIR/clipboard-sync.service" << 'EOF'
[Unit]
Description=Bidirectional Wayland clipboard sync
After=graphical-session.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/wl-paste --watch /home/eztvn/.local/bin/clipboard-sync watch
Restart=always
RestartSec=3
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=CLIPBOARD_PEER=eztvn@desktop
Environment=CLIPBOARD_SSH_KEY=/home/eztvn/.ssh/id_ed25519

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

# dotoold
cat > "$SYSTEMD_DIR/dotoold.service" << 'EOF'
[Unit]
Description=dotool daemon (uinput for middle-click)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/dotoold
Restart=no

[Install]
WantedBy=graphical-session.target
EOF

# scroll-momentum
cat > "$SYSTEMD_DIR/scroll-momentum.service" << 'EOF'
[Unit]
Description=Mouse wheel momentum glide (MX-style)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/home/eztvn/.local/bin/scroll-momentum.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# gamepad-watch
cat > "$SYSTEMD_DIR/gamepad-watch.service" << 'EOF'
[Unit]
Description=Detect gamepad connect/disconnect -> game mode
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/home/eztvn/.local/bin/gamepad-watch.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

# hypr-input-bridge
cat > "$SYSTEMD_DIR/hypr-input-bridge.service" << 'EOF'
[Unit]
Description=Hyprland activewindow -> input-remapper preset
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/home/eztvn/.local/bin/hypr-input-bridge.sh
Restart=on-failure
RestartSec=2
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

# lid-inhibit (laptop only)
if [[ "$MACHINE" == "laptop" ]]; then
    cat > "$SYSTEMD_DIR/lid-inhibit.service" << 'EOF'
[Unit]
Description=Flag: suspend on lid close on AC

[Service]
Type=simple
ExecStart=/usr/bin/sleep infinity

[Install]
WantedBy=default.target
EOF
fi

# temperature-log
cat > "$SYSTEMD_DIR/temperature-log.service" << 'EOF'
[Unit]
Description=Log thermal sensor temperatures

[Service]
Type=oneshot
ExecStart=/home/eztvn/.local/bin/temperature-log.sh
EOF

cat > "$SYSTEMD_DIR/temperature-log.timer" << 'EOF'
[Unit]
Description=Periodic thermal sensor log

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=default.target
EOF

# Enable services
systemctl --user daemon-reload
for svc in dotfiles-sync.timer graphical-session-holder quickshell lan-mouse clipboard-sync hyprpolkitagent voice-daemon dotoold scroll-momentum gamepad-watch hypr-input-bridge temperature-log.timer; do
    systemctl --user enable "$svc" 2>/dev/null && ok "$svc habilitado" || warn "$svc no pudo habilitarse"
done

# ══════════════════════════════════════════════════════════════
# FASE 9: Servicios de sistema
# ══════════════════════════════════════════════════════════════
header "Fase 9: Servicios de sistema"

# Syncthing
if command -v syncthing &>/dev/null; then
    sudo systemctl enable syncthing@eztvn 2>/dev/null || true
    ok "Syncthing habilitado"
fi

# Tailscale
if command -v tailscale &>/dev/null; then
    sudo systemctl enable tailscaled 2>/dev/null || true
    ok "Tailscale habilitado"
fi

# input-remapper
if command -v input-remapper &>/dev/null; then
    sudo systemctl enable input-remapper 2>/dev/null || true
    ok "input-remapper habilitado"
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

# input-remapper (writable — GUI muta presets)
mkdir -p "$HOME/.config/input-remapper-2/presets/Nintendo Wii Remote Pro Controller"
cp -n "$DOTFILES_CONFIG/input-remapper-2/config.json" "$HOME/.config/input-remapper-2/" 2>/dev/null || true
cp -n "$DOTFILES_CONFIG/input-remapper-2/presets/Nintendo Wii Remote Pro Controller/desktop.json" \
    "$HOME/.config/input-remapper-2/presets/Nintendo Wii Remote Pro Controller/" 2>/dev/null || true
ok "input-remapper config copiada"

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
# FASE 12: Fonts
# ══════════════════════════════════════════════════════════════
header "Fase 12: Fonts"

if [[ -d "$REPO/linux/fonts/old-london" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    ln -sf "$REPO/linux/fonts/old-london" "$HOME/.local/share/fonts/old-london"
    fc-cache -f 2>/dev/null || true
    ok "Fuentes instaladas"
fi

# ══════════════════════════════════════════════════════════════
# FASE 13: NVIDIA (detectar y configurar)
# ══════════════════════════════════════════════════════════════
header "Fase 13: NVIDIA"

if lspci 2>/dev/null | grep -qi nvidia; then
    if ! command -v nvidia-smi &>/dev/null; then
        info "GPU NVIDIA detectada — instalando drivers..."
        sudo pacman -S --needed --noconfirm nvidia nvidia-utils nvidia-settings
        if [[ "$MACHINE" == "desktop" ]]; then
            sudo pacman -S --needed --noconfirm cuda cudnn 2>/dev/null || \
                warn "CUDA no disponible en repos — instalar manualmente"
        fi
        ok "NVIDIA drivers instalados (reiniciar para activar)"
    else
        ok "NVIDIA driver ya activo"
    fi
else
    ok "No hay GPU NVIDIA — skip"
fi

# ══════════════════════════════════════════════════════════════
# FASE 14: AI/ML stack
# ══════════════════════════════════════════════════════════════
header "Fase 14: AI/ML stack"

if ! python3 -c "import torch" 2>/dev/null; then
    info "Instalando PyTorch..."
    mkdir -p "$HOME/.local/share/venvs"
    python3 -m venv "$HOME/.local/share/venvs/ai"
    source "$HOME/.local/share/venvs/ai/bin/activate"
    pip install --upgrade pip

    # PyTorch con CUDA si hay NVIDIA
    if command -v nvidia-smi &>/dev/null; then
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
        ok "PyTorch + CUDA instalado"
    else
        pip install torch torchvision torchaudio
        ok "PyTorch (CPU) instalado"
    fi

    pip install transformers datasets accelerate
    pip install opencv-python-headless numpy scipy
    pip install openai anthropic
    deactivate
    ok "AI stack listo"
else
    ok "PyTorch ya instalado"
fi

# ══════════════════════════════════════════════════════════════
# FASE 15: Verificación
# ══════════════════════════════════════════════════════════════
header "Fase 15: Verificación"

CHECKS=(
    "hyprland:Hyprland"
    "hyprctl:Hyprland IPC"
    "quickshell:Quickshell"
    "keyd:keyd"
    "systemctl:systemd"
    "pipewire:PipeWire"
    "nmcli:NetworkManager"
    "brightnessctl:Brightness"
    "jq:jq"
    "git:Git"
    "python3:Python3"
    "node:Node.js"
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

# NVIDIA check
if command -v nvidia-smi &>/dev/null; then
    ok "NVIDIA driver"
else
    warn "nvidia-smi no encontrado — reiniciar si acabas de instalar drivers"
fi

# Quickshell config check
if [[ -L "$HOME/.config/quickshell" ]] && [[ -f "$HOME/.config/quickshell/shell.qml" ]]; then
    ok "Quickshell config"
else
    err "Quickshell config NO configurado"
    ALL_OK=false
fi

# Hyprland config check
if [[ -f "$HOME/.config/hypr/hyprland.lua" ]]; then
    ok "Hyprland Lua config"
else
    err "Hyprland Lua config NO encontrado"
    ALL_OK=false
fi

echo ""
if $ALL_OK; then
    echo -e "${GREEN}${BOLD}═══ Setup completado ═══${NC}"
else
    echo -e "${YELLOW}${BOLD}═══ Setup completado con warnings ═══${NC}"
fi

echo ""
info "Proximos pasos:"
info "  1. Reiniciar (para NVIDIA + keyd + servicios)"
info "  2. Copiar secrets: bash ~/dotfiles/scripts/setup-secrets.sh"
info "  3. Probar Hyprland: login desde SDDM"
info "  4. Para desactivar auto-sync: touch ~/.local/state/dotfiles/skip-auto-rebuild"
echo ""
info "Quickshell se lanza automaticamente via systemd."
info "Para reiniciar manualmente: systemctl --user restart quickshell"
echo ""
info "Omarchy shell deshabilitado. Usa tu quickshell custom."
info "Para restaurar omarchy-shell: systemctl --user enable --now omarchy-shell"
echo ""
