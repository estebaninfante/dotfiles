# Configuracion base NixOS — comun a laptop y desktop.
# Replica el entorno Fedora descrito en linux/packages/dnf-packages.txt
# y el inventario de scripts/install.sh.
#
# OJO: el archivo hardware-configuration.nix NO se gestiona aqui.
# Se genera por maquina con `nixos-generate-config` durante la instalacion
# (ver README.md). Cada host importa el suyo en hosts/<host>.nix.

{ config, pkgs, lib, ... }:

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

  # ── Red ───────────────────────────────────────────────────────
  networking.networkmanager.enable = true;
  # Hostname por maquina (definido en hosts/*.nix)
  networking.hostName = lib.mkDefault "nixos";

  # Firewall (equivalente a ufw en Fedora)
  networking.firewall.enable = true;
  # Si usas tailscale descomenta para no cortar la red mesh:
  # networking.firewall.checkReversePath = "loose";

  # ── Localizacion ──────────────────────────────────────────────
  # TODO: ajustar a tu zona horaria / locale si difiere
  time.timeZone = "America/Bogota";
  i18n.defaultLocale = "es_ES.UTF-8";
  # NOTA: console.keyMap NO se define aqui — el modulo keyboard.nix
  # lo pone en dvk_prog (tu layout custom, igual que Fedora).

  # ── Paquetes del sistema (mapeo de dnf-packages.txt) ──────────
  environment.systemPackages = import ./modules/packages.nix { inherit pkgs; };

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

  # Huella dactilar (fprintd + fprintd-pam)
  services.fprintd.enable = true;

  # Power profiles (reemplaza tuned-ppd; misma API UPower.PowerProfiles
  # que usa power-mode.sh via busctl). Ver seccion "Power profiles" abajo
  # para la config ppd.conf.

  # Sync de archivos
  services.syncthing.enable = true;
  services.syncthing.user = "eztvn";
  services.syncthing.dataDir = "/home/eztvn/.local/state/syncthing";

  # VPN mesh
  services.tailscale.enable = true;

  # SSH server (para acceso via Tailscale)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Abrir puerto SSH solo en la interfaz de Tailscale
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 ];

  # Flatpak (apps que no esten en nixpkgs)
  services.flatpak.enable = true;

  # ── Virtualizacion / contenedores ─────────────────────────────
  virtualisation.libvirtd.enable = true;
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;

  # ── Gaming ────────────────────────────────────────────────────
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # ── Login manager: GDM ──
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.accounts-daemon.enable = true;

  environment.etc = {
    # linux/system/tuned/ppd.conf
    "ppd.conf".source = ../linux/system/tuned/ppd.conf;
  };

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

  # ── Fuentes (mapeo de linux/packages/dnf-packages.txt) ──────
  fonts.packages = with pkgs; [
    fira-code            # fira-code-fonts
    jetbrains-mono       # jetbrains-mono-fonts
    font-awesome         # fontawesome-fonts
    noto-fonts           # google-noto-sans-fonts
    noto-fonts-color-emoji # google-noto-emoji-fonts (renombrado en nixpkgs)
    powerline-fonts      # powerline-fonts
    nerd-fonts.jetbrains-mono  # hyprlock usa "JetBrainsMono Nerd Font"
  ];

  # ── Power profiles (tuned-ppd → power-profiles-daemon) ───────
  # power-mode.sh habla con org.freedesktop.UPower.PowerProfiles via busctl;
  # power-profiles-daemon expone exactamente esa API (igual que tuned-ppd).
  # Config ppd.conf en environment.etc (arriba).
  services.power-profiles-daemon.enable = true;

  # ── Usuario ───────────────────────────────────────────────────
  users.users.eztvn = {
    isNormalUser = true;
    description = "estebaninfante";
    # input/uinput: keyd corre como user service (home.nix) y necesita
    # leer /dev/input/* y crear /dev/uinput para remapear teclado.
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "docker" "video" "audio" "input" "uinput" ];
    # TODO: definir contrasena inicial tras instalar:
    #   sudo passwd eztvn
    # o usar hashedPassword con `mkpasswd -m sha-512`.
  };

  # NOPASSWD para scripts del repo (equivalente a linux/system/sudoers/dotfiles)
  security.sudo.extraRules = import ./modules/sudoers.nix;
  security.sudo.wheelNeedsPassword = false;

  # hyprlock necesita su propia config PAM en NixOS para poder autenticar
  # (en Fedora usa el PAM del sistema; en NixOS cada app de bloqueo requiere
  # /etc/pam.d/hyprlock — sin esto la contrasena siempre es rechazada).
  # fprintAuth = true: desbloqueo por huella (silencioso si no hay lector).
  security.pam.services.hyprlock = {
    fprintAuth = true;
  };

  # ── Nix ───────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 14d";

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
