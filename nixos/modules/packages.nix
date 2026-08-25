# Paquetes del sistema (nixpkgs).
{ pkgs, handyPackage }:

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
  ((brave.override { commandLineArgs = "--enable-speech-dispatcher"; }).overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/brave --prefix LD_LIBRARY_PATH : ${pkgs.speechd}/lib
    '';
  }))
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
  # TTS: piper (default) + espeak-ng (fallback) + kokoro (opcional).
  # STT: faster-whisper en dos envs → CPU (voice-stt-cpu) y CUDA
  #      (voice-stt-cuda). CPU por defecto; GPU opcional vía `voice backend`.
  # Voces piper: fetchurl de rhasspy/piper-voices → $out/share/piper-voices
  # (ahí las buscan `speak` y linux/voice/engine.py). No hay package de
  # voces en nixpkgs (verificado).
  piper-tts
  espeak-ng
  sox
  (let
    voiceFetch = { name, path, onnxHash, jsonHash }:
      pkgs.runCommand "piper-voice-${name}" { } ''
        mkdir -p $out/share/piper-voices/${name}
        cp ${pkgs.fetchurl { url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${path}/${name}.onnx"; hash = onnxHash; }} \
          $out/share/piper-voices/${name}/${name}.onnx
        cp ${pkgs.fetchurl { url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${path}/${name}.onnx.json"; hash = jsonHash; }} \
          $out/share/piper-voices/${name}/${name}.onnx.json
      '';
    piperVoices =
      pkgs.symlinkJoin {
        name = "piper-voices";
        paths = map voiceFetch [
          { name = "es_MX-claude-high";
            path = "es/es_MX/claude/high";
            onnxHash = "sha256-181y101fw0hfy7ili73wnjh6gynwxk9afvvymgc2r1b3x9qhmx1y";
            jsonHash = "sha256-0bf14dvmbdayrxq02zw00s4ajm4bdc4wl3bw9lxwpr600gvq3z0s"; }
          { name = "es_MX-ald-medium";
            path = "es/es_MX/ald/medium";
            onnxHash = "sha256-0qwvaxn1jw3v9wadfvvq9r8rl84970xfblkd415f74rw541ki6q1";
            jsonHash = "sha256-0g5hsslc29fhh5dka5lq85ayd765cdpb9lb3s3aiscp5c9p77azg"; }
          { name = "es_ES-davefx-medium";
            path = "es/es_ES/davefx/medium";
            onnxHash = "sha256-05x94bi45i62crywl6wy5ly3b4qkpim8kab5qbj6wcbc38xv0n36";
            jsonHash = "sha256-0hj8qngdzyymcclslxyaglr2y9frh1ill9zzf63z7xijqy3xl38f"; }
          { name = "en_US-amy-medium";
            path = "en/en_US/amy/medium";
            onnxHash = "sha256-063c43bbs0nb09f86l4avnf9mxah38b1h9ffl3kgpixqaxxy99mk";
            jsonHash = "sha256-0xvxjxk59byydx9gj6rdvvydp5zm8mzsrf9vyy6x6299sjs3x8lm"; }
        ];
      };
  in
  piperVoices)
  (let
    sttCpu = pkgs.python313.withPackages (ps: [ ps.faster-whisper ]);
    sttCuda = pkgs.python313.withPackages (ps: [
      (ps.faster-whisper.override {
        ctranslate2 = ps.ctranslate2.override { withCUDA = true; };
      })
    ]);
  in
  [
    (pkgs.writeShellScriptBin "voice-stt-cpu" ''
      exec ${sttCpu}/bin/python3 "$@"
    '')
    (pkgs.writeShellScriptBin "voice-stt-cuda" ''
      exec ${sttCuda}/bin/python3 "$@"
    '')
  ])
  # kokoro (TTS neural, opcional): el daemon conmuta a este motor con
  # `voice` en config (engine = "kokoro"). Voces se descargan en el primer
  # uso (hexgrad/Kokoro-82M) a ~/.cache/huggingface.
  (let
    kokoroEnv = pkgs.python313.withPackages (ps: [ ps.kokoro ]);
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

  # ── GTK theming (GDM login screen) ──
  gnome-themes-extra
  adwaita-icon-theme

  # ── Biometria / energia ──
  fprintd                   # fprintd + fprintd-pam (via services.fprintd)
  power-profiles-daemon     # services.power-profiles-daemon

  # ── KVM (compartir teclado/raton entre maquinas) ──
  input-leap
]
