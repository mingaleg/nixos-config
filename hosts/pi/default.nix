{ config, pkgs, lib, ... }:

{
  imports = lib.optionals (builtins.pathExists ./hardware-configuration.nix) [
    ./hardware-configuration.nix
  ];

  networking.hostName = "pi";
  
  # Enable remote deployments
  nix.settings.trusted-users = [ "root" "mingaleg" ];
  
  # Mount NTFS drive to /mnt/pegasus
  fileSystems."/mnt/pegasus" = {
    device = "/dev/disk/by-uuid/B66C1D7C6C1D3897";
    fsType = "ntfs-3g";
    options = [ "defaults" "nofail" "uid=1000" "gid=100" "dmask=022" "fmask=133" ];
  };
  
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
    ntfs3g
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
