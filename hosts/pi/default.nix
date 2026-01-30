{ config, pkgs, ... }:

{
  imports = [
    # skipped for now -- will add after a first boot
    # ./hardware-configuration.nix
  ];

  # Boot configuration for Raspberry Pi
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "pi";
  
  # Enable networking
  networking.networkmanager.enable = true;
  
  # Enable SSH
  services.openssh.enable = true;
  
  # Your user
  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
    hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";
  };

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];

  # Allow unfree packages if needed
  nixpkgs.config.allowUnfree = true;

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "Europe/London";

  system.stateVersion = "25.11";
}