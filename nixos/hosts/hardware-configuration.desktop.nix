# Hardware REAL del desktop (generado con nixos-generate-config).
# CPU: AMD Ryzen 9 5900X · GPU: NVIDIA RTX 3070 (GA104) · NVMe btrfs.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/e1639a37-9404-4a5a-8905-bfbdeab2b16a";
      fsType = "btrfs";
    };

  fileSystems."/nix" =
    { device = "/dev/disk/by-uuid/e1639a37-9404-4a5a-8905-bfbdeab2b16a";
      fsType = "btrfs";
      options = [ "subvol=nix" ];
    };

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/e1639a37-9404-4a5a-8905-bfbdeab2b16a";
      fsType = "btrfs";
      options = [ "subvol=home" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/14AE-92A5";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
