# Host: desktop (sin NVIDIA; GPU integrada o dedicada AMD/Intel)
{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.desktop.nix ];

  networking.hostName = "desktop";

  # Sin configuracion NVIDIA: si el desktop tuviera GPU dedicada,
  # anadir aqui el modulo correspondiente (ej. hardware.nvidia para X).
}
