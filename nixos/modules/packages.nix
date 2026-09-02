# Paquetes del sistema (nixpkgs).
{ pkgs, handyPackage, piperVoices }:

with pkgs; [  # ── Shell & terminal ──
  kitty
  warp-terminal
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
  swaynotificationcenter  # swaync
  swayosd
  avizo
  kanata
  hyprpolkitagent
  hyprpaper
  brightnessctl
  libnotify
  playerctl
  pamixer
  polkit_gnome           # polkit-gnome (attr en nixpkgs es polkit_gnome)
  wl-clipboard
  wtype                  # Handy paste en Wayland (Hyprland)
  dotool                 # inyeccion uinput: Warp ignora eventos de wtype (virtual-keyboard)
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
  (google-chrome.override { commandLineArgs = "--enable-speech-dispatcher"; })
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
  socat                 # hypr-input-bridge.sh: lee eventos socket2 de Hyprland
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
  audacity

  # ── Speech-to-Text ──
  # handy: se usa el paquete del flake upstream (github:cjpais/Handy),
  # pasado como handyPackage desde flake.nix. nixpkgs va atrasado (0.9.1).
  handyPackage

  # ── Voz local (sistema de voz: STT + TTS, ver linux/voice + CLI voice) ──
  # TTS: router por-idioma (kokoro neural / piper / espeak-ng fallback).
  # STT: Handy (whisper local, GPU via Vulkan o CPU) — handyPackage, en el
  #      bloque anterior. Sin faster-whisper/CUDA.
  # Kokoro usa torch: en desktop lleva CUDA (nixpkgs.config.cudaSupport=true
  # en hosts/desktop.nix → build largo desde fuente); en laptop queda CPU.
  # Voces piper: definidas en flake.nix (voiceFetch/piperVoices) y pasadas
  # como arg. Viven en ~/.local/share/tts/piper/voices via home-manager
  # (NO en /sw/share: system-path solo expone bin, no share).
  piper-tts
  espeak-ng
  sox
  (let
    # spacy-models.en_core_web_sm: modelo para voces EN de kokoro (misaki[en]
    # lanza spacy en runtime; sin el modelo falla "No package installer").
    kokoroEnv = pkgs.python313.withPackages (ps: [
      ps.kokoro
      ps.spacy-models.en_core_web_sm
    ]);
  in
  pkgs.writeShellScriptBin "voice-kokoro" ''
    repo="''${VOICE_REPO:-$HOME/dotfiles}"
    test -f "$repo/linux/voice/kokoro.py" \
      || { echo "voice-kokoro: repositorio no encontrado" >&2; exit 1; }
    exec ${kokoroEnv}/bin/python3 "$repo/linux/voice/kokoro.py" "$@"
  '')

  # ── Compartir teclado/raton entre maquinas ──
  deskflow
  (lan-mouse.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ../../linux/patches/lan-mouse-altgr.patch ];
  }))

  # ── opencode (CLI + Desktop) ──
  opencode
  opencode-desktop

  # ── pi coding agent (earendil-works/pi) ──
  pi-coding-agent

  # ── Orca ADE (Agent Development Environment, stablyai/orca) ──
  # No esta en nixpkgs: AppImage de GitHub Releases envuelto en FHS (wrapType2)
  # + .desktop e icono extraidos del propio AppImage.
  (let
    orcaAdeSrc = fetchurl {
      url = "https://github.com/stablyai/orca/releases/download/v1.4.188/orca-linux.AppImage";
      hash = "sha256-LnDLXhmXQeVgKnBgglV1MZ9eA7wvqkuJzScyjz9V1LQ=";
    };
    orcaAdeWrapped = appimageTools.wrapType2 {
      pname = "orca-ade";
      version = "1.4.188";
      src = orcaAdeSrc;
    };
    orcaAdeExtracted = appimageTools.extract {
      pname = "orca-ade";
      version = "1.4.188";
      src = orcaAdeSrc;
    };
  in
  symlinkJoin {
    name = "orca-ade";
    paths = [ orcaAdeWrapped ];
    postBuild = ''
      mkdir -p $out/share/applications
      install -Dm644 ${orcaAdeExtracted}/orca-ide.png \
        $out/share/icons/hicolor/512x512/apps/orca-ide.png
      substitute ${orcaAdeExtracted}/orca-ide.desktop $out/share/applications/orca-ade.desktop \
        --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=orca-ade %U'
      sed -i '/X-AppImage-Version/d' $out/share/applications/orca-ade.desktop
    '';
  })

  # ── RStudio ──
  rstudio

  # ── Desarrollo ──
  gcc
  gnumake
  cmake
  clang
  nodejs
  live-server # servidor estatico con recarga (live-server.nvim)
  (python3.withPackages (ps: with ps; [
    pip
    evdev                  # python3-evdev
    openinference-instrumentation-openai
  ]))
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
  calibre
  qbittorrent
  nextcloud-client
  filezilla

  # ── Virtualizacion / contenedores ──
  virt-manager
  qemu
  OVMF                    # edk2-ovmf
  docker-compose

  # ── Gaming ──
  heroic                  # Heroic Games Launcher (Epic/GOG/Amazon)
  # cartridges: parche para crash con biblioteca vacia (label=games_no int).
  (cartridges.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ../../linux/patches/cartridges-games-label.patch ];
  }))
  cartridges              # biblioteca unificada (Steam/Heroic/Lutris) — modo juegos
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

  # ── Accesibilidad ──
  orca                     # navegador de pantalla (screen reader)

  # ── GTK theming (GDM login screen) ──
  gnome-themes-extra
  adwaita-icon-theme

  # ── Biometria / energia ──
  fprintd                   # fprintd + fprintd-pam (via services.fprintd)
  power-profiles-daemon     # services.power-profiles-daemon

  # ── KVM (compartir teclado/raton entre maquinas) ──
  input-leap
]
