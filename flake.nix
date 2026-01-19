{
  description = "mingaleg's NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      home-manager-modules = [
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.mingaleg = import ./home.nix;
          home-manager.extraSpecialArgs = inputs;
        }
      ];
    in
    {
      nixosConfigurations = {
        # By default, NixOS will try to refer the nixosConfiguration with its hostname.
        # so the system named `minganix` will use this configuration.
        # However, the configuration name can also be specified using `sudo nixos-rebuild switch --flake /path/to/flakes/directory#<name>`.
        # The `nixpkgs.lib.nixosSystem` function is used to build this configuration, the following attribute set is its parameter.
        # Run `sudo nixos-rebuild switch --flake .#minganix` in the flake's directory to deploy this configuration on any NixOS system
        "minganix" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            ./hosts/minganix
          ] ++ home-manager-modules;
        };

        # Run `sudo nixos-rebuild switch --flake .#mingamini` to deploy this configuration
        "mingamini" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [
            ./hosts/mingamini
          ] ++ home-manager-modules;
        };
      };
    };
}

