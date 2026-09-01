# home-manager: inventario canónico de configs (~/.config, ~/.local/bin).
#
# Filosofia identica: el repo (~/dotfiles) es la unica fuente de verdad.
# home.file usa mkOutOfStoreSymlink → crea symlinks a los archivos del repo
# (no copias al store). Editas en el repo, se aplica al instante.
#
# Recibe `machineType` (laptop|desktop) via extraSpecialArgs desde flake.nix.

{ config, pkgs, lib, machineType, piperVoices, ... }:

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
    "hypr" "waybar" "kitty" "nvim" "kanata" "fastfetch"
    "mako" "swaync" "swayosd" "avizo" "btop" "gh" "opencode"
    "quickshell" "tmux" "voice"
  ];
  configFiles = [
    "libinput-gestures.conf" "mimeapps.list" "user-dirs.dirs" "user-dirs.locale"
  ];
  homeFiles = [ ".bashrc" ".gitconfig" ];

allScripts = [
    "gpu-mode.sh" "toggle_moonlight.sh"
    "wifi-reconnect.sh" "shot" "waybar-battery-top"
    "clean-temp.sh" "pomodoro-waybar.sh" "lid-inhibit-waybar.sh"
    "waybar-ram-top" "keyboard-layout-waybar.sh" "tts-send" "tts-server" "tts"
    "power-mode.sh" "battery-power-guard.sh" "toggle-lid.sh" "agent.sh" "send-with-taildrop" "tv-toggle.sh"
    "tv-mode.sh" "game-mode.sh" "wheel-mode-monitor.sh" "reiniciar.sh"
    "fix-hyprland.sh" "cerrar-sesion.sh" "apagar.sh" "antigravity-ui.sh"
    "super-hold-monitor.sh" "wallpaper-switch.sh" "wallpaper-daemon.sh"
    "grid-move" "Hermes" "speak" "leia.sh" "lan-mouse-escape.sh" "clipboard-sync"
    "voice" "voice-daemon" "handy-paste.sh" "middle-click.sh"
    "bedtime.sh" "bedtime-skip.sh" "notify-lid-suspend.sh" "notify-push-toggle.sh" "temperature-log.sh"
    "kitty-theme-toggle.sh" "obsidian-theme-toggle.sh"
    "theme-toggle.sh"
    "gamepad-watch.sh" "hypr-input-bridge.sh"
    "qs-launcher.sh" "apps-list.sh" "file-list.sh" "script-list.sh"
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
    # ── Tmux: .desktop para lanzarlo desde el launcher (apps) ─
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
    # ── Voces piper: ~/.local/share/tts/piper/voices ─────────────────────
    # Ruta que buscan `speak` y linux/voice/engine.py. NO usar /sw/share
    # (system-path solo expone bin/). Del derivación piperVoices (flake.nix).
    {
      ".local/share/tts/piper/voices" = {
        source = "${piperVoices}/share/piper-voices";
        recursive = true;
        force = true;
      };
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

  # input-remapper muta config.json/presets cuando el usuario ajusta los
  # mapeos desde la GUI → se copian (no symlink), igual patron lan-mouse.
  # El repo queda como fuente de verdad de los mapeos default; la GUI puede
  # sobrescribir en ~/.config y se pierde en el proximo rebuild (igual
  # que config.toml de lan-mouse).
  home.activation.inputRemapper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ir_dir="$HOME/.config/input-remapper-2"
    if [ -L "$ir_dir" ]; then
      rm "$ir_dir"
    fi
    mkdir -p "$ir_dir/presets/Nintendo Wii Remote Pro Controller"
    ${pkgs.coreutils}/bin/install -m 0644 \
      "${cfg}/input-remapper-2/config.json" "$ir_dir/config.json"
    ${pkgs.coreutils}/bin/install -m 0644 \
      "${cfg}/input-remapper-2/presets/Nintendo Wii Remote Pro Controller/desktop.json" \
      "$ir_dir/presets/Nintendo Wii Remote Pro Controller/desktop.json"
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

  # F10 permite mantener laptop despierta con tapa cerrada, pero solo por
  # 30 minutos. Luego suspende aunque tapa ya este cerrada.
  systemd.user.services.lid-inhibit = lib.mkIf (machineType == "laptop") {
    Unit = { Description = "Allow laptop to stay awake with lid closed"; };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=handle-lid-switch --mode=block ${pkgs.coreutils}/bin/sleep infinity";
    };
  };

  systemd.user.services.lid-inhibit-timeout = lib.mkIf (machineType == "laptop") {
    Unit = { Description = "Suspend laptop after lid inhibit timeout"; };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${bin}/notify-lid-suspend.sh";
      ExecStart = [
        "${pkgs.systemd}/bin/systemctl --user stop lid-inhibit.timer lid-inhibit.service"
        "${pkgs.systemd}/bin/systemctl suspend"
      ];
    };
  };

  systemd.user.timers.lid-inhibit = lib.mkIf (machineType == "laptop") {
    Unit = { Description = "Limit lid inhibit duration"; };
    Timer = {
      OnActiveSec = "30min";
      Unit = "lid-inhibit-timeout.service";
    };
  };

  # Guarda temperaturas de sensores termicos disponibles cada 5 minutos.
  systemd.user.services.temperature-log = {
    Unit = { Description = "Log thermal sensor temperatures"; };
    Service = {
      Type = "oneshot";
      ExecStart = "${bin}/temperature-log.sh";
    };
  };

  systemd.user.timers.temperature-log = {
    Unit = { Description = "Periodic thermal sensor log"; };
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
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

  # ── quickshell: barra/panel QML ──────────────────────────────
  # Reemplaza el exec_cmd de hyprland.lua. Config: ~/.config/quickshell/
  # (symlink al repo). --no-duplicate evita instancias multiples.
  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell panel (QML bar)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = pkgs.writeShellScript "quickshell-wait" ''
        for i in $(seq 1 30); do
          [ -S "/run/user/%U/wayland-1" ] && exit 0
          sleep 0.5
        done
        exit 0
      '';
      ExecStart = "${pkgs.quickshell}/bin/quickshell --no-duplicate";
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/%U"
        "XDG_CURRENT_DESKTOP=Hyprland"
        "QT_SCALE_FACTOR=1"
      ];
      Restart = "on-failure";
      RestartSec = "3";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

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
      ExecStartPre = pkgs.writeShellScript "polkit-wait" ''
        # Esperar socket Wayland: con Linger=yes graphical-session.target se
        # activa al boot (antes del login), y el agente Qt aborta fatal
        # ("no Qt platform plugin") sin compositor. Espero wayland-1.
        for i in $(seq 1 60); do
          [ -S "/run/user/%U/wayland-1" ] && exit 0
          sleep 0.5
        done
        exit 0
      '';
      ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/%U"
        "XDG_CURRENT_DESKTOP=Hyprland"
        # Fix QQuickStyle: sin esto el diálogo se dibuja roto y el botón
        # "Authenticate" no responde (QQuickStyle::setStyle() debe llamarse
        # antes de importar QtQuick.Controls 2, bug hyprpolkitagent 0.1.3).
        "QT_QUICK_CONTROLS_STYLE=default"
      ];
      Restart = "on-failure";
      RestartSec = "3";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # ── linux-wallpaperengine: wallpapers animados de Steam ────────
  # Requiere Steam + Wallpaper Engine instalados.
  # La config viva esta en ~/.config/wallpaper-current (id) y
  # ~/.config/wallpaper-scaling. `wallpaper-switch.sh` las escribe y
  # reinicia el servicio → persistente entre sesiones.

  # Inyectar variables de entorno Wayland que systemd user no hereda de Hyprland
  # linux-wallpaperengine: SOLO desktop (laptop: drena batería — wallpaper
  # animado mantiene iGPU/CPU activas). En laptop se usa hyprpaper.
  systemd.user.services.linux-wallpaperengine = lib.mkIf (machineType == "desktop") {
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
        # Esperar no solo el socket Wayland sino el IPC de Hyprland (socket2):
        # hyprctl (usado por wallpaper-daemon.sh) falla si el IPC no está listo,
        # y con pipefail el daemon muere → RestartSec=2 → crash-loop.
        for i in $(seq 1 60); do
          if /run/current-system/sw/bin/hyprctl monitors -j >/dev/null 2>&1; then
            exit 0
          fi
          sleep 0.5
        done
        exit 0
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
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # ── voice-daemon: cola TTS + reproduccion (sistema de voz) ───────────
  # Capa daemon del sistema de voz local (linux/voice/daemon.py). Habla
  # via PipeWire (pw-play); CLI `voice speak` y plugin opencode voice
  # escriben por el FIFO ~/.cache/voice/tts.fifo.
  systemd.user.services.voice-daemon = {
    Unit = {
      Description = "Voice daemon (TTS queue + playback)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${bin}/voice-daemon";
      Restart = "on-failure";
      RestartSec = "3";
      Environment = [
        "XDG_RUNTIME_DIR=/run/user/%U"
        "XDG_SESSION_TYPE=wayland"
        "PULSE_SERVER=unix:/run/user/%U/pulse/native"
      ];
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  systemd.user.services.dotoold = {
    Unit = {
      Description = "dotool daemon (uinput persistente para middle-click Warp)";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.dotool}/bin/dotoold";
      # Restart=no: si el pipe /tmp/dotool-pipe tiene un lector fantasma
      # (zombie leftover), dotoold sale 1 al instante; on-failure lo
      # reinicia cada 3s en loop indefinido. Daemon one-shot: si muere,
      # se arregla limpiando el pipe y volviendo a start.
      Restart = "no";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # ── Modo consola: gamepad → modo juego + UI ───────────────────
  # gamepad-watch.sh: detecta conexión/desconexión de pads (BT/USB) y
  # dispara game-mode.sh / exit con debounce. No dispara en arranque.
  systemd.user.services.gamepad-watch = {
    Unit = {
      Description = "Detect gamepad connect/disconnect -> game mode";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${bin}/gamepad-watch.sh";
      Restart = "always";
      RestartSec = "5";
      Environment = [ "XDG_RUNTIME_DIR=/run/user/%U" ];
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  # hypr-input-bridge.sh: escucha socket2 de Hyprland y activa/desactiva
  # el preset del gamepad segun la ventana enfocada (UI → mapeo desktop,
  # juego fullscreen → stop = pad nativo).
  systemd.user.services.hypr-input-bridge = {
    Unit = {
      Description = "Hyprland activewindow -> input-remapper preset";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${bin}/hypr-input-bridge.sh";
      Restart = "on-failure";
      RestartSec = "2";
      Environment = [ "XDG_RUNTIME_DIR=/run/user/%U" ];
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

}
