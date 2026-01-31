{
  description = "mingaleg's NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Raspberry Pi support - use main branch (stable)
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Binary cache for pre-built packages
  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixpkgs, home-manager, nixos-raspberrypi, ... }@inputs:
    let
      home-manager-modules = [
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.mingaleg = import ./home.nix;
          home-manager.extraSpecialArgs = inputs;
        }
      ];
    in
    {
      nixosConfigurations = {
        "minganix" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            ./hosts/minganix
          ] ++ home-manager-modules;
        };

        "mingamini" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            ./hosts/mingamini
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.mingaleg = import ./home-mingamini.nix;
              home-manager.extraSpecialArgs = inputs;
            }
          ];
        };

        # Raspberry Pi 5 - Use their helper function
        "pi" = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = [
            # Hardware specific modules
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.page-size-16k  # Recommended for RPi5
                raspberry-pi-5.display-vc4    # If you have a display
              ];
            }
            
            # Your configuration
            ./hosts/pi
          ];
        };
      };
    };
}
