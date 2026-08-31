  # Configuracion base NixOS — comun a laptop y desktop.
#
# OJO: el archivo hardware-configuration.nix NO se gestiona aqui.
# Se genera por maquina con `nixos-generate-config` durante la instalacion
# (ver README.md). Cada host importa el suyo en hosts/<host>.nix.

{ config, pkgs, lib, handyPackage, machineType, piperVoices, refind-minimal-theme, ... }:

let
  # Tema minimal para rEFInd (evanpurkhiser/rEFInd-minimal). Se copia a
  # /boot/EFI/refind/themes/rEFInd-minimal/ via
  # boot.loader.refind.additionalFiles (dest = themes/rEFInd-minimal/*,
  # relativo a refind_dir). inputs flake = source del store → leer FS ok.
  # theme.conf se referencia con `include themes/rEFInd-minimal/theme.conf`.
  # Los values (source paths) se pasan sin string context: builtins.toJSON
  # de refind-install.json RECHAZA strings con context de store path.
  flattenDir = dir:
    let entries = builtins.readDir dir;
    in builtins.concatMap
      (name:
        let type = entries.${name};
        in if type == "directory" then flattenDir "${dir}/${name}" else [ "${dir}/${name}" ])
      (builtins.attrNames entries);
  refindThemeFiles = flattenDir refind-minimal-theme;
  refindThemeAdditional = lib.listToAttrs (map
    (file: {
      name = builtins.unsafeDiscardStringContext
        "themes/rEFInd-minimal/${lib.removePrefix "${refind-minimal-theme}/" file}";
      value = builtins.unsafeDiscardStringContext file;
    })
    refindThemeFiles);
in

{
  imports = [
    # Teclado: layout dvk_prog (Dvorak Programador Español V5) en TTY,
    # X11/GDM y Wayland. Fuente de verdad: linux/xkb/dvk_prog
    ./modules/keyboard.nix
  ];

  # ── Boot ──────────────────────────────────────────────────────
  # rEFInd: menú gráfico de arranque. Auto-detecta Windows (EFI/Microsoft/
  # bootmgfw.efi) además del kernel NixOS. Se elige entre ambos al bootear.
  # systemd-boot silenciaba grub (mkDefault false). Sin el, grub vuelve a
  # su default (!isContainer = true) y fuerza la assertion grub.devices.
  # Lo desactivamos explicitamente: rEFInd es el unico bootloader.
  boot.loader.grub.enable = false;
  boot.loader.refind.enable = true;
  boot.loader.refind.efiInstallAsRemovable = false;
  # Tema minimal para rEFInd (evanpurkhiser/rEFInd-minimal). Se copia a
  # /boot/EFI/refind/themes/rEFInd-minimal/ y lo activa via include.
  # theme.conf (evanpurkhiser) NO trae timeout/default_selection, asi que
  # no sobreescribe los nuestros. Solo showtools shutdown.
  boot.loader.refind.additionalFiles = refindThemeAdditional;
  # Generaciones NixOS visibles en el menu rEFInd. El generador ordena
  # descendente (la mas reciente primero) y default_selection la auto-bootea
  # tras el timeout. 1 = solo la ultima gen, un menu limpio (Windows + NixOS).
  # Rollback a una gen anterior se hace por terminal (nixos-rebuild --rollback
  # o boot manual del perfil), no desde el menu boot.
  boot.loader.refind.maxGenerations = 1;
  # El generador refind-install.py escribe SIEMPRE `default_selection 2`
  # tras extraConfig (NixOS default) + `timeout {boot.loader.timeout}`.
  # Se setea boot.loader.timeout (no en extraConfig) para que no haya
  # timeout duplicado/confuso (extraConfig va ANTES del que genera el script).
  boot.loader.timeout = 8;
  boot.loader.refind.extraConfig = ''
    use_graphics_for linux,windows
    # scanfor explícito: SOLO internal (Windows en el ESP) + manual (entradas
    # del config abajo) + firmware (entrada UEFI). El default incluye external,
    # que escanea particiones (btrfs/ext4) y arma entradas sin init= que bootean
    # a la raíz (el "ícono NixOS → Root"). Sin external el menú queda limpio:
    # Windows + NixOS (única, manual) + UEFI.
    scanfor internal,manual,firmware
    # systemd-boot remnants: /efi/systemd era del bootloader anterior.
    dont_scan_dirs /efi/systemd
    include themes/rEFInd-minimal/theme.conf
  '';
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Kernel / hardware base ────────────────────────────────────
  hardware.graphics.enable = true;
  boot.kernelModules = [ "uhid" "hid-logitech-new" ]; # Sunshine + Logitech G923 FFB

  # ── Red ───────────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = lib.mkIf (machineType == "laptop") true;
  # Dispatcher NM: reinicia lan-mouse en redes de casa y vigila conflictos
  # de la IP estática LAN (fuente de verdad: linux/system/NetworkManager/)
  networking.networkmanager.dispatcherScripts = [
    {
      source = ../linux/system/NetworkManager/dispatcher.d/90-lan-mouse;
      type = "basic";
    }
  ];
  # kvm-ensure.sh: lógica de IP KVM flotante + ruta simétrica, fuente única
  # compartida por el dispatcher y el timer de safety net.
  environment.etc."NetworkManager/kvm-ensure.sh".source =
    ../linux/system/NetworkManager/kvm-ensure.sh;
  environment.etc."NetworkManager/kvm-ensure.sh".mode = "0555";
  # Safety net: re-asegura IP KVM y ruta simétrica aunque un evento NM se
  # pierda (ej. device que llega antes que la IP, dock USB re-enumerado).
  systemd.services.kvm-ensure = {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/etc/NetworkManager/kvm-ensure.sh";
    };
  };
  systemd.timers.kvm-ensure = {
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
    wantedBy = [ "timers.target" ];
  };
  hardware.bluetooth.enable = true;
  # Hostname por maquina (definido en hosts/*.nix)
  networking.hostName = lib.mkDefault "nixos";

  # Firewall
  networking.firewall.enable = true;
  # Reverse path "loose": con dos interfaces en el mismo subnet (dock
  # ethernet + WiFi en laptop), las respuestas del peer KVM pueden entrar
  # por la interfaz no-preferida; estricto las dropea.
  networking.firewall.checkReversePath = "loose";
  # SSH solo via tailscale0.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  # LAN-Mouse: TCP (handshake) + UDP (input data)
  # Syncthing: TCP/UDP 22000 + descubrimiento local UDP 21027.
  # Proyecto leia: Next dev server en laptop, puerto 3100.
  # LocalSend: TCP (transferencia) + UDP (descubrimiento local), puerto 53317.
  networking.firewall.allowedTCPPorts = [ 4242 22000 3100 53317 ];
  networking.firewall.allowedUDPPorts = [ 4242 21027 22000 53317 ];
  networking.nameservers = [ "1.1.1.1" "8.8.8.8"];

  # ── Localizacion ──────────────────────────────────────────────
  # TODO: ajustar a tu zona horaria / locale si difiere
  time.timeZone = "America/Bogota";
  i18n.defaultLocale = "es_ES.UTF-8";
  # NOTA: console.keyMap NO se define aqui — el modulo keyboard.nix
  # lo pone en dvk_prog (tu layout custom).

  # ── Paquetes del sistema ─────────────────────────────────────
  environment.systemPackages = import ./modules/packages.nix { inherit pkgs handyPackage piperVoices; };

  # Fix "disable touchpad while typing" con keyd (ver archivo):
  # keyd re-emite teclas por su teclado virtual (externo para libinput), asi
  # que el touchpad nunca se desactiva al teclear. Estos quirks marcan los
  # virtuales de keyd como internos. Fuente de verdad: linux/system/libinput/.
  environment.etc."libinput/local-overrides.quirks".source =
    ../linux/system/libinput/local-overrides.quirks;

  # ── Entorno de sesión ────────────────────────────────────────
  # Garantiza ~/.local/bin (rtk y scripts propios), ~/.opencode/bin y
  # ~/.cargo/bin en TODA sesión (Warp, GUI, systemd user), incluso cuando
  # la app no pasa por .bashrc interactivo. Prepend idempotente.
  environment.extraInit = ''
    for d in "$HOME/.local/bin" "$HOME/.opencode/bin" "$HOME/.cargo/bin"; do
      if [ -d "$d" ]; then
        case ":$PATH:" in
          *":$d:"*) ;;
          *) PATH="$d:$PATH" ;;
        esac
      fi
    done
    export PATH
  '';

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
  services.syncthing.settings = {
    devices = {
      laptop = {
        id = "CL2PRT2-ZIZVS42-UFZJQL4-ATHFXNT-FA7XYJC-AIWBAVW-HAM52GU-25TMEAL";
        addresses = [
          "tcp://192.168.1.240:22000"
          "quic://192.168.1.240:22000"
          "tcp://100.81.24.119:22000"
          "quic://100.81.24.119:22000"
        ];
      };
      desktop = {
        id = "EMW3K4G-36KQAKL-73EKS3M-53AXVRU-PTCOZFR-5VOXQJL-6YTELPO-R2QHLAE";
        addresses = [
          "tcp://192.168.1.241:22000"
          "quic://192.168.1.241:22000"
          "tcp://100.118.58.7:22000"
          "quic://100.118.58.7:22000"
        ];
      };
    };
    folders.developing = {
      id = "developing";
      label = "Developing";
      path = "/home/eztvn/developing";
      type = "sendreceive";
      devices = [ "laptop" "desktop" ];
      rescanIntervalS = 10;
      fsWatcherEnabled = true;
      ignorePerms = true;
      versioning = {
        type = "simple";
        params.keep = "5";
      };
    };
    folders.books = {
      id = "books";
      label = "Books";
      path = "/home/eztvn/books";
      type = "sendreceive";
      devices = [ "laptop" "desktop" ];
      rescanIntervalS = 10;
      fsWatcherEnabled = true;
      ignorePerms = true;
      versioning = {
        type = "simple";
        params.keep = "5";
      };
    };
  };

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

  # SSH server (solo tailnet), para administracion entre maquinas.
  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # Flatpak (apps que no esten en nixpkgs)
  # Declarativo: sincronizado entre maquinas via rebuild.
  services.flatpak = {
    enable = true;
    remotes = [{ name = "flathub"; location = "https://dl.flathub.org/repo/flathub.flatpakrepo"; }];
    packages = [
      "com.stremio.Stremio"
      # "it.mijorus.gearlever" / "com.vixalien.protonplus": en README pero
      # no instalados en ninguna maquina. Anadir aqui para instalarlos.
    ];
  };

  # ── Virtualizacion / contenedores ─────────────────────────────
  virtualisation.libvirtd.enable = true;
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;

  # ── Gaming ────────────────────────────────────────────────────
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # Logitech G923 (volante racing): oversteer para configurar FFB/range.
  # G923 PS/PC necesita new-lg4ff; hid-generic solo expone ejes, sin FFB.
  boot.extraModulePackages = [ config.boot.kernelPackages."new-lg4ff" ];
  services.udev.packages = with pkgs; [ oversteer ];

  # ── input-remapper: gamepad -> teclado/raton (modo consola) ──
  # Daemon de sistema que "roba" el pad (grab evdev) y re-emite teclado
  # virtual (uinput) -> funciona en Wayland nativo. Presets en
  # ~/.config/input-remapper-2 (copiados por home-manager, ver home.nix).
  # El switch UI/juego lo gestiona linux/bin/hypr-input-bridge.sh (user
  # service). enableUdevRules=false: el autoload lo lanza gamepad-watch.sh.
  services.input-remapper.enable = true;

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
      ids = [ "*" "m:beef:dead" ];
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
          middlemouse = "f7";
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

  # Si no hay actividad, suspender conserva batería mucho mejor que dejar
  # pantalla apagada indefinidamente. Solo laptop.
  services.logind.settings.Login = lib.mkIf (machineType == "laptop") {
    IdleAction = "suspend";
    IdleActionSec = "15min";
  };

  # ── Ahorro laptop: guarda automática por fuente de energía ────
  # Al desconectar cargador → power-saver + dGPU en D3cold.
  # En AC no cambia selección manual del usuario.
  systemd.services.gpu-power-guard = lib.mkIf (machineType == "laptop") {
    description = "Laptop: aplicar ahorro máximo al desenchufar";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
      ExecStart = "${pkgs.bash}/bin/bash /home/eztvn/dotfiles/linux/bin/battery-power-guard.sh";
    };
  };

  # Corte FÍSICO (ACPI _OFF) de la dGPU al boot. Tras resume lo re-aplica
  # powerManagement.powerUpCommands (el firmware reenciende el rail en
  # suspend/resume; esto lo vuelve a apagar).
  systemd.services.gpu-acpi-off = lib.mkIf (machineType == "laptop") {
    description = "Laptop: apagar dGPU por ACPI (corte físico)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
      ExecStart = "${pkgs.bash}/bin/bash -c 'sleep 5 && /home/eztvn/dotfiles/linux/bin/gpu-mode.sh off'";
    };
  };

  # Re-aplicar corte ACPI de la dGPU después de cada resume.
  powerManagement.powerUpCommands = lib.mkIf (machineType == "laptop") ''
    ${pkgs.bash}/bin/bash -c 'sleep 5; /home/eztvn/dotfiles/linux/bin/gpu-mode.sh off' &
  '';

  # powertop --auto-tune al boot: runtime PM agresivo (PCI, SATA, audio).
  powerManagement.powertop.enable = lib.mkIf (machineType == "laptop") true;

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

  # ── Higiene de sueño: apagado automático 21:00 ────────────────
  # Timer dispara bedtime.service a las 20:55 → aviso + poweroff a las 21:00.
  # Persistent=true: si la máquina estaba apagada a las 21:00 y se enciende
  # después, el trigger perdido compensa al boot → avisa y apaga igual.
  # Escape puntual: `bedtime-skip` (flag /run/bedtime-skip con fecha de hoy,
  # muere al reboot). Fuente de verdad: linux/bin/bedtime.sh
  systemd.services.bedtime = {
    description = "Apagado 21:00 (higiene de sueño)";
    serviceConfig = {
      Type = "oneshot";
      Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin";
      ExecStart = "${pkgs.bash}/bin/bash /home/eztvn/dotfiles/linux/bin/bedtime.sh";
    };
  };
  systemd.timers.bedtime = {
    description = "Aviso 20:55 → apagado 21:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 20:55:00";
      Persistent = true;
      Unit = "bedtime.service";
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

  # Tope GLOBAL de paralelismo (default de nix = auto = 24 cores) →
  # un rebuild sin NIX_CONFIG (ej. rebuild manual olvidado) ya no
  # satura la maquina ni la congela (OOM) durante builds CUDA/torch.
  # El cliente puede pedir mas via NIX_CONFIG (honrado aun via daemon,
  # verificado: max-jobs=2 => max 2 builds concurrentes).
  nix.settings.max-jobs = 4;
  nix.settings.cores = 8;

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
