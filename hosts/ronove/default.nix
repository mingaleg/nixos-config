{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core-server
    ./nginx-www.nix
    ./samba-server.nix
    ./pihole.nix
  ];

  networking.hostName = "ronove";
  # IP is assigned via a DHCP static lease reserved on `pi`'s pihole
  # (see home-network/layout.nix) - no static config needed here.
  networking.networkmanager.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  # Pegasus NAS disk, physically moved over from `pi`
  fileSystems."/mnt/pegasus" = {
    device = "/dev/disk/by-uuid/0fd7125c-e77f-4a65-8e3d-984ecb96cadc";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];

  system.stateVersion = "25.11";
}
