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
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, handy, nix-flatpak, ... }:
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

      mkHost = { machineType, extraModules }: lib.nixosSystem {
        inherit system;
        modules = baseModules ++ [
          { home-manager.extraSpecialArgs = { inherit machineType; }; }
          { _module.args = { inherit handyPackage machineType; }; }
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
    };
}
