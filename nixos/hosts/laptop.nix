# Host: laptop (AMD iGPU + NVIDIA RTX 4060, hibrida)
# Espejo de la seccion "GPU NVIDIA (laptop hibrida)" de AGENTS.md.
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.laptop.nix ];

  networking.hostName = "laptop";

  # Swapfile 16G en btrfs (chattr +C nodatacow, creado con fallocate).
  # Protege de OOM cuando la RAM llega al maximo.
  swapDevices = [ { device = "/swapfile"; } ];

  # ── NVIDIA hybrid ────────────────────────────────────────────
  # iGPU AMD (amdgpu) maneja el display; dGPU NVIDIA solo para juegos.
  # gpu-mode.sh controla el runtime PM manualmente (battery/gaming),
  # por eso powerManagement.enable = false (no pelear con el script).
  #
  # ⚠️ "nvidia" en videoDrivers es OBLIGATORIO: sin esto el modulo de
  # nixpkgs no activa nada (nvidiaEnabled = elem "nvidia" videoDrivers).
  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];

  hardware.nvidia = {
    # Driver propietario.
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
}
