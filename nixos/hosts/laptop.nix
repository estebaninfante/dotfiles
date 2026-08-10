# Host: laptop (AMD iGPU + NVIDIA RTX 4060, hibrida)
# Espejo de la seccion "GPU NVIDIA (laptop hibrida)" de AGENTS.md.
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.laptop.nix ];

  networking.hostName = "laptop";

  # ── NVIDIA hybrid ────────────────────────────────────────────
  # iGPU AMD (amdgpu) maneja el display; dGPU NVIDIA solo para juegos.
  # gpu-mode.sh controla el runtime PM manualmente (battery/gaming),
  # por eso powerManagement.enable = false (no pelear con el script).
  #
  # ⚠️ "nvidia" en videoDrivers es OBLIGATORIO: sin esto el modulo de
  # nixpkgs no activa nada (nvidiaEnabled = elem "nvidia" videoDrivers).
  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];

  hardware.nvidia = {
    # Driver propietario (equivalente a akmod-nvidia en Fedora).
    # Obligatorio fijarlo: el default null rompe una assertion del modulo.
    open = false;
    modesetting.enable = true;
    nvidiaSettings = true;

    prime = {
      # Offload: la dGPU se activa bajo demanda (PRIME render offload)
      offload.enable = true;

      # Bus IDs reales de esta laptop (Lenovo 82Y5 / Legion Slim 5):
      #   lspci: 05:00.0 AMD Phoenix1 (iGPU) · 01:00.0 NVIDIA RTX 4060
      amdgpuBusId = "PCI:5:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };

    # gpu-mode.sh hace `tee power/control` manualmente → no auto-manage
    powerManagement.enable = false;
  };

  # El driver amdgpu es el default para GPUs AMD; nada extra que configurar.
  # (El layout XKB dvk_prog ahora vive en nixos/modules/keyboard.nix —
  #  aplica a TTY, X11/GDM y Wayland en laptop y desktop.)

  # ── keyd (linux/system/keyd/default.conf como fuente de verdad) ──
  # El repo define la config en /etc/keyd/default.conf; keyd la lee igual
  # que en Fedora. Servicio propio para no pelear con el modulo de nixpkgs.
  # (El modulo oficial de nixpkgs hace hardware.uinput.enable = mkDefault true;
  #  como usamos servicio propio, lo activamos aqui manualmente.)
  hardware.uinput.enable = true;
  environment.etc."keyd/default.conf".source = ../../linux/system/keyd/default.conf;
  systemd.services.keyd = {
    description = "Keyboard remapping daemon";
    # graphical.target: keyd solo corre con la sesion grafica.
    # En multi-user.target keyd captura el teclado antes del login y su
    # overload (leftalt/enter) interfiere con Ctrl+Alt+F<N> para cambiar
    # de TTY (los eventos no llegan al kernel como esperas).
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.keyd}/bin/keyd";
      Restart = "on-failure";
    };
  };
}
