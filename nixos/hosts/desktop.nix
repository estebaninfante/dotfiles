# Host: desktop (AMD Ryzen 9 5900X + NVIDIA RTX 3070)
# GPU dedicada unica (no hibrida: sin iGPU AMD). NVIDIA maneja el display.
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.desktop.nix ];

  networking.hostName = "desktop";

  # ── Sunshine NVENC (RTX 3070) ────────────────────────────────
  # Solo desktop: NVENC para gaming en streaming. Requiere recompilar
  # sunshine con cudaSupport (SUNSHINE_ENABLE_CUDA) para la conversion de
  # color por GPU. La laptop usa el paquete plain (software), suficiente
  # para solo ver. ⚠️ Compilar con paralelismo limitado (max-jobs/cores)
  # o la build C++ con 24 jobs OOM y congela (sin swap).
  services.sunshine.package = (pkgs.sunshine.override { cudaSupport = true; });

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
  # cudaSupport=true → nixpkgs compila python torch CON CUDA (RTX 3070).
  # El env de voz (pkgs celestiales kokoro/kokoroEnv en packages.nix) usa
  # torch → se infiere cudaSupport de pkgs.config. Solo desktop: la laptop
  # evita el build CUDA (la usa para jugar, no para ML).
  # ⚠️ Build LARGO: torch se compila desde fuente (horas). Correr con
  #    paralelismo controlado y seguir el log en otra terminal:
  #    sudo env NIX_CONFIG="max-jobs = 2"$'\n'"cores = 8" nixos-rebuild switch
  #    (o bash ~/dotfiles/scripts/rebuild.sh con NIX_CONFIG seteado).
  nixpkgs.config.cudaSupport = true;

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
