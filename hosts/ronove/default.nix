{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/core-server
    ../../modules/network-tuning.nix
    ./nginx-www.nix
    ./samba-server.nix
    ./pihole.nix
    ./wireguard-vpn.nix
  ];

  networking.hostName = "ronove";
  networkTuning.interface = "enp2s0";

  # Static IP now that ronove runs the DHCP/DNS server itself - can't depend
  # on DHCP (from itself or anything else) to get an address at boot.
  networking.useDHCP = false;
  networking.interfaces.enp2s0 = {
    ipv4.addresses = [{
      address = layout.machines.ronove.interfaces.eth.ip;
      prefixLength = layout.network.prefixLength;
    }];
  };
  networking.defaultGateway = layout.network.defaultGateway;
  networking.nameservers = [ "127.0.0.1" "1.1.1.1" ];  # Use itself for DNS

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
