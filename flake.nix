{
  description = "NixOS configuration — replica del entorno Fedora (dotfiles)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      # Modulos base compartidos por todas las maquinas.
      # home-manager: los dotfiles del repo se enlazan igual que en Fedora
      # (misma filosofia: el repo es la unica fuente de verdad).
      baseModules = [
        ./nixos/configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.eztvn = import ./nixos/home.nix;
        }
      ];

      mkHost = { machineType, extraModules }: lib.nixosSystem {
        inherit system;
        modules = baseModules ++ [
          { home-manager.extraSpecialArgs = { inherit machineType; }; }
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
