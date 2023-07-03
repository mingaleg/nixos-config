{
  description = "mingaleg's NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: {
    nixosConfigurations = {
      # By default, NixOS will try to refer the nixosConfiguration with its hostname.
      # so the system named `minganix` will use this configuration.
      # However, the configuration name can also be specified using `sudo nixos-rebuild switch --flake /path/to/flakes/directory#<name>`.
      # The `nixpkgs.lib.nixosSystem` function is used to build this configuration, the following attribute set is its parameter.
      # Run `sudo nixos-rebuild switch --flake .#minganix` in the flake's directory to deploy this configuration on any NixOS system
      "minganix" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = inputs;

        # <https://nixos.org/manual/nixpkgs/unstable/#module-system-introduction>
        modules = [
          ./configuration.nix

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.mingaleg = import ./home.nix;

            home-manager.extraSpecialArgs = inputs;
          }
        ];
      };
    };
  };
}

