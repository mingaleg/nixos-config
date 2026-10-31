{
  description = "mingaleg's NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tracks its own nixpkgs (nixos-25.11 on main). Left as-is while
    # foreign-agent is in transit - move to its nixos-26.05 branch once the box
    # is reachable again (deploy with --test first).
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };

    # Builds main on ronove and deploys it to the fleet (dashboard + API).
    fleet-deployer = {
      url = "github:mingaleg/fleet-deployer";
      inputs.nixpkgs.follows = "nixpkgs";
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

  outputs = { self, nixpkgs, home-manager, nixos-raspberrypi, agenix, ... }@inputs:
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

        # Raspberry Pi 5 (ex-pi) at Igor and Tanya's house. Includes the
        # sd-image module so images.foreign-agent builds the exact system the
        # recovery stick flashes.
        "foreign-agent" = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.page-size-16k
                raspberry-pi-5.display-vc4
                sd-image
              ];
            }
            agenix.nixosModules.default
            ./hosts/foreign-agent
          ];
        };

        # Break-glass USB stick: boots, reflashes foreign-agent's SD card, powers off
        "foreign-agent-recovery" = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = [
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.page-size-16k
                raspberry-pi-5.display-vc4
                sd-image
              ];
            }
            ./hosts/foreign-agent/recovery-stick
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
        "ronove" = nixpkgs.lib.nixosSystem {
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

      # SD image outputs (aarch64 - need an aarch64 builder)
      images.foreign-agent = self.nixosConfigurations.foreign-agent.config.system.build.sdImage;
      images.foreign-agent-recovery = self.nixosConfigurations.foreign-agent-recovery.config.system.build.sdImage;
    };
}
