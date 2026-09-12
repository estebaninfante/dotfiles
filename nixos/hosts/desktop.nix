# Host: desktop (AMD Ryzen 9 5900X + NVIDIA RTX 3070)
# GPU dedicada unica (no hibrida: sin iGPU AMD). NVIDIA maneja el display.
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.desktop.nix ];

  # Swapfile 16G en btrfs (chattr +C nodatacow, creado con truncate→fallocate).
  # Protege de freezes/OOM durante builds pesados (torch CUDA etc.).
  swapDevices = [ { device = "/swapfile"; } ];

  networking.hostName = "desktop";

  # ── Sunshine (RTX 3070) ──────────────────────────────────────
  # Paquete plain (sin NVENC): recompilar con cudaSupport triggea horas
  # de build CUDA (cudnn ~2GB + libcublas ~1GB). NVENC no esencial para
  # streaming local. Para re-habilitar: uncomment la linea de abajo.
  # services.sunshine.package = (pkgs.sunshine.override { cudaSupport = true; });

  # ── DaVinci Resolve (solo desktop) ──────────────────────────
  # Edicion de video con aceleracion CUDA (RTX 3070). Unfree pero
  # permitido por nixpkgs.config.allowUnfree. Nota: version FREE no
  # soporta H.264/H.265/AAC en Linux → convertir a DNxHR con ffmpeg.
  # No corre Wayland nativo (qtwayland) → lanzar con QT_QPA_PLATFORM=xcb.
  environment.systemPackages = [ pkgs.davinci-resolve ];

  # ── NVIDIA (RTX 3070 / GA104, unica GPU) ────────────────────
  # GPU dedicada manejando el display directo → driver nvidia con
  # modesetting. SIN prime.offload (eso es para hibridas con iGPU).
  #
  # ⚠️ "nvidia" en videoDrivers es OBLIGATORIO: sin esto el modulo de
  # nixpkgs no activa nada (nvidiaEnabled = elem "nvidia" videoDrivers).
  services.xserver.videoDrivers = [ "nvidia" ];

  # ── CUDA para ML/TTS (torch/Kokoro) ─────────────────────────
  # DESHABILITADO: torch CUDA y opencv4 CUDA se compilan desde fuente
  # con cudnn/cublas (~2GB cada uno). torch funciona en CPU (lento pero
  # funcional). Para re-habilitar: uncomment el bloque de overlays.
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
  #       (python-final: python-prev: {
  #         torch = python-prev.torch.override { cudaSupport = true; };
  #       })
  #     ];
  #     opencv4 = prev.opencv4.override { enableCuda = true; };
  #   })
  # ];

  # nixpkgs.config.cudaCapabilities = [ "8.6" "8.9" ];  # DESHABILITADO: sin overrides CUDA, innecesario

  hardware.nvidia = {
    # Driver propietario.
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
