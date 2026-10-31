{ config, pkgs, lib, ... }:

{
  imports = [
    ../core-common
  ];

  # ronove's fleet-deployer deploys as mingaleg (passwordless sudo, below).
  users.users.mingaleg.openssh.authorizedKeys.keys = [
    (builtins.readFile ../../ssh-keys/fleet-deployer.pub)
  ];

  # Agenix configuration
  age.identityPaths = [ "/root/.ssh/agenix-hosts" ];

  # Headless server: key-only SSH, no root login
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
  };

  # Allow remote deploys (nixos-rebuild --target-host) without a sudo password
  security.sudo.wheelNeedsPassword = false;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;
}
