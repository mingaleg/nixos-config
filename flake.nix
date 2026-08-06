{
  description = "mingaleg's NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-2605.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixpkgs, nixpkgs-2605, home-manager, nixos-raspberrypi, agenix, ... }@inputs:
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
        "mingamini" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            agenix.nixosModules.default
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

        # Raspberry Pi 5 - running system
        "pi" = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.page-size-16k
                raspberry-pi-5.display-vc4
              ];
            }
            agenix.nixosModules.default
            ./hosts/pi
          ];
        };

        # Raspberry Pi 5 - SD image installer
        "pi-installer" = nixos-raspberrypi.lib.nixosInstaller {
          specialArgs = inputs;
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.page-size-16k
                raspberry-pi-5.display-vc4
              ];
            }
            agenix.nixosModules.default
            ./hosts/pi
          ];
        };

        # GCP VPS - WireGuard relay
        "vps" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            agenix.nixosModules.default
            ./hosts/vps
          ];
        };

        # Home server - replacing pi's non-network services
        # On nixos-26.05 (not the fleet-wide nixos-25.11) for pihole-ftl 6.7+,
        # which adds the dns.localise toggle needed for VPN A records.
        "ronove" = nixpkgs-2605.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            agenix.nixosModules.default
            ./hosts/ronove
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.users.mingaleg = import ./home-ronove.nix;
              home-manager.extraSpecialArgs = inputs;
            }
          ];
        };
      };

      # SD image output
      images.pi = self.nixosConfigurations.pi-installer.config.system.build.sdImage;
    };
}
