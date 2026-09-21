{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
    ../../modules/core-server
    ./wireguard.nix
    ./murmur.nix
  ];

  networking.hostName = "vps";

  # Disable Google OS Login (we're using standard SSH keys)
  security.googleOsLogin.enable = lib.mkForce false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    tcpdump
    wireguard-tools
  ];

  # Enable IP forwarding for routing
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ 51820 51821 ];

    # Allow forwarding between WireGuard interfaces and to internet
    extraCommands = ''
      # Forward between WireGuard interfaces (for home network access)
      iptables -A FORWARD -i wg-clients -o wg-pi -j ACCEPT
      iptables -A FORWARD -i wg-pi -o wg-clients -j ACCEPT

      # NAT for wg-clients to internet (routes all traffic)
      iptables -A FORWARD -i wg-clients -j ACCEPT
      iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o eth0 -j MASQUERADE
    '';
  };

  # 10GB GCE disk with the ext4 default of 640k inodes: the journal grew to
  # 971MB across 28 files and, together with 14 uncollected system generations,
  # exhausted the inode table - `nixos-rebuild` then died in Python's
  # gettempdir() and even `nix-collect-garbage` could not create its lock file.
  # Generation GC comes from core-server; cap the journal here because the
  # right size depends on the host's disk.
  services.journald.extraConfig = "SystemMaxUse=200M";

  system.stateVersion = "25.11";
}
