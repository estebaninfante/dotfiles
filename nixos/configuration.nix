# Configuracion base NixOS — comun a laptop y desktop.
#
# OJO: el archivo hardware-configuration.nix NO se gestiona aqui.
# Se genera por maquina con `nixos-generate-config` durante la instalacion
# (ver README.md). Cada host importa el suyo en hosts/<host>.nix.

{ config, pkgs, lib, handyPackage, machineType, ... }:

{
  imports = [
    # Teclado: layout dvk_prog (Dvorak Programador Español V5) en TTY,
    # X11/GDM y Wayland. Fuente de verdad: linux/xkb/dvk_prog
    ./modules/keyboard.nix
  ];

  # ── Boot ──────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Kernel / hardware base ────────────────────────────────────
  hardware.graphics.enable = true;
  boot.kernelModules = [ "uhid" ]; # Sunshine: emulacion de DS5 controller

  # ── Red ───────────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  # Hostname por maquina (definido en hosts/*.nix)
  networking.hostName = lib.mkDefault "nixos";

  # Firewall
  networking.firewall.enable = true;
  # Si usas tailscale descomenta para no cortar la red mesh:
  # networking.firewall.checkReversePath = "loose";
  # SSH solo via tailscale0 (la laptop sincroniza ~/developing con rsync)
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  # LAN-Mouse: TCP (handshake) + UDP (input data)
  networking.firewall.allowedTCPPorts = [ 4242 ];
  networking.firewall.allowedUDPPorts = [ 4242 ];

  # ── Localizacion ──────────────────────────────────────────────
  # TODO: ajustar a tu zona horaria / locale si difiere
  time.timeZone = "America/Bogota";
  i18n.defaultLocale = "es_ES.UTF-8";
  # NOTA: console.keyMap NO se define aqui — el modulo keyboard.nix
  # lo pone en dvk_prog (tu layout custom).

  # ── Paquetes del sistema ─────────────────────────────────────
  environment.systemPackages = import ./modules/packages.nix { inherit pkgs handyPackage; };

  # Incluir las voces de Piper (share/piper-voices) en el profile del
  # sistema. environment.pathsToLink es una lista restringida: si no se
  # lista este prefijo, buildEnv descarta la salida de `piperVoices`
  # (paquete sin binario, contenido solo en /share/piper-voices).
  environment.pathsToLink = [ "/share/piper-voices" ];

  # ── Variables de sesion ───────────────────────────────────────
  environment.sessionVariables.XDG_DATA_HOME = "\${XDG_DATA_HOME:-$HOME/.local/share}";

  # ── Servicios base ────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true; # wpctl (usado por hyprland.lua)
  };

  # Gnome keyring (hyprland.lua ejecuta gnome-keyring-daemon)
  services.gnome.gnome-keyring.enable = true;

  # Huella dactilar (fprintd + fprintd-pam).
  # Leitor Elan 04f3:0c4b SOLO en laptop (Lenovo). El driver upstream de
  # libfprint es flaky (enroll falla con "protocol error", "enroll-disconnected").
  # TODO driver oficial de Lenovo (libfprint-2-tod1-elan) match exacto PID.
  services.fprintd = {
    enable = true;
    # Driver TOD propietario Elan: hardware laptop. En desktop no hay lector
    # → driver inutil; evitarlo para no arrastrar el paquete a maquinas sin Leitor.
    tod = lib.mkIf (machineType == "laptop") {
      enable = true;
      driver = pkgs.libfprint-2-tod1-elan;
    };
  };

  # Power profiles: power-profiles-daemon (misma API UPower.PowerProfiles
  # que usa power-mode.sh via busctl).

  # Sync de archivos
  services.syncthing.enable = true;
  services.syncthing.user = "eztvn";
  services.syncthing.dataDir = "/home/eztvn/.local/state/syncthing";

  # VPN mesh
  services.tailscale.enable = true;

  # ── Sunshine (host Moonlight) ─────────────────────────────────
  # autoStart=false: con linger + graphical-session-holder, graphical-session.target
  # se activa al BOOT (antes del login) y sunshine arrancaria sin compositor
  # Wayland → captura via KMS → agarra /dev/dri/card1 → GDM "No GPUs found" →
  # cuelga el login. Se arranca post-login desde hyprland.lua.
  # capSysAdmin=false: captura via Wayland (portal), no KMS.
  # package por maquina: desktop usa override cudaSupport (NVENC) en hosts/desktop.nix.
  services.sunshine = {
    enable = true;
    openFirewall = true;
    autoStart = false;
    capSysAdmin = false;
  };

  # SSH server (solo tailnet): la laptop sincroniza ~/developing con rsync.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Flatpak (apps que no esten en nixpkgs)
  services.flatpak.enable = true;

  # ── Virtualizacion / contenedores ─────────────────────────────
  virtualisation.libvirtd.enable = true;
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;

  # ── Gaming ────────────────────────────────────────────────────
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # ── nix-ld: binarios pre-compilados FHS (antigravity-ide, etc.) ──
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    nspr
    nss
    nss_latest
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    gtk3
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libgbm
    libglvnd
    libxkbcommon
    pango
    udev
    xorg.libxcb
    libdrm
    mesa
    libnotify
    libsecret
    xorg.libXScrnSaver
    xorg.xcbutilkeysyms
  ];

  # ── Login manager: GDM ──
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.accounts-daemon.enable = true;

  # ── keyd: remapeo de teclado (SERVICIO DE SISTEMA) ────────────
  # Módulo oficial NixOS services.keyd: crea /etc/keyd/default.conf,
  # habilita hardware.uinput y corre keyd como root en boot
  # (aplica en GDM/login, TTY y toda sesión). Fuente de verdad:
  # linux/system/keyd/default.conf (aplica a todas las maquinas).
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          # Caps Lock como Super (keyd, no XKB): aplica en TTY/GDM.
          capslock = "leftmeta";
          # overload(numpad, layer(alt)): tap = alt, hold = numpad layer.
          # layer(alt) (en vez de leftalt) evita el warning de keyd y
          # preserva el comportamiento de Alt en tap.
          leftalt = "overload(numpad, layer(alt))";
          enter = "overload(nav, enter)";
          # Chording: space+AltGr (rightalt) = escape, sin sacrificar space.
          "space+rightalt" = "escape";
        };
        nav = {
          a = "left";
          s = "left";
          d = "down";
          f = "right";
          e = "up";
        };
        numpad = {
          a = "kpplus";
          s = "kpminus";
          d = "kpasterisk";
          f = "kpslash";
          g = "kpequal";
          p = "kpequal";
          m = "1";
          comma = "2";
          dot = "3";
          j = "4";
          k = "5";
          l = "6";
          u = "7";
          i = "8";
          o = "9";
          semicolon = "0";
        };
      };
      # Capa compuesta al final (extraConfig se anade DESPUES de settings):
      # keyd exige que las capas compuestas se definan tras sus capas base.
      # Garantiza Ctrl+Alt+F1..F12 (cambio de TTY) aunque leftalt tenga
      # overload(numpad): al sostener leftalt se activa numpad (no alt), y
      # esta compuesta con control re-emite ctrl+alt+F<N> con precedencia.
      extraConfig = ''
        [control+numpad]
        f1=C-A-f1
        f2=C-A-f2
        f3=C-A-f3
        f4=C-A-f4
        f5=C-A-f5
        f6=C-A-f6
        f7=C-A-f7
        f8=C-A-f8
        f9=C-A-f9
        f10=C-A-f10
        f11=C-A-f11
        f12=C-A-f12
      '';
    };
  };

  # ── Hyprland ──────────────────────────────────────────────────
  programs.hyprland = {
    enable = true;
    xwayland.enable = true; # hyprland.lua usa force_zero_scaling en xwayland
  };

  # Portales xdg (necesarios para pantalla compartida / file pickers)
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-hyprland ];
  };

  # ── Fuentes ──────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    fira-code            # fira-code-fonts
    jetbrains-mono       # jetbrains-mono-fonts
    font-awesome         # fontawesome-fonts
    noto-fonts           # google-noto-sans-fonts
    noto-fonts-color-emoji # google-noto-emoji-fonts (renombrado en nixpkgs)
    powerline-fonts      # powerline-fonts
    nerd-fonts.jetbrains-mono  # hyprlock usa "JetBrainsMono Nerd Font"
  ];

  # ── Power profiles (power-profiles-daemon) ──────────────────
  # power-mode.sh habla con org.freedesktop.UPower.PowerProfiles via busctl.
  services.power-profiles-daemon.enable = true;

  # ── UPower ──────────────────────────────────────────────────
  # Daemon de batería. Lo consume quickshell (Quickshell.Services.UPower)
  # para el módulo de batería de la barra. power-profiles-daemon solo
  # provee la API UPower.PowerProfiles, no el estado de batería.
  services.upower.enable = true;

  # ── GPU NVIDIA: guarda automática por fuente de energía ──────
  # Al desconectar el cargador (AC online=0) → gpu-mode.sh guard pone
  # la dGPU en battery (D3cold, ahorro). Al conectar no toca nada.
  # Solo laptop (hibrida); en desktop no hay fuente Mains que dispare.
  systemd.services.gpu-power-guard = lib.mkIf (machineType == "laptop") {
    description = "NVIDIA GPU: switch a battery mode al desenchufar";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /home/eztvn/dotfiles/linux/bin/gpu-mode.sh guard";
    };
  };

  services.udev.extraRules = lib.mkIf (machineType == "laptop") ''
    # Flujo de energía Mains (AC) → dispara la guarda de la GPU.
    # Solo existe un device type=Mains en laptops; en desktop no → no dispara.
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl --no-block start gpu-power-guard.service"
  '';

  # ── fprintd: restart tras resume ──────────────────────────────
  # Solo laptop: el desktop no suspende en este patron.
  systemd.services.restart-fprintd-on-resume = lib.mkIf (machineType == "laptop") {
    description = "Restart fprintd after suspend/resume";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StopWhenUnneeded = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${pkgs.systemd}/bin/systemctl restart fprintd.service";
    };
  };

  # ── Usuario ───────────────────────────────────────────────────
  users.users.eztvn = {
    isNormalUser = true;
    description = "estebaninfante";
    # Llaves SSH de ambas maquinas (rsync sync-developing.sh + ssh bidireccional
    # laptop <-> desktop). Llaves publicas: se commitean, son publicas.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG3fn5nhRUS9KjWAnKYKDPGsTFnnh+Ms4h5d8C7hGk1u eztvn@laptop"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINodW8jCv6unpL0ViAN24VO8UFwAogy1ffvUdGNT/zYE eztvn@desktop"
    ];
    # input/uinput: keyd corre como user service (home.nix) y necesita
    # leer /dev/input/* y crear /dev/uinput para remapear teclado.
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "docker" "video" "audio" "input" "uinput" ];
    # TODO: definir contrasena inicial tras instalar:
    #   sudo passwd eztvn
    # o usar hashedPassword con `mkpasswd -m sha-512`.
  };

  # NOPASSWD para scripts del repo (equivalente a nixos/modules/sudoers.nix)
  security.sudo.extraRules = import ./modules/sudoers.nix;
  security.sudo.wheelNeedsPassword = false;

  # hyprlock necesita su propia config PAM en NixOS para poder autenticar
  # (cada app de bloqueo requiere /etc/pam.d/hyprlock — sin esto la
  # contrasena siempre es rechazada).
  # fprintAuth = true: desbloqueo por huella (silencioso si no hay lector).
  # NOTA: el login de GDM NO usa fprintAuth en login/gdm-password — GDM
  # maneja la huella aparte con el servicio PAM gdm-fingerprint en paralelo
  # (gdm.nix: login.fprintAuth=false a proposito, no pisar).
  security.pam.services.hyprlock = {
    fprintAuth = true;
  };

  # ── Nix ───────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 14d";

  # Cachix de handy (github:cjpais/Handy): evita compilar handy desde fuente
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://handy-computer.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "handy-computer.cachix.org-1:Sihzctn6DC0CJM5QeL+9nBEL3CL8c33m777C+eIv748="
  ];

  nixpkgs.config.allowUnfree = true;

  # ── Overlay: waybar patched for Lua IPC dispatch (PR #5013) ──────
  # Waybar v0.15.0 envia comandos dispatch con sintaxis legacy
  # ("dispatch workspace N"), pero Hyprland 0.54+ con config Lua espera
  # la nueva API ("hl.dsp.focus({ workspace = N })"). Esto rompe el
  # on-click: activate en workspaces y scroll.
  nixpkgs.overlays = [
    (final: prev: {
      waybar = prev.waybar.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ../linux/patches/waybar-lua-dispatch.patch
        ];
      });
    })
  ];

  system.stateVersion = "25.05";
}
