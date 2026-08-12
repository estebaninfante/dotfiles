# Host: desktop (AMD Ryzen 9 5900X + NVIDIA RTX 3070)
# GPU dedicada unica (no hibrida: sin iGPU AMD). NVIDIA maneja el display.
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.desktop.nix ];

  networking.hostName = "desktop";

  # ── NVIDIA (RTX 3070 / GA104, unica GPU) ────────────────────
  # GPU dedicada manejando el display directo → driver nvidia con
  # modesetting. SIN prime.offload (eso es para hibridas con iGPU).
  #
  # ⚠️ "nvidia" en videoDrivers es OBLIGATORIO: sin esto el modulo de
  # nixpkgs no activa nada (nvidiaEnabled = elem "nvidia" videoDrivers).
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Driver propietario (equivalente a akmod-nvidia en Fedora).
    # RTX 3070 (Ampere) → open = false (el open kernel module soporta
    # Turing+ pero el driver closed es el estandar para desktop stable).
    open = false;
    modesetting.enable = true;
    nvidiaSettings = true;

    # Sin prime.offload: no hay iGPU AMD en el desktop.
    # No usamos powerManagement.enable (no es laptop; el script
    # gpu-mode.sh solo corre en laptop).
  };
}
