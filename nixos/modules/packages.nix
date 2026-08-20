# Paquetes del sistema (nixpkgs).
{ pkgs, handyPackage }:

with pkgs; [  # ── Shell & terminal ──
  kitty
  fish
  pnpm
  tmux
  fastfetch
  btop
  starship      # usado por .bashrc (eval "$(starship init bash)")
  zoxide        # usado por .bashrc (eval "$(zoxide init bash)")

  # ── Editores ──
  neovim

  # ── Hyprland ecosystem ──
  hyprpaper
  hyprpicker
  hypridle
  hyprlock
  waybar
  # quickshell (barra QML): qtsvg ya viene dentro del paquete. Wrap extra:
  #  - qt5compat → Qt5Compat.GraphicalEffects (FastBlur = gaussian blur)
  #  - qtimageformats → webp/otros formatos en IconImage
  (symlinkJoin {
    name = "quickshell";
    paths = [ quickshell ];
    buildInputs = [ makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/quickshell \
        --prefix QML2_IMPORT_PATH : "${qt6Packages.qt5compat}/${qt6.qtbase.qtQmlPrefix}" \
        --prefix QT_PLUGIN_PATH : "${qt6Packages.qtimageformats}/${qt6.qtbase.qtPluginPrefix}" \
        --set QS_DISABLE_DMABUF 1
    '';
  })
  rofi                  # en nixpkgs reciente rofi-wayland ya se fusiono en rofi
  rofi-emoji
  swaynotificationcenter  # swaync
  swayosd
  avizo
  kanata
  hyprpolkitagent
  brightnessctl
  libnotify
  playerctl
  pamixer
  polkit_gnome           # polkit-gnome (attr en nixpkgs es polkit_gnome)
  wl-clipboard
  wtype                  # Handy paste en Wayland (Hyprland)
  evtest                 # monitor de teclado (super-hold-monitor.sh)
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  swappy
  grim
  networkmanagerapplet
  bluez                  # bluetoothctl para quickshell
  slurp
  imv
  jq

  # ── Navegadores ──
  brave
  google-chrome
  firefox

  # ── Utilidades ──
  git
  gh
  bat
  fzf
  ripgrep
  fd
  eza
  lazygit
  delta                 # git-delta (gitAndTools fue eliminado; delta esta en top level)
  unzip
  zip
  p7zip
  unrar
  curl
  wget
  tldr
  yq
  tree
  rsync
  ncdu
  duf
  htop
  glances
  openssh
  tailscale
  ngrok
  libinput-gestures      # hyprland.lua: libinput-gestures-setup start (laptop)

  # ── Multimedia ──
  vlc
  mpv
  obs-studio
  ffmpeg
  ffmpegthumbnailer
  imagemagick
  gimp
  inkscape
  yt-dlp

  # ── Speech-to-Text ──
  # handy: se usa el paquete del flake upstream (github:cjpais/Handy),
  # pasado como handyPackage desde flake.nix. nixpkgs va atrasado (0.9.1).
  handyPackage

  # ── Compartir teclado/raton entre maquinas ──
  deskflow
  (lan-mouse.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ../../linux/patches/lan-mouse-altgr.patch ];
  }))

  # ── opencode (CLI + Desktop) ──
  opencode
  opencode-desktop

  # ── RStudio ──
  rstudio

  # ── Desarrollo ──
  gcc
  gnumake
  cmake
  clang
  nodejs
  python3
  python3Packages.pip
  python3Packages.evdev   # python3-evdev
  rustc
  cargo
  go
  jdk                     # java-25-openjdk (ajustar version si hace falta)
  maven
  qt6Packages.qtdeclarative  # qmlls + qmlformat (LSP/formatter QML para nvim)

  # ── KDE / GNOME apps de escritorio ──
  kdePackages.dolphin
  kdePackages.ark
  kdePackages.gwenview
  kdePackages.kate
  nautilus
  eog
  gparted
  gnome-disk-utility
  gnome-tweaks
  gnome-extension-manager # gnome-extensions-app (reemplazo moderno)

  # ── Mensajeria / productividad ──
  discord
  telegram-desktop
  thunderbird
  libreoffice
  qbittorrent
  nextcloud-client
  filezilla

  # ── Virtualizacion / contenedores ──
  virt-manager
  qemu
  OVMF                    # edk2-ovmf
  docker-compose

  # ── Gaming ──
  lutris
  wineWow64Packages.full  # wine + wine-mono + wine-gecko (wineWowPackages deprecado)
  dxvk                    # wine-dxvk
  protontricks
  mangohud
  vulkan-tools
  vulkan-validation-layers
  oversteer               # GUI para configurar volantes Logitech (G923, G29, etc.)

  # ── Apps adicionales ──
  localsend
  teams-for-linux
  spotify
  obsidian
  prismlauncher
  moonlight-qt
  # Sunshine (host Moonlight) NO va aqui: lo gestiona el modulo NixOS
  # services.sunshine (configuration.nix). El paquete es por-maquina:
  # desktop → override cudaSupport (NVENC) en hosts/desktop.nix;
  # laptop → plain (software).
  # stremio / gearlever / protonplus: no estan en nixpkgs →
  # se instalan via flatpak (services.flatpak.enable ya activo).

  # ── GTK theming (GDM login screen) ──
  gnome-themes-extra
  adwaita-icon-theme

  # ── Biometria / energia ──
  fprintd                   # fprintd + fprintd-pam (via services.fprintd)
  power-profiles-daemon     # services.power-profiles-daemon

  # ── KVM (compartir teclado/raton entre maquinas) ──
  input-leap
]
