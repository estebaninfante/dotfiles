# home-manager: replica EXACTA de lo que hace scripts/install.sh en Fedora.
#
# Filosofia identica: el repo (~/dotfiles) es la unica fuente de verdad.
# home.file usa mkOutOfStoreSymlink → crea symlinks a los archivos del repo
# (no copias al store). Editas en el repo, se aplica al instante.
#
# Recibe `machineType` (laptop|desktop) via extraSpecialArgs desde flake.nix.

{ config, pkgs, lib, machineType, ... }:

let
  repo = "/home/eztvn/dotfiles";
  cfg = repo + "/linux/config";
  home = repo + "/linux/home";
  bin = repo + "/linux/bin";

  # Symlink out-of-store (el repo queda como fuente de verdad)
  link = p: config.lib.file.mkOutOfStoreSymlink p;

  # ── Inventarios (espejo de scripts/install.sh) ──────────────
  configDirs = [
    "hypr" "waybar" "kitty" "rofi" "nvim" "kanata" "fastfetch"
    "mako" "swaync" "swayosd" "avizo" "btop" "gh" "gtklock"
  ];
  configFiles = [
    "libinput-gestures.conf" "mimeapps.list" "user-dirs.dirs" "user-dirs.locale"
  ];
  homeFiles = [ ".bashrc" ".gitconfig" ];

  allScripts = [
    "rofi-power-mode.sh" "gpu-mode.sh" "toggle_moonlight.sh" "reload-hyprpaper.sh"
    "trackpad-dwt-daemon" "wifi-reconnect.sh" "shot" "waybar-battery-top"
    "clean-temp.sh" "pomodoro-waybar.sh" "setup-fingerprint.sh" "lid-inhibit-waybar.sh"
    "waybar-ram-top" "tts-send" "tts-server" "tts" "rofi-scripts-launcher.sh"
    "power-mode.sh" "toggle-lid.sh" "agent.sh" "send-with-taildrop" "tv-toggle.sh"
    "tv-mode.sh" "rofi-file-search.sh" "rofi-context-menu.sh" "reiniciar.sh"
    "fix-hyprland.sh" "cerrar-sesion.sh" "apagar.sh" "antigravity-ui.sh"
  ];
  # Solo laptop (igual que LAPTOP_SCRIPTS en install.sh)
  laptopScripts = [
    "toggle-lid.sh" "lid-inhibit-waybar.sh" "waybar-battery-top"
    "trackpad-dwt-daemon" "reload-hyprpaper.sh" "gpu-mode.sh"
  ];
  scripts =
    if machineType == "laptop" then allScripts
    else lib.subtractLists laptopScripts allScripts;

  configDirName = d: ".config/" + d;
  configFileName = f: ".config/" + f;
  scriptName = s: ".local/bin/" + s;
in
{
  home.username = "eztvn";
  home.homeDirectory = "/home/eztvn";
  home.stateVersion = "25.05";

  # Todos los paquetes van a nivel sistema (como dnf en Fedora).
  # home.packages queda libre para herramientas de perfil de usuario si
  # algun dia quieres separar; por ahora nada para no duplicar.
  home.packages = [ ];

  # ── machine-type (lo lee hyprland.lua / hyprpaper) ───────────
  # ── Config dirs (~/.config/<app>) ────────────────────────────
  home.file = lib.mkMerge [
    {
      ".config/machine-type".text = machineType;
    }
    (lib.genAttrs (map configDirName configDirs) (d: {
      source = link (cfg + "/" + lib.removePrefix ".config/" d);
      recursive = true;
    }))
    # ── Config files sueltos ───────────────────────────────────
    (lib.genAttrs (map configFileName configFiles) (f: {
      source = link (cfg + "/" + lib.removePrefix ".config/" f);
    }))
    # ── Home files (~/.bashrc, ~/.gitconfig) ───────────────────
    (lib.genAttrs homeFiles (f: {
      source = link (home + "/" + f);
    }))
    # ── Scripts (~/.local/bin/) ────────────────────────────────
    # Nota: sin `executable = true` — con mkOutOfStoreSymlink home-manager
    # copiaria el archivo al store (rompiendo el symlink). Los scripts del
    # repo ya son 755 en git; el symlink preserva el bit del destino.
    (lib.genAttrs (map scriptName scripts) (s: {
      source = link (bin + "/" + lib.removePrefix ".local/bin/" s);
    }))
    # ── .cargo/env vacio: el .bashrc hace `. ~/.cargo/env`;
    #    en NixOS cargo va en el store, no hay env → no romper el shell ──
    {
      ".cargo/env" = { text = ""; };
    }
  ];

  # ── Git credential helper ─────────────────────────────────────
  # El .gitconfig del repo apunta a /usr/bin/gh (ruta Fedora).
  # En NixOS gh vive en el store: override solo del helper, el resto
  # del .gitconfig (user.name/email/insteadOf) sigue viniendo del repo.
  programs.git = {
    enable = true;
    settings.credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    settings.credential."https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
  };

  # ── Units systemd user (espejo de linux/config/systemd/user/) ──
  # Nota: en NixOS los binarios no estan en /usr/bin → rutas del store.
  systemd.user.services.dotfiles-sync = {
    Unit = {
      Description = "Dotfiles auto-sync (git pull)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.git}/bin/git -C %h/dotfiles pull --ff-only";
    };
  };

  systemd.user.timers.dotfiles-sync = {
    Unit = { Description = "Dotfiles pull at boot"; };
    Timer = { OnBootSec = "2min"; };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # ── keyd: user service (arranca solo con la sesion grafica) ──
  # Servicio de usuario en vez de sistema: keyd de sistema agarra el
  # teclado a nivel kernel y su overload (leftalt/enter) se traga
  # Ctrl+Alt+F<N> → imposible cambiar de TTY. Como user service solo
  # corre dentro de Hyprland: GDM/TTY libres, overloads funcionales.
  # Requiere grupos input/uinput (configuration.nix) y /etc/keyd/default.conf
  # (laptop.nix — config del repo como fuente de verdad).
  systemd.user.services.keyd = lib.mkIf (machineType == "laptop") {
    Unit = {
      Description = "Keyboard remapping daemon (user session)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.keyd}/bin/keyd";
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # Solo laptop (igual que en install.sh: SYSTEMD_UNITS condicional)
  systemd.user.services.trackpad-dwt = lib.mkIf (machineType == "laptop") {
    Unit = {
      Description = "Trackpad disable-while-typing daemon";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/trackpad-dwt-daemon";
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };
}
