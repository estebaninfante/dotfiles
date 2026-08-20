# Paquetes del sistema (nixpkgs).
{ pkgs, handyPackage }:

let
  inherit (pkgs) fetchurl runCommand;

  # Voces de Piper (rhasspy/piper-voices). No estan en nixpkgs → se
  # descargan declarativamente. Solo voces es:
  #   - es_MX-ald-medium     (favorita: espanol mexicano MASCULINO, Aldo)
  #   - es_MX-claude-high    (alternativa: espanol mexicano femenino, alta calidad)
  #   - es_ES-davefx-medium  (alternativa: castellano)
  #   - en_US-joe-medium     (ingles EEUU masculino, Joe; usado por opencode)
  # Cada voz = .onnx + .onnx.json (config sample_rate, id_map, etc.)
  piperVoice = path: sha256:
    fetchurl {
      url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${path}";
      inherit sha256;
    };

  piperVoices = runCommand "piper-voices" { } ''
    mkdir -p $out/share/piper-voices/es_MX-claude-high
    mkdir -p $out/share/piper-voices/es_ES-davefx-medium
    mkdir -p $out/share/piper-voices/es_MX-ald-medium
    mkdir -p $out/share/piper-voices/en_US-joe-medium
    cp ${piperVoice "es/es_MX/claude/high/es_MX-claude-high.onnx" "181y101fw0hfy7ili73wnjh6gynwxk9afvvymgc2r1b3x9qhmx1y"} \
      $out/share/piper-voices/es_MX-claude-high/es_MX-claude-high.onnx
    cp ${piperVoice "es/es_MX/claude/high/es_MX-claude-high.onnx.json" "0bf14dvmbdayrxq02zw00s4ajm4bdc4wl3bw9lxwpr600gvq3z0s"} \
      $out/share/piper-voices/es_MX-claude-high/es_MX-claude-high.onnx.json
    cp ${piperVoice "es/es_ES/davefx/medium/es_ES-davefx-medium.onnx" "05x94bi45i62crywl6wy5ly3b4qkpim8kab5qbj6wcbc38xv0n36"} \
      $out/share/piper-voices/es_ES-davefx-medium/es_ES-davefx-medium.onnx
    cp ${piperVoice "es/es_ES/davefx/medium/es_ES-davefx-medium.onnx.json" "0hj8qngdzyymcclslxyaglr2y9frh1ill9zzf63z7xijqy3xl38f"} \
      $out/share/piper-voices/es_ES-davefx-medium/es_ES-davefx-medium.onnx.json
    cp ${piperVoice "es/es_MX/ald/medium/es_MX-ald-medium.onnx" "0qwvaxn1jw3v9wadfvvq9r8rl84970xfblkd415f74rw541ki6q1"} \
      $out/share/piper-voices/es_MX-ald-medium/es_MX-ald-medium.onnx
    # ald trae "phoneme_type": "PhonemeType.ESPEAK" (formato v1.0.0), que
    # piper-tts 1.4.2 rechaza (enum espera "espeak") → se normaliza al copiar.
    cp ${piperVoice "es/es_MX/ald/medium/es_MX-ald-medium.onnx.json" "0g5hsslc29fhh5dka5lq85ayd765cdpb9lb3s3aiscp5c9p77azg"} \
      $out/share/piper-voices/es_MX-ald-medium/es_MX-ald-medium.onnx.json
    sed -i 's/PhonemeType\.ESPEAK/espeak/' \
      $out/share/piper-voices/es_MX-ald-medium/es_MX-ald-medium.onnx.json
    cp ${piperVoice "en/en_US/joe/medium/en_US-joe-medium.onnx" "01mg7f5piyvhdfx2s89088xpjnn51i81d76zginw9ndq441wxbsq"} \
      $out/share/piper-voices/en_US-joe-medium/en_US-joe-medium.onnx
    cp ${piperVoice "en/en_US/joe/medium/en_US-joe-medium.onnx.json" "0cxd3a73dv6qaqikmynvdyg73431y3w7w94m0nav2p3rnc858v9x"} \
      $out/share/piper-voices/en_US-joe-medium/en_US-joe-medium.onnx.json
  '';
in

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

  # ── Text-to-Speech ──
  # piper-tts (binary `piper`) + voces espanolas descargadas
  # declarativamente. El script `speak` (~/.local/bin) hace la
  # sintesis + reproduccion directa vía PipeWire.
  piper-tts
  piperVoices

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
  wineWowPackages.full  # wine + wine-mono + wine-gecko (wineWowPackages deprecado)
  dxvk                    # wine-dxvk
  protontricks
  mangohud
  vulkan-tools
  vulkan-validation-layers
  linux-wallpaperengine  # wallpapers animados de Steam (daemon nativo)

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
