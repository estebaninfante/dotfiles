# home-manager: inventario canónico de configs (~/.config, ~/.local/bin).
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
  developingIgnore = pkgs.writeText "developing.stignore" ''
    **/node_modules
    **/.next
    **/dist
    **/build
    **/coverage
    **/.turbo
    **/.vite
    **/.cache
    **/*.log
  '';

  # Symlink out-of-store (el repo queda como fuente de verdad)
  link = p: config.lib.file.mkOutOfStoreSymlink p;

  # ── Inventarios ─────────────────────────────────────────────
  configDirs = [
    "hypr" "waybar" "kitty" "rofi" "nvim" "kanata" "fastfetch"
    "mako" "swaync" "swayosd" "avizo" "btop" "gh" "opencode"
    "quickshell" "tmux"
  ];
  configFiles = [
    "libinput-gestures.conf" "mimeapps.list" "user-dirs.dirs" "user-dirs.locale"
  ];
  homeFiles = [ ".bashrc" ".gitconfig" ];

  allScripts = [
    "rofi-power-mode.sh" "gpu-mode.sh" "toggle_moonlight.sh"
    "wifi-reconnect.sh" "shot" "waybar-battery-top"
    "clean-temp.sh" "pomodoro-waybar.sh" "lid-inhibit-waybar.sh"
    "waybar-ram-top" "keyboard-layout-waybar.sh" "tts-send" "tts-server" "tts" "rofi-scripts-launcher.sh"
    "power-mode.sh" "toggle-lid.sh" "agent.sh" "send-with-taildrop" "tv-toggle.sh"
    "tv-mode.sh" "rofi-file-search.sh" "rofi-context-menu.sh" "reiniciar.sh"
    "fix-hyprland.sh" "cerrar-sesion.sh" "apagar.sh" "antigravity-ui.sh"
    "super-hold-monitor.sh" "wallpaper-switch.sh" "wallpaper-daemon.sh"
    "grid-move" "Hermes" "speak" "leia.sh" "lan-mouse-escape.sh" "clipboard-sync"
  ];
  # Solo laptop
  laptopScripts = [
    "toggle-lid.sh" "lid-inhibit-waybar.sh" "waybar-battery-top"
    "gpu-mode.sh"
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

  # Todos los paquetes van a nivel sistema.
  # home.packages queda libre para herramientas de perfil de usuario si
  # algun dia quieres separar; por ahora nada para no duplicar.
  home.packages = [ ];

  # ── machine-type (lo lee hyprland.lua) ─────────────────────────
  # ── Config dirs (~/.config/<app>) ────────────────────────────
  home.file = lib.mkMerge [
    {
      ".config/machine-type".text = machineType;
    }
    # ── Tmux: .desktop para lanzarlo desde rofi (drun) ─────────
    {
      ".local/share/applications/tmux.desktop" = { source = link (cfg + "/applications/tmux.desktop"); force = true; };
    }
    (lib.genAttrs (map configDirName configDirs) (d: {
      source = link (cfg + "/" + lib.removePrefix ".config/" d);
      recursive = true;
      force = true;
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
    # ── Fuente Old London (local, no en nixpkgs): ~/.local/share/fonts ──
    {
      ".local/share/fonts/old-london" = {
        source = link (repo + "/linux/fonts/old-london");
        recursive = true;
      };
    }
    # ── .cargo/env vacio: el .bashrc hace `. ~/.cargo/env`;
    #    en NixOS cargo va en el store, no hay env → no romper el shell ──
    {
      ".cargo/env" = { text = ""; };
    }
  ];

  # Lan-mouse mutates config.toml while saving state. Copy both files instead
  # of symlinking them, and recover from stale directory symlinks.
  home.activation.lanMouseConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    lan_mouse_dir="$HOME/.config/lan-mouse"
    if [ -L "$lan_mouse_dir" ]; then
      rm "$lan_mouse_dir"
    fi
    mkdir -p "$lan_mouse_dir"
    ${pkgs.coreutils}/bin/install -m 0644 \
      "${cfg}/lan-mouse/lan-mouse.pem" "$lan_mouse_dir/lan-mouse.pem"
    ${pkgs.coreutils}/bin/install -m 0644 \
      "${cfg}/lan-mouse/config.${machineType}.toml" "$lan_mouse_dir/config.toml"
  '';

  # Keep generated dependencies/builds local. Source, configs and lockfiles
  # remain synchronized by Syncthing.
  home.activation.developingSyncthingIgnore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    developing_dir="$HOME/developing"
    if [ -d "$developing_dir" ]; then
      ${pkgs.coreutils}/bin/install -m 0644 \
        "${developingIgnore}" "$developing_dir/.stignore"
    fi
  '';

  # ── Git credential helper ─────────────────────────────────────
  # El .gitconfig del repo apunta a /usr/bin/gh (ruta no-store).
  # En NixOS gh vive en el store: override solo del helper, el resto
  # del .gitconfig (user.name/email/insteadOf) sigue viniendo del repo.
  programs.git = {
    enable = true;
    settings.credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
    settings.credential."https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
  };

  # ── Units systemd user ──────────────────────────────────────
  # Nota: en NixOS los binarios no estan en /usr/bin → rutas del store.
  systemd.user.services.dotfiles-sync = {
    Unit = {
      Description = "Dotfiles auto-sync (pull + commit + push)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${repo}/scripts/auto-sync.sh";
    };
  };

  systemd.user.timers.dotfiles-sync = {
    Unit = { Description = "Dotfiles sync periodico"; };
    Timer = { OnBootSec = "2min"; OnUnitActiveSec = "5min"; };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # ── lan-mouse: KVM por red (mouse+teclado compartido) ─────────
  # Config: config.${machineType}.toml enlazado desde el repo.
  # PEM: compartido entre machines. config.toml es writable (lan-mouse
  # guarda estado) pero gitignored.
  systemd.user.services.lan-mouse = {
    Unit = {
      Description = "LAN-Mouse KVM daemon";
      After = [ "graphical-session.target" "network-online.target" "xdg-desktop-portal-hyprland.service" ];
      Wants = [ "network-online.target" "xdg-desktop-portal-hyprland.service" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = pkgs.writeShellScript "lan-mouse-wait" ''
        # Wait for Wayland socket
        SOCKET="/run/user/%U/wayland-1"
        for i in $(seq 1 30); do
          [ -S "$SOCKET" ] && break
          sleep 0.5
        done
        # Wait for compositor protocols to initialize
        sleep 3
        # Wait for peer to be reachable (extract IP from config.toml)
        CONFIG="$HOME/.config/lan-mouse/config.toml"
        if [ -f "$CONFIG" ]; then
          PEER_IP=$(grep -E '^\s*ips\s*=' "$CONFIG" | head -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
          if [ -n "$PEER_IP" ]; then
            for i in $(seq 1 60); do
              ping -c 1 -W 1 "$PEER_IP" >/dev/null 2>&1 && break
              sleep 1
            done
          fi
        fi
      '';
      ExecStart = "${pkgs.lan-mouse}/bin/lan-mouse --capture-backend layer-shell daemon";
      ExecStopPost = pkgs.writeShellScript "lan-mouse-cleanup" ''
        # Kill any lingering capture sessions if lan-mouse crashed
        sleep 1
        pkill -f "lan-mouse" 2>/dev/null || true
      '';
      Restart = "always";
      RestartSec = "5";
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/%U"
      ];
    };
    Install = { };
  };

  # Clipboard sync externo recomendado por comunidad lan-mouse. SSH transporta
  # MIME Wayland elegido por riqueza; lan-mouse sigue manejando input.
  systemd.user.services.clipboard-sync = {
    Unit = {
      Description = "Bidirectional Wayland clipboard sync";
      After = [ "graphical-session.target" "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${bin}/clipboard-sync watch";
      Restart = "always";
      RestartSec = "3";
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/%U"
        "CLIPBOARD_PEER=${if machineType == "laptop" then "eztvn@desktop" else "eztvn@laptop"}"
        "CLIPBOARD_SSH_KEY=/home/eztvn/.ssh/id_ed25519"
      ];
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };
  # Drop-in: forzar Restart=always en xdg-desktop-portal-hyprland
  # (el stock usa Restart=on-failure que no cubre SIGSEGV)
  xdg.configFile."systemd/user/xdg-desktop-portal-hyprland.service.d/override.conf".text = ''
    [Service]
    Restart=always
    RestartSec=2
  '';

  # ── keyd: SERVICIO DE SISTEMA (configuration.nix services.keyd) ──
  # keyd corre como root desde boot (GDM/TTY/sesión). El overload (leftalt/enter)
  # y la capa compuesta [control+numpad] garantizan Ctrl+Alt+F<N> (cambio de TTY).
  # No hay user service para evitar duplicar el daemon (crash-loop por doble grab).

  # ── holder de graphical-session.target (portales xdg) ─────────
  # La sesion de Hyprland no arranca graphical-session.target (eso lo
  # hace el session manager en DEs tipo GNOME). Las units de
  # xdg-desktop-portal tienen Requisite=graphical-session.target y se
  # activan por D-Bus → sin el target la activacion falla y Deskflow
  # (captura de entrada en Wayland via libei) no puede arrancar.
  # Este servicio persistente mantiene el target activo durante la sesion.
  systemd.user.services.graphical-session-holder = {
    Unit = {
      Description = "Keep graphical-session.target active (xdg portals)";
      After = [ "default.target" ];
      Wants = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      Restart = "always";
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  # ── polkit agent (hyprpolkitagent) ──────────────────────────────
  # Necesario para autorizar acciones polkit (p.ej. fprintd-enroll:
  # "Not Authorized: net.reactivated.fprint.device.enroll" sin agente).
  # Wayland-native, sustituye al gnome agent que hyprland.lua llamaba
  # con path inexistente (/usr/libexec/...).
  systemd.user.services.hyprpolkitagent = {
    Unit = {
      Description = "Hyprland polkit authentication agent";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Restart = "on-failure";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # ── linux-wallpaperengine: wallpapers animados de Steam ────────
  # Requiere Steam + Wallpaper Engine instalados.
  # La config viva esta en ~/.config/wallpaper-current (id) y
  # ~/.config/wallpaper-scaling. `wallpaper-switch.sh` las escribe y
  # reinicia el servicio → persistente entre sesiones.

  # Inyectar variables de entorno Wayland que systemd user no hereda de Hyprland
  systemd.user.services.linux-wallpaperengine = {
    Unit = {
      Description = "Implementation of Wallpaper Engine on Linux";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      StartLimitIntervalSec = "30";
      StartLimitBurst = "3";
    };
    Service = {
      Type = "simple";
      ExecStartPre = pkgs.writeShellScript "wallpaper-wait" ''
        SOCKET="/run/user/%U/wayland-1"
        for i in $(seq 1 30); do
          [ -S "$SOCKET" ] && break
          sleep 0.5
        done
        sleep 0.5
      '';
      ExecStart = "${config.home.homeDirectory}/.local/bin/wallpaper-daemon.sh";
      Environment = [
        "XDG_SESSION_TYPE=wayland"
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_CURRENT_DESKTOP=Hyprland"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "LINUX_WALLPAPERENGINE=${pkgs.linux-wallpaperengine}/share/linux-wallpaperengine/linux-wallpaperengine"
      ];
      Restart = "on-failure";
      RestartSec = "2";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}
