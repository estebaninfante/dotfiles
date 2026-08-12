# Paquetes del sistema (nixpkgs).
{ pkgs }:

with pkgs; [  # ── Shell & terminal ──
  kitty
  fish
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
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  swappy
  grim
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
  handy

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

  # ── Apps adicionales ──
  localsend
  zapzap
  teams-for-linux
  spotify
  obsidian
  prismlauncher
  moonlight-qt
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
