{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
    ./wireguard.nix
  ];

  networking.hostName = "vps";

  # User configuration
  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
    settings.PasswordAuthentication = false;
  };

  # Agenix
  age.identityPaths = [ "/root/.ssh/agenix-hosts" ];

  # Disable Google OS Login (we're using standard SSH keys)
  security.googleOsLogin.enable = lib.mkForce false;

  # Allow wheel group sudo access without password
  security.sudo.wheelNeedsPassword = false;

  # Trust mingaleg for remote Nix operations
  nix.settings.trusted-users = [ "root" "mingaleg" ];

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
      iptables -t nat -A POSTROUTING -o wg-pi -j MASQUERADE

      # NAT for wg-clients to internet (routes all traffic)
      iptables -A FORWARD -i wg-clients -j ACCEPT
      iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o eth0 -j MASQUERADE
    '';
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
