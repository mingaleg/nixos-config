{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  # Create mingaleg user with SSH keys
  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
  };

  # Allow wheel group sudo access
  security.sudo.wheelNeedsPassword = false;

  # Trust mingaleg for remote Nix operations
  nix.settings.trusted-users = [ "root" "mingaleg" ];

  # Disable Google OS Login (we're using standard SSH keys)
  security.googleOsLogin.enable = lib.mkForce false;

  # Basic system configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
