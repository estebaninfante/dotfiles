{
  description = "NixOS configuration (dotfiles)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # handy (speech-to-text): nixpkgs va atrasado (0.9.1); el flake
    # upstream tiene 0.9.5+ y cachix propio (handy-computer).
    handy.url = "github:cjpais/Handy/v0.9.5";
    # Flatpak declarativo: services.flatpak.packages (sincroniza apps
    # fuera de nixpkgs entre maquinas).
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    # Tema minimal para rEFInd (evanpurkhiser original). No tiene flake.nix →
    # flake = false, se usa como path raw. Se copia a /boot via
    # boot.loader.refind.additionalFiles (paths themes/rEFInd-minimal/*).
    refind-minimal-theme.url = "github:evanpurkhiser/rEFInd-minimal";
    refind-minimal-theme.flake = false;
  };

  outputs = { self, nixpkgs, home-manager, handy, nix-flatpak, refind-minimal-theme, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      # Modulos base compartidos por todas las maquinas.
      # home-manager: los dotfiles del repo se enlazan via mkOutOfStoreSymlink
      # (el repo es la unica fuente de verdad).
      baseModules = [
        ./nixos/configuration.nix
        nix-flatpak.nixosModules.nix-flatpak
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.eztvn = import ./nixos/home.nix;
        }
      ];

      # handy desde flake upstream (v0.9.5+), no desde nixpkgs
      handyPackage = handy.packages.${system}.handy;

      # Voces piper: fetchurl de rhasspy/piper-voices → $out/share/piper-voices.
      # No hay package de voces en nixpkgs (verificado). Se pasa como arg a
      # NixOS (systemPackages) y a home-manager (home.file enlaza a
      # ~/.local/share/tts/piper/voices, ruta que buscan `speak` y
      # linux/voice/engine.py). NOTA: /run/current-system/sw/share NO sirve
      # porque system-path solo expone bin/, no share/.
      voiceFetch = { name, path, onnxHash, jsonHash }:
        nixpkgs.legacyPackages.${system}.runCommand "piper-voice-${name}" { } ''
          mkdir -p $out/share/piper-voices/${name}
          cp ${nixpkgs.legacyPackages.${system}.fetchurl { url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${path}/${name}.onnx"; hash = onnxHash; }} \
            $out/share/piper-voices/${name}/${name}.onnx
          cp ${nixpkgs.legacyPackages.${system}.fetchurl { url = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${path}/${name}.onnx.json"; hash = jsonHash; }} \
            $out/share/piper-voices/${name}/${name}.onnx.json
        '';
      piperVoices =
        nixpkgs.legacyPackages.${system}.symlinkJoin {
          name = "piper-voices";
          paths = map voiceFetch [
            { name = "es_MX-claude-high";
              path = "es/es_MX/claude/high";
              onnxHash = "sha256-PvQKcepjhSzYq35vp9Ls3PpnoLR8nEjj8Q4C7gIIPqA=";
              jsonHash = "sha256-GvyB9wPA5Ms7TXwNyglri1SpiAaAfwFwz161VXcjwS0="; }
            { name = "es_MX-ald-medium";
              path = "es/es_MX/ald/medium";
              onnxHash = "sha256-AZs4Ayk8k+NKIG3S5To4iSCaUU54b9cUT3twGWxXm2M=";
              jsonHash = "sha256-76tzbmLlMh3V0GPRtG5jxZzmVUGYFjVbgdAlwajWsDw="; }
            { name = "es_ES-davefx-medium";
              path = "es/es_ES/davefx/medium";
              onnxHash = "sha256-ZliwOxpsMW7kwmWpiWq8E5M1PC2eG8p9ZsLEQuIiqRc=";
              jsonHash = "sha256-Dg3ah8cy9vOHcf8nSmOA2SUvMn3Kd6opY9X7357FSEI="; }
            { name = "en_US-amy-medium";
              path = "en/en_US/amy/medium";
              onnxHash = "sha256-s6bke1e4x/vmoM4lGBYaUPWanN2KUINcAssCvdYgbBg=";
              jsonHash = "sha256-laI+tNQpCdON9zu5rH9F9Zfb/N4tG/lSb96vVGaXfXc="; }
          ];
        };

      mkHost = { machineType, extraModules }: lib.nixosSystem {
        inherit system;
        modules = baseModules ++ [
          { home-manager.extraSpecialArgs = { inherit machineType piperVoices refind-minimal-theme; }; }
          { _module.args = { inherit handyPackage machineType piperVoices refind-minimal-theme; }; }
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations = {
        laptop = mkHost {
          machineType = "laptop";
          extraModules = [ ./nixos/hosts/laptop.nix ];
        };
        desktop = mkHost {
          machineType = "desktop";
          extraModules = [ ./nixos/hosts/desktop.nix ];
        };
      };
      # piperVoices expuesto como paquete del flake: permite `nix build
      # .#piperVoices` para construir/tener las voces sin hacer rebuild:
      # `nix build ".#piperVoices" &&`
      #   # luego home-manager lo referencia via home.file.
      packages.${system}.piperVoices = piperVoices;
    };
}
