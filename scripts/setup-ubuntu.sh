#!/usr/bin/env bash
# setup-ubuntu.sh — Migra dotfiles de NixOS a Ubuntu 24.04 LTS
# Ejecutar en Ubuntu fresco despues de clonar ~/dotfiles
# Uso: bash ~/dotfiles/scripts/setup-ubuntu.sh [--skip-nvidia] [--skip-builds] [--dry-run] [--laptop|--desktop]
set -euo pipefail

# ══════════════════════════════════════════════════════════════
# CONFIG
# ══════════════════════════════════════════════════════════════
REPO="$HOME/dotfiles"
CFG="$REPO/linux/config"
BIN="$REPO/linux/bin"
HOME_DIR="$REPO/linux/home"
MACHINE=""

# ── Colores ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR!]${NC} $*" >&2; }

SKIP_NVIDIA=false
SKIP_BUILDS=false
DRY_RUN=false
DRY=""

# ── Arg parsing ────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --skip-nvidia)  SKIP_NVIDIA=true ;;
    --skip-builds)  SKIP_BUILDS=true ;;
    --dry-run)      DRY_RUN=true; DRY="echo [DRY-RUN]" ;;
    --laptop)       MACHINE="laptop" ;;
    --desktop)      MACHINE="desktop" ;;
    --help|-h)
      echo "Uso: $0 [--skip-nvidia] [--skip-builds] [--dry-run] [--laptop|--desktop]"
      echo "  --laptop/--desktop  Forzar machine type (auto-detect si omitido)"
      echo "  --skip-nvidia       No instalar drivers NVIDIA/CUDA"
      echo "  --skip-builds       No compilar quickshell/kanata/keyd/lan-mouse"
      echo "  --dry-run           Mostrar comandos sin ejecutar"
      exit 0 ;;
    *) err "Arg desconocido: $arg"; exit 1 ;;
  esac
done

# ══════════════════════════════════════════════════════════════
# BOOTSTRAP — instalar git si no existe y clonar repo
# ══════════════════════════════════════════════════════════════
bootstrap() {
  if [[ -d "$REPO/.git" ]]; then
    info "Repo ya existe en $REPO"
    return
  fi

  info "Instalando dependencias basicas..."
  sudo apt update
  sudo apt install -y git curl ca-certificates software-properties-common

  if [[ ! -d "$REPO" ]]; then
    echo ""
    echo "El repo no existe. Clonalo manualmente:"
    echo "  git clone <tu-repo-url> $REPO"
    echo "  bash $REPO/scripts/setup-ubuntu.sh"
    echo ""
    exit 1
  fi
}

# ══════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ══════════════════════════════════════════════════════════════
preflight() {
  if [[ ! -d "$REPO" ]]; then
    err "Repo no encontrado en $REPO. Clona primero: git clone <url> ~/dotfiles"
    exit 1
  fi
  if [[ ! -d "$REPO/.git" ]]; then
    err "$REPO no es un repo git."
    exit 1
  fi
  if [[ $(lsb_release -rs 2>/dev/null || echo "0") != "24.04" ]]; then
    warn "Este script esta disenado para Ubuntu 24.04 LTS. Continua bajo tu responsabilidad."
  fi
  if [[ $EUID -eq 0 ]]; then
    err "No correr como root. El script usa sudo cuando necesita."
    exit 1
  fi
}

# ── Detectar machine type ──────────────────────────────────────
detect_machine() {
  if [[ -n "$MACHINE" ]]; then
    info "Machine forzada: $MACHINE"
    return
  fi
  local chassis
  chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
  if [[ -d /sys/class/power_supply/BAT0 ]] || [[ "$chassis" -ge 8 && "$chassis" -le 11 ]]; then
    MACHINE="laptop"
  else
    MACHINE="desktop"
  fi
  info "Machine detectada: $MACHINE"
}

# ══════════════════════════════════════════════════════════════
# 1. PPAs
# ══════════════════════════════════════════════════════════════
setup_ppas() {
  info "Agregando PPAs..."

  # Brave browser repo
  if [[ -z "$DRY" ]]; then
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
      https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
      https://brave-browser-apt-release.s3.brave.com/ stable main" \
      | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
  else
    $DRY "sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://..."
    $DRY "echo deb [...] | sudo tee /etc/apt/sources.list.d/brave-browser-release.list"
  fi

  $DRY sudo add-apt-repository -y ppa:hyprland/ppa || true
  $DRY sudo add-apt-repository -y ppa:mozillateam/ppa || true
  $DRY sudo add-apt-repository -y ppa:agornking/kanata || true
  $DRY sudo add-apt-repository -y ppa:starsheeere/ppa || true
  $DRY sudo add-apt-repository -y ppa:linuxuprising/gpu-manager || true
  $DRY sudo apt update
  ok "PPAs agregados"
}

# ══════════════════════════════════════════════════════════════
# 2. Paquetes apt
# ══════════════════════════════════════════════════════════════
install_apt_packages() {
  info "Instalando paquetes apt..."

  # ── Core system ──
  local core=(
    build-essential git curl wget ca-certificates gnupg lsb-release
    software-properties-common apt-transport-https
    openssh-server
    network-manager network-manager-gnome bluez blueman
    power-profiles-daemon fprintd
    gnome-themes-extra adwaita-icon-theme
    xdg-desktop-portal xdg-desktop-portal-gtk
    fonts-noto fonts-noto-color-emoji
  )
  $DRY sudo apt install -y "${core[@]}"

  # ── Tailscale (needs its own repo) ──
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh || warn "Tailscale: instalar manualmente"
  fi

  # ── Polkit (nombre varia por distro) ──
  $DRY sudo apt install -y policykit-1 2>/dev/null || \
  $DRY sudo apt install -y polkit-gnome 2>/dev/null || \
    warn "Polkit: instalar manualmente"

  # ── Shell & terminal ──
  local shell_tools=(
    kitty fish tmux fastfetch btop htop glances
    jq yq tree rsync ncdu duf unzip zip p7zip unrar
    socat evtest
  )
  $DRY sudo apt install -y "${shell_tools[@]}"

  # ── Neovim ──
  $DRY sudo apt install -y neovim

  # ── Navegadores ──
  $DRY sudo apt install -y brave-browser
  # Chrome via .deb
  $DRY wget -q -O /tmp/google-chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" || true
  $DRY sudo dpkg -i /tmp/google-chrome.deb 2>/dev/null || $DRY sudo apt -f install -y
  # Firefox ESR via PPA
  $DRY sudo apt install -y firefox-esr || true

  # ── Hyprland ecosystem ──
  local hypr=(
    hyprland hyprpicker hypridle hyprlock hyprpaper hyprpolkitagent
    waybar swaynotificationcenter swayosd avizo
    xdg-desktop-portal-hyprland
    brightnessctl libnotify playerctl pamixer
    wl-clipboard wtype grim slurp swappy imv
    network-manager-applet
  )
  # Try all at once, fallback to individual
  if ! $DRY sudo apt install -y "${hypr[@]}" 2>/dev/null; then
    warn "Algunos paquetes Hyprland no disponibles. Intentando uno por uno..."
    for pkg in "${hypr[@]}"; do
      $DRY sudo apt install -y "$pkg" 2>/dev/null || warn "Falta: $pkg"
    done
  fi

  # ── Qt6 (necesario para quickshell) ──
  $DRY sudo apt install -y \
    qt6-base-dev qt6-declarative-dev qml6-module-qtquick \
    qml6-module-qtquick-controls qml6-module-qtquick-layouts \
    qml6-module-qtgraphicaleffects libqt6svg6-dev qt6-imageformats \
    libqt6quick6 qt6-tools-dev qt6-tools-dev-tools

  # ── KDE/GNOME apps ──
  local desktop_apps=(
    dolphin ark gwenview kate nautilus eog
    gparted gnome-disk-utility gnome-tweaks
  )
  $DRY sudo apt install -y "${desktop_apps[@]}" || true

  # ── Multimedia ──
  local media=(
    vlc mpv obs-studio ffmpeg imagemagick gimp inkscape audacity
    ffmpegthumbnailer
  )
  $DRY sudo apt install -y "${media[@]}"

  # ── Messaging / productivity ──
  $DRY sudo apt install -y libreoffice calibre qbittorrent
  $DRY sudo snap install discord || true
  $DRY sudo snap install telegram-desktop || true
  $DRY sudo snap install thunderbird || true

  # ── Dev tools ──
  local dev=(
    gcc g++ g++-13 make cmake clang
    python3 python3-pip python3-venv python3-gi python3-cairo python3-numpy
    nodejs npm
    golang-go default-jdk maven
    docker.io docker-compose-v2
  )
  $DRY sudo apt install -y "${dev[@]}" || true

  # ── Containers / Virtualization ──
  $DRY sudo apt install -y virt-manager qemu-kvm ovmf || true

  # ── Gaming ──
  $DRY sudo apt install -y wine64 || true
  $DRY sudo apt install -y lutris || true
  $DRY sudo snap install steam || true

  # ── Accessibility ──
  $DRY sudo apt install -y espeak-ng || true

  # ── Rust/Cargo (needed for kanata, lan-mouse builds) ──
  if ! command -v cargo &>/dev/null; then
    info "Instalando Rust..."
    if [[ -z "$DRY" ]]; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      source "$HOME/.cargo/env"
    else
      $DRY "curl ... | sh -s -- -y (rustup)"
    fi
  fi

  ok "Paquetes apt instalados"
}

# ══════════════════════════════════════════════════════════════
# 3. CLI modernos (binarios upstream)
# ══════════════════════════════════════════════════════════════
install_modern_cli() {
  info "Instalando CLI modernos..."

  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"
  export PATH="$HOME/.local/bin:$PATH"

  # bat
  if ! command -v bat &>/dev/null && ! command -v batcat &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      local bat_ver
      bat_ver=$(curl -sL https://github.com/sharkdp/bat/releases/latest/download/ 2>/dev/null | grep -oP 'bat-v\K[^/]+' || echo "0.24.0")
      curl -sL "https://github.com/sharkdp/bat/releases/download/v${bat_ver}/bat-v${bat_ver}-x86_64-unknown-linux-gnu.tar.gz" \
        | tar xz -C /tmp && cp /tmp/bat-*/bat "$bin_dir/bat" && chmod +x "$bin_dir/bat"
    else
      $DRY "curl ... | tar ... (bat)"
    fi
    ok "bat"
  fi

  # fd
  if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      local fd_ver
      fd_ver=$(curl -sL https://github.com/sharkdp/fd/releases/latest/download/ 2>/dev/null | grep -oP 'fd-v\K[^/]+' || echo "10.2.0")
      curl -sL "https://github.com/sharkdp/fd/releases/download/v${fd_ver}/fd-v${fd_ver}-x86_64-unknown-linux-gnu.tar.gz" \
        | tar xz -C /tmp && cp /tmp/fd-*/fd "$bin_dir/fd" && chmod +x "$bin_dir/fd"
    else
      $DRY "curl ... | tar ... (fd)"
    fi
    ok "fd"
  fi

  # ripgrep
  if ! command -v rg &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      local rg_ver
      rg_ver=$(curl -sL https://github.com/BurntSushi/ripgrep/releases/latest/download/ 2>/dev/null | grep -oP 'ripgrep-\K[^/]+' || echo "14.1.1")
      curl -sL "https://github.com/BurntSushi/ripgrep/releases/download/${rg_ver}/ripgrep-${rg_ver}-x86_64-unknown-linux-musl.tar.gz" \
        | tar xz -C /tmp && cp /tmp/ripgrep-*/rg "$bin_dir/rg" && chmod +x "$bin_dir/rg"
    else
      $DRY "curl ... | tar ... (ripgrep)"
    fi
    ok "ripgrep"
  fi

  # eza
  if ! command -v eza &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -sL https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz \
        | tar xz -C /tmp && cp /tmp/eza "$bin_dir/eza" && chmod +x "$bin_dir/eza"
    else
      $DRY "curl ... | tar ... (eza)"
    fi
    ok "eza"
  fi

  # lazygit
  if ! command -v lazygit &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -s "https://raw.githubusercontent.com/jesseduffield/lazygit/master/install.sh" | bash
    else
      $DRY "curl ... | bash (lazygit)"
    fi
    ok "lazygit"
  fi

  # delta (git-delta)
  if ! command -v delta &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      local delta_ver
      delta_ver=$(curl -sL https://github.com/dandavison/delta/releases/latest/download/ 2>/dev/null | grep -oP 'delta-\K[^/]+' || echo "0.18.2")
      curl -sL "https://github.com/dandavison/delta/releases/download/${delta_ver}/delta-${delta_ver}-x86_64-unknown-linux-gnu.tar.gz" \
        | tar xz -C /tmp && cp /tmp/delta-*/delta "$bin_dir/delta" && chmod +x "$bin_dir/delta"
    else
      $DRY "curl ... | tar ... (delta)"
    fi
    ok "delta"
  fi

  # starship
  if ! command -v starship &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -sS https://starship.rs/install.sh | sh -s -- -y
    else
      $DRY "curl -sS https://starship.rs/install.sh | sh -s -- -y"
    fi
    ok "starship"
  fi

  # zoxide
  if ! command -v zoxide &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    else
      $DRY "curl ... | bash (zoxide)"
    fi
    ok "zoxide"
  fi

  # tldr (tealdeer)
  if ! command -v tldr &>/dev/null; then
    curl -sL https://github.com/tealdeer-rs/tealdeer/releases/latest/download/tealdeer-linux-x86_64-musl \
      -o "$bin_dir/tldr" && chmod +x "$bin_dir/tldr" && "$bin_dir/tldr" --update && ok "tldr"
  fi

  # gh (GitHub CLI)
  if ! command -v gh &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt update && sudo apt install -y gh && ok "gh"
    else
      $DRY "curl ... | sudo dd of=.../githubcli-archive-keyring.gpg"
      $DRY "echo deb [...] | sudo tee /etc/apt/sources.list.d/github-cli.list"
      $DRY sudo apt update && $DRY sudo apt install -y gh && ok "gh"
    fi
  fi

  # pnpm
  if ! command -v pnpm &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -fsSL https://get.pnpm.io/install.sh | sh -
    else
      $DRY "curl -fsSL https://get.pnpm.io/install.sh | sh -"
    fi
    ok "pnpm"
  fi

  # uv (Python package manager)
  if ! command -v uv &>/dev/null; then
    if [[ -z "$DRY" ]]; then
      curl -LsSf https://astral.sh/uv/install.sh | sh
    else
      $DRY "curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi
    ok "uv"
  fi

  ok "CLI modernos instalados"
}

# ══════════════════════════════════════════════════════════════
# 4. Builds manuales (quickshell, kanata, keyd, lan-mouse)
# ══════════════════════════════════════════════════════════════
install_manual_builds() {
  if $SKIP_BUILDS; then
    warn "Saltando builds manuales (--skip-builds)"
    return
  fi

  info "Compilando herramientas manuales..."
  local build_deps=(
    cmake meson ninja-build pkg-config
    libevdev-dev libudev-dev libinput-dev
    libxkbcommon-dev libwayland-dev
    libpulse-dev libpipewire-0.3-dev
    libssl-dev libffi-dev
    libqt6qml6 libqt6quickcontrols2-6
    qt6-declarative-dev qt6-wayland
    wayland-protocols libwlroots-dev
    hwdata
  )
  $DRY sudo apt install -y "${build_deps[@]}"

  local src_dir="/tmp/builds"
  mkdir -p "$src_dir"

  # Ensure cargo is in PATH
  export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

  # ── quickshell (QML bar) ──
  if ! command -v quickshell &>/dev/null; then
    info "Compilando quickshell..."
    $DRY git clone --depth 1 https://github.com/quickshell-mirror/quickshell.git "$src_dir/quickshell" 2>/dev/null || \
    $DRY git clone --depth 1 https://git.outfoxxed.me/outfoxxed/quickshell.git "$src_dir/quickshell" || true
    if [[ -d "$src_dir/quickshell" ]]; then
      $DRY cmake -S "$src_dir/quickshell" -B "$src_dir/quickshell/build" \
        -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
      $DRY cmake --build "$src_dir/quickshell/build" -j"$(nproc)"
      $DRY sudo cmake --install "$src_dir/quickshell/build"
      ok "quickshell"
    else
      warn "No se pudo clonar quickshell"
    fi
  fi

  # ── kanata (teclado programable) ──
  if ! command -v kanata &>/dev/null; then
    info "Compilando kanata..."
    if command -v cargo &>/dev/null; then
      $DRY cargo install --git https://github.com/jtroo/kanata.git kanata
      $DRY cp "$HOME/.cargo/bin/kanata" "$HOME/.local/bin/"
      ok "kanata"
    else
      warn "cargo no disponible, instala kanata manualmente"
    fi
  fi

  # ── keyd (key remapping daemon) ──
  if ! command -v keyd &>/dev/null; then
    info "Compilando keyd..."
    $DRY git clone --depth 1 https://github.com/rvaiya/keyd.git "$src_dir/keyd" || true
    if [[ -d "$src_dir/keyd" ]]; then
      $DRY make -C "$src_dir/keyd"
      $DRY sudo make -C "$src_dir/keyd" install
      $DRY sudo systemctl enable keyd
      ok "keyd"
    fi
  fi

  # ── lan-mouse (KVM por red) ──
  if ! command -v lan-mouse &>/dev/null; then
    info "Compilando lan-mouse..."
    if command -v cargo &>/dev/null; then
      $DRY git clone --depth 1 https://github.com/feschber/lan-mouse.git "$src_dir/lan-mouse" || true
      if [[ -d "$src_dir/lan-mouse" ]]; then
        (cd "$src_dir/lan-mouse" && $DRY cargo build --release)
        $DRY cp "$src_dir/lan-mouse/target/release/lan-mouse" "$HOME/.local/bin/"
        ok "lan-mouse"
      fi
    else
      warn "cargo no disponible, instala lan-mouse manualmente"
    fi
  fi

  # ── deskflow (KVM GUI) ──
  if ! command -v deskflow &>/dev/null && ! command -v input-leap &>/dev/null; then
    info "Descargando deskflow..."
    local df_ver="2.0.0"
    $DRY wget -q -O /tmp/deskflow.deb \
      "https://github.com/deskflow/deskflow/releases/download/v${df_ver}/deskflow_${df_ver}_amd64.deb" || true
    $DRY sudo dpkg -i /tmp/deskflow.deb 2>/dev/null || $DRY sudo apt -f install -y
  fi

  ok "Builds manuales completados"
}

# ══════════════════════════════════════════════════════════════
# 5. Flatpak (apps que no estan en repos)
# ══════════════════════════════════════════════════════════════
install_flatpak_apps() {
  info "Instalando flatpak apps..."
  $DRY sudo apt install -y flatpak
  $DRY sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  local fpk_apps=(
    com.heroicgameslauncher.hgl
    com.spotify.Client
    com.obsidian.Obsidian
    io.github.MakovQ.prismlauncher
    io.github.moonlight_technologies.moonlight-qt
    stremio.stremio
    com.github.Ammmber.gearlever
    com.github.Ammmber.protonplus
    dev.aunali.localsend
  )
  for app in "${fpk_apps[@]}"; do
    $DRY flatpak install -y flathub "$app" 2>/dev/null || warn "Flatpak no disponible: $app"
  done

  # Nextcloud
  $DRY sudo apt install -y nextcloud-desktop || $DRY flatpak install -y flathub com.nextcloud.desktopclient || true

  ok "Flatpak apps instalados"
}

# ══════════════════════════════════════════════════════════════
# 6. NVIDIA drivers + CUDA (para AI local)
# ══════════════════════════════════════════════════════════════
install_nvidia() {
  if $SKIP_NVIDIA; then
    warn "Saltando NVIDIA (--skip-nvidia)"
    return
  fi

  info "Instalando NVIDIA drivers + CUDA..."
  $DRY sudo ubuntu-drivers install || true
  $DRY sudo apt install -y nvidia-driver-550 nvidia-utils-550 || \
  $DRY sudo apt install -y nvidia-driver-535 nvidia-utils-535 || \
  warn "Instalar NVIDIA driver manualmente: sudo ubuntu-drivers install"

  # CUDA toolkit
  $DRY wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb || true
  $DRY sudo dpkg -i /tmp/cuda-keyring.deb 2>/dev/null || true
  $DRY sudo apt update
  $DRY sudo apt install -y cuda-toolkit-12-6 || \
  $DRY sudo apt install -y cuda-toolkit-12-4 || \
  warn "Instalar CUDA toolkit manualmente desde developer.nvidia.com"

  # cuDNN
  $DRY sudo apt install -y libcudnn9-cuda-12 || \
  $DRY sudo apt install -y libcudnn8-cuda-12 || \
  warn "cuDNN no encontrado. Instalar desde: https://developer.nvidia.com/cudnn"

  # Vulkan
  $DRY sudo apt install -y vulkan-tools vulkan-validation-layers libvulkan1

  # Mangohud
  $DRY sudo apt install -y mangohud || $DRY flatpak install -y flathub org.freedesktop.Platform.MangoHud || true

  ok "NVIDIA + CUDA instalado"
}

# ══════════════════════════════════════════════════════════════
# 7. XDG dirs + Symlinks
# ══════════════════════════════════════════════════════════════
setup_symlinks() {
  info "Creando symlinks..."

  local cfg="$HOME/.config"
  local bin="$HOME/.local/bin"
  mkdir -p "$cfg" "$bin"

  # ── XDG dirs (fresh Ubuntu may not have them) ──
  mkdir -p "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents" "$HOME/Music" "$HOME/Pictures" "$HOME/Videos" "$HOME/Templates" "$HOME/Public"
  if [[ -f "$CFG/user-dirs.dirs" ]] && [[ ! -L "$HOME/.config/user-dirs.dirs" ]]; then
    cp -a "$CFG/user-dirs.dirs" "$HOME/.config/user-dirs.dirs"
  fi

  # ── Config dirs ──
  local config_dirs=(
    waybar kitty nvim kanata fastfetch
    mako swaync swayosd avizo btop gh opencode
    quickshell tmux voice gesturecontrol
  )
  for d in "${config_dirs[@]}"; do
    if [[ -d "$CFG/$d" ]]; then
      rm -f "$cfg/$d" 2>/dev/null || true
      ln -sfn "$CFG/$d" "$cfg/$d"
    fi
  done

  # ── Config files sueltos ──
  local config_files=(
    libinput-gestures.conf mimeapps.list
    user-dirs.locale
  )
  for f in "${config_files[@]}"; do
    if [[ -f "$CFG/$f" ]]; then
      rm -f "$cfg/$f" 2>/dev/null || true
      ln -sfn "$CFG/$f" "$cfg/$f"
    fi
  done

  # ── Hyprland: copiar (GUI muta config) ──
  if [[ -d "$CFG/hypr" ]]; then
    rm -rf "$cfg/hypr" 2>/dev/null || true
    mkdir -p "$cfg/hypr"
    cp -a "$CFG/hypr/." "$cfg/hypr/"
    ok "hyprland config copiado"
  fi

  # ── lan-mouse: copiar (GUI muta config.toml) ──
  if [[ -d "$CFG/lan-mouse" ]]; then
    rm -rf "$cfg/lan-mouse" 2>/dev/null || true
    mkdir -p "$cfg/lan-mouse"
    cp -a "$CFG/lan-mouse/." "$cfg/lan-mouse/"
    ok "lan-mouse config copiado"
  fi

  # ── input-remapper: copiar (GUI muta presets) ──
  if [[ -d "$CFG/input-remapper-2" ]]; then
    rm -rf "$cfg/input-remapper-2" 2>/dev/null || true
    mkdir -p "$cfg/input-remapper-2"
    cp -a "$CFG/input-remapper-2/." "$cfg/input-remapper-2/"
    ok "input-remapper config copiado"
  fi

  # ── Home files ──
  for f in .bashrc .gitconfig; do
    if [[ -f "$HOME_DIR/$f" ]]; then
      rm -f "$HOME/$f" 2>/dev/null || true
      ln -sfn "$HOME_DIR/$f" "$HOME/$f"
    fi
  done

  # ── machine-type ──
  if [[ ! -L "$cfg/machine-type" ]]; then
    echo -n "$MACHINE" > "$cfg/machine-type"
  else
    warn "machine-type is a symlink, skipping write"
  fi

  # ── Scripts ──
  mkdir -p "$bin"
  for script in "$BIN"/*; do
    local name
    name=$(basename "$script")
    [[ "$name" == "__pycache__" ]] && continue
    [[ ! -f "$script" ]] && continue
    rm -f "$bin/$name" 2>/dev/null || true
    ln -sfn "$script" "$bin/$name"
  done

  # ── Fonts ──
  if [[ -d "$REPO/linux/fonts" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    for font_dir in "$REPO/linux/fonts"/*/; do
      local font_name
      font_name=$(basename "$font_dir")
      rm -f "$HOME/.local/share/fonts/$font_name" 2>/dev/null || true
      ln -sfn "$font_dir" "$HOME/.local/share/fonts/$font_name"
    done
    fc-cache -f 2>/dev/null || true
  fi

  # ── Wallpapers ──
  mkdir -p "$HOME/Pictures/wallpapers"
  if [[ -d "$CFG/hypr/wallpapers" ]]; then
    cp -a "$CFG/hypr/wallpapers/." "$HOME/Pictures/wallpapers/" 2>/dev/null || true
  fi

  # ── Cargo env (para .bashrc) ──
  mkdir -p "$HOME/.cargo" 2>/dev/null || true
  touch "$HOME/.cargo/env" 2>/dev/null || true

  ok "Symlinks creados"
}

# ══════════════════════════════════════════════════════════════
# 8. Systemd units
# ══════════════════════════════════════════════════════════════
setup_systemd_units() {
  info "Configurando systemd user units..."
  local units_dir="$HOME/.config/systemd/user"
  mkdir -p "$units_dir"

  # Use $HOME in ExecStart (not hardcoded path)
  local user_home="$HOME"
  local user_bin="$HOME/.local/bin"

  # ── dotfiles-sync ──
  cat > "$units_dir/dotfiles-sync.service" << EOF
[Unit]
Description=Dotfiles auto-sync (pull + commit + push)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${REPO}/scripts/auto-sync.sh
EOF

  cat > "$units_dir/dotfiles-sync.timer" << 'EOF'
[Unit]
Description=Dotfiles sync periodico

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=default.target
EOF

  # ── quickshell ──
  cat > "$units_dir/quickshell.service" << EOF
[Unit]
Description=Quickshell panel (QML bar)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do [ -S "/run/user/%U/wayland-1" ] && exit 0; sleep 0.5; done; exit 0'
ExecStart=${user_bin}/quickshell --no-duplicate
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_CURRENT_DESKTOP=Hyprland
Environment=QT_SCALE_FACTOR=1
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

  # ── clipboard-sync ──
  local peer_user="eztvn@desktop"
  [[ "$MACHINE" == "desktop" ]] && peer_user="eztvn@laptop"
  cat > "$units_dir/clipboard-sync.service" << EOF
[Unit]
Description=Bidirectional Wayland clipboard sync
After=graphical-session.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/wl-paste --watch ${user_bin}/clipboard-sync watch
Restart=always
RestartSec=3
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=CLIPBOARD_PEER=${peer_user}
Environment=CLIPBOARD_SSH_KEY=${user_home}/.ssh/id_ed25519

[Install]
WantedBy=graphical-session.target
EOF

  # ── lan-mouse ──
  cat > "$units_dir/lan-mouse.service" << EOF
[Unit]
Description=LAN-Mouse KVM daemon
After=graphical-session.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'sleep 5; CONFIG=${user_home}/.config/lan-mouse/config.toml; if [ -f "\$CONFIG" ]; then PEER_IP=\$(grep -E "^\s*ips\s*=" "\$CONFIG" | head -1 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1); [ -n "\$PEER_IP" ] && for i in \$(seq 1 30); do ping -c 1 -W 1 "\$PEER_IP" >/dev/null 2>&1 && break; sleep 1; done; fi'
ExecStart=${user_bin}/lan-mouse --capture-backend layer-shell daemon
Restart=always
RestartSec=5
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

  # ── graphical-session-holder ──
  cat > "$units_dir/graphical-session-holder.service" << 'EOF'
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

  # ── hyprpolkitagent ──
  cat > "$units_dir/hyprpolkitagent.service" << 'EOF'
[Unit]
Description=Hyprland polkit authentication agent
After=graphical-session.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'for i in $(seq 1 60); do [ -S "/run/user/%U/wayland-1" ] && exit 0; sleep 0.5; done; exit 0'
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

  # ── voice-daemon ──
  cat > "$units_dir/voice-daemon.service" << EOF
[Unit]
Description=Voice daemon (TTS queue + playback)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${user_bin}/voice-daemon
Restart=on-failure
RestartSec=3
Environment=XDG_RUNTIME_DIR=/run/user/%U
Environment=XDG_SESSION_TYPE=wayland
Environment=PULSE_SERVER=unix:/run/user/%U/pulse/native

[Install]
WantedBy=graphical-session.target
EOF

  # ── dotoold ──
  cat > "$units_dir/dotoold.service" << 'EOF'
[Unit]
Description=dotool daemon (uinput persistente)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/dotoold
Restart=no

[Install]
WantedBy=graphical-session.target
EOF

  # ── scroll-momentum ──
  cat > "$units_dir/scroll-momentum.service" << EOF
[Unit]
Description=Mouse wheel momentum glide
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${user_bin}/scroll-momentum.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

  # ── gamepad-watch ──
  cat > "$units_dir/gamepad-watch.service" << EOF
[Unit]
Description=Detect gamepad connect/disconnect -> game mode
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${user_bin}/gamepad-watch.sh
Restart=always
RestartSec=5
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

  # ── hypr-input-bridge ──
  cat > "$units_dir/hypr-input-bridge.service" << EOF
[Unit]
Description=Hyprland activewindow -> input-remapper preset
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${user_bin}/hypr-input-bridge.sh
Restart=on-failure
RestartSec=2
Environment=XDG_RUNTIME_DIR=/run/user/%U

[Install]
WantedBy=graphical-session.target
EOF

  # ── temperature-log ──
  cat > "$units_dir/temperature-log.service" << EOF
[Unit]
Description=Log thermal sensor temperatures

[Service]
Type=oneshot
ExecStart=${user_bin}/temperature-log.sh
EOF

  cat > "$units_dir/temperature-log.timer" << 'EOF'
[Unit]
Description=Periodic thermal sensor log

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=default.target
EOF

  # ── xdg-desktop-portal-hyprland override ──
  mkdir -p "$units_dir/xdg-desktop-portal-hyprland.service.d"
  cat > "$units_dir/xdg-desktop-portal-hyprland.service.d/override.conf" << 'EOF'
[Service]
Restart=always
RestartSec=2
EOF

  # ── Lid inhibit (laptop only) ──
  if [[ "$MACHINE" == "laptop" ]]; then
    cat > "$units_dir/lid-inhibit.service" << 'EOF'
[Unit]
Description=Flag: suspender al cerrar en AC

[Service]
Type=simple
ExecStart=/usr/bin/sleep infinity

[Install]
WantedBy=graphical-session.target
EOF
  fi

  # ── Habilitar Linger ──
  sudo loginctl enable-linger "$USER" 2>/dev/null || true

  # ── Reload systemd ──
  if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload
  fi

  ok "Systemd units configuradas"
}

# ══════════════════════════════════════════════════════════════
# 9. input-remapper
# ══════════════════════════════════════════════════════════════
setup_input_remapper() {
  info "Configurando input-remapper..."
  $DRY sudo apt install -y input-remapper 2>/dev/null || {
    local src="/tmp/builds/input-remapper"
    $DRY git clone --depth 1 https://github.com/sezanzeb/input-remapper.git "$src" 2>/dev/null || true
    if [[ -d "$src" ]]; then
      $DRY sudo apt install -y python3-dev python3-evdev python3-dbus python3-gi
      (cd "$src" && $DRY sudo pip3 install .)
    fi
  }
  $DRY sudo systemctl enable --now input-remapper 2>/dev/null || true
  ok "input-remapper configurado"
}

# ══════════════════════════════════════════════════════════════
# 10. TTS/STT
# ══════════════════════════════════════════════════════════════
setup_voice() {
  info "Configurando TTS/STT..."

  # Piper TTS
  if ! command -v piper &>/dev/null; then
    $DRY wget -q -O /tmp/piper.zip "https://github.com/rhasspy/piper/releases/latest/download/piper_linux_x86_64.zip"
    $DRY unzip -o /tmp/piper.zip -d /tmp/piper
    $DRY cp /tmp/piper/piper/piper "$HOME/.local/bin/"
    $DRY chmod +x "$HOME/.local/bin/piper"
    ok "piper"
  fi

  # Voces piper
  local voices_dir="$HOME/.local/share/tts/piper/voices"
  mkdir -p "$voices_dir"
  if [[ -d "$REPO/linux/voice/piper-voices" ]]; then
    cp -a "$REPO/linux/voice/piper-voices/." "$voices_dir/"
  fi

  # Kokoro (Python)
  if command -v pip3 &>/dev/null; then
    pip3 install kokoro 2>/dev/null || true
  elif command -v uv &>/dev/null; then
    uv pip install kokoro 2>/dev/null || true
  fi

  ok "Voice configurado (verificar Kokoro y Handy manualmente)"
}

# ══════════════════════════════════════════════════════════════
# 11. GPU mode (laptop hybrid)
# ══════════════════════════════════════════════════════════════
setup_gpu_mode() {
  if [[ "$MACHINE" != "laptop" ]]; then
    return
  fi
  info "Configurando GPU mode (laptop hybrid)..."
  $DRY sudo apt install -y acpi-call-dkms 2>/dev/null || {
    $DRY sudo apt install -y dkms
    $DRY git clone --depth 1 https://github.com/nix-community/acpi_call.git /tmp/acpi_call || true
    if [[ -d /tmp/acpi_call ]]; then
      (cd /tmp/acpi_call && $DRY sudo dkms add . && $DRY sudo dkms install acpi_call/1.0)
    fi
  }
  $DRY sudo modprobe acpi_call 2>/dev/null || true
  ok "acpi_call configurado"
}

# ══════════════════════════════════════════════════════════════
# 12. keyd service
# ══════════════════════════════════════════════════════════════
setup_keyd() {
  info "Configurando keyd..."
  if command -v keyd &>/dev/null; then
    sudo mkdir -p /etc/keyd
    if [[ -f "$REPO/linux/system/keyd/default.conf" ]]; then
      sudo cp "$REPO/linux/system/keyd/default.conf" /etc/keyd/default.conf
    fi
    sudo systemctl enable --now keyd 2>/dev/null || true
    ok "keyd configurado"
  fi
}

# ══════════════════════════════════════════════════════════════
# 13. Git credential helper
# ══════════════════════════════════════════════════════════════
setup_git() {
  info "Configurando git credential helper..."
  git config --global credential."https://github.com".helper "!gh auth git-credential" 2>/dev/null || true
  git config --global credential."https://gist.github.com".helper "!gh auth git-credential" 2>/dev/null || true
  ok "Git configurado"
}

# ══════════════════════════════════════════════════════════════
# 14. dconf settings
# ══════════════════════════════════════════════════════════════
setup_dconf() {
  info "Aplicando dconf settings..."
  dconf write /org/gnome/nautilus/preferences/show-hidden-files "true" 2>/dev/null || true
  dconf write /org/gtk/settings/file-chooser/show-hidden "true" 2>/dev/null || true
  ok "dconf configurado"
}

# ══════════════════════════════════════════════════════════════
# 15. Shell setup
# ══════════════════════════════════════════════════════════════
setup_shell() {
  info "Verificando .bashrc..."
  if [[ -f "$HOME/.bashrc" ]]; then
    if ! grep -q "starship" "$HOME/.bashrc" 2>/dev/null; then
      warn ".bashrc no contiene starship. Verifica que el symlink este correcto."
    fi
  fi
  # Fish shell
  if command -v fish &>/dev/null; then
    chsh -s "$(which fish)" 2>/dev/null || true
  fi
  ok "Shell configurado"
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════
main() {
  echo "═══════════════════════════════════════════════════════════"
  echo "  SETUP UBUNTU — Dotfiles migration from NixOS"
  echo "═══════════════════════════════════════════════════════════"
  echo ""

  preflight
  detect_machine

  echo ""
  echo "Machine: $MACHINE"
  echo "Skip NVIDIA: $SKIP_NVIDIA"
  echo "Skip Builds: $SKIP_BUILDS"
  echo "Dry Run: $DRY_RUN"
  echo ""

  setup_ppas
  install_apt_packages
  install_modern_cli
  install_manual_builds
  install_flatpak_apps
  install_nvidia
  setup_symlinks
  setup_systemd_units
  setup_input_remapper
  setup_keyd
  setup_gpu_mode
  setup_voice
  setup_git
  setup_dconf
  setup_shell

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "  INSTALACION COMPLETA"
  echo "═══════════════════════════════════════════════════════════"
  echo ""
  echo "Pasos pendientes manuales:"
  echo "  1. Reiniciar para NVIDIA drivers: sudo reboot"
  echo "  2. Configurar Tailscale: sudo tailscale up"
  echo "  3. Clave SSH: ssh-keygen -t ed25519"
  echo "  4. Configurar gh: gh auth login"
  echo "  5. Habilitar servicios systemd:"
  echo "     systemctl --user enable --now dotfiles-sync.timer"
  echo "     systemctl --user enable --now quickshell.service"
  echo "     systemctl --user enable --now clipboard-sync.service"
  echo "     systemctl --user enable --now voice-daemon.service"
  echo "  6. Copiar secrets (sunshine creds, ntfy keys, etc.)"
  echo "  7. Recargar shell: exec bash"
  echo ""
  info "El repo ~/dotfiles sigue siendo la fuente de verdad."
  info "Los symlinks apuntan al repo. Edita ahi."
}

main "$@"
