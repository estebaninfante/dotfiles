# Reglas NOPASSWD para los scripts del repo (gpu-mode.sh, etc.).
# Los binarios viven en /run/current-system/sw/bin.
#
# Uso: security.sudo.extraRules = import ./modules/sudoers.nix;

[
  {
    users = [ "eztvn" ];
    commands = [
      # gpu-mode.sh: control de runtime PM de la GPU NVIDIA
      {
        command = "/run/current-system/sw/bin/tee /sys/bus/pci/devices/*/power/control";
        options = [ "NOPASSWD" ];
      }
      # gpu-mode.sh: nvidia-smi -pm (persistence mode)
      {
        command = "/run/current-system/sw/bin/nvidia-smi";
        options = [ "NOPASSWD" ];
      }
      # keyd reload (linux/system/keyd/default.conf)
      {
        command = "/run/current-system/sw/bin/keyd";
        options = [ "NOPASSWD" ];
      }
      # systemctl (units de sistema gestionadas manualmente)
      {
        command = "/run/current-system/sw/bin/systemctl";
        options = [ "NOPASSWD" ];
      }
    ];
  }
]
