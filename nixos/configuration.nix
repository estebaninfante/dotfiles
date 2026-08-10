# Configuracion base NixOS — comun a laptop y desktop.
# Replica el entorno Fedora descrito en linux/packages/dnf-packages.txt
# y el inventario de scripts/install.sh.
#
# OJO: el archivo hardware-configuration.nix NO se gestiona aqui.
# Se genera por maquina con `nixos-generate-config` durante la instalacion
# (ver README.md). Cada host importa el suyo en hosts/<host>.nix.

{ config, pkgs, lib, ... }:

{
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
  console.keyMap = "es";

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

  # Flatpak (apps que no esten en nixpkgs)
  services.flatpak.enable = true;

  # ── Virtualizacion / contenedores ─────────────────────────────
  virtualisation.libvirtd.enable = true;
  virtualisation.docker.enable = true;
  virtualisation.podman.enable = true;

  # ── Gaming ────────────────────────────────────────────────────
  programs.steam.enable = true;
  programs.gamemode.enable = true;

  # ── Display manager (GDM, tema oscuro — equivalente a setup-gdm-dark.sh) ──
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
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
  services.power-profiles-daemon.enable = true;
  # linux/system/tuned/ppd.conf como referencia (power-profiles-daemon
  # lee /etc/ppd.conf para su propio mapeo de perfiles)
  environment.etc."ppd.conf".source = ../linux/system/tuned/ppd.conf;

  # ── Usuario ───────────────────────────────────────────────────
  users.users.eztvn = {
    isNormalUser = true;
    description = "estebaninfante";
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "docker" "video" "audio" ];
    # TODO: definir contrasena inicial tras instalar:
    #   sudo passwd eztvn
    # o usar hashedPassword con `mkpasswd -m sha-512`.
  };

  # NOPASSWD para scripts del repo (equivalente a linux/system/sudoers/dotfiles)
  security.sudo.extraRules = import ./modules/sudoers.nix;

  # ── Nix ───────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc.automatic = true;
  nix.gc.options = "--delete-older-than 14d";

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.05";
}
