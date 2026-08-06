{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  imports = lib.optionals (builtins.pathExists ./hardware-configuration.nix) [
    ./hardware-configuration.nix
  ] ++ [
    ../../modules/pegasus-mount.nix
    ../../modules/network-tuning.nix
    ./pihole.nix
    # ./strongswan.nix  # Disabled in favor of WireGuard-only VPN (kept for rollback)
    # ./wireguard-vpn.nix  # Disabled - WireGuard endpoint moved to ronove (kept for rollback)
    ./nginx-www.nix
  ];

  # Agenix configuration
  age.identityPaths = [ "/root/.ssh/agenix-hosts" ];

  # Mount pegasus by IP: pi is itself the DNS server, and its
  # systemd-resolved setup doesn't reliably resolve local hostnames back
  # through its own pihole, so avoid that self-dependency here.
  pegasusMount.host = layout.machines.ronove.interfaces.eth.ip;

  networkTuning.interface = "end0";

  networking.hostName = "pi";
  
  nix.settings.trusted-users = [ "root" "mingaleg" ];

  # Static IP for the DHCP/DNS server
  networking.useDHCP = false;
  networking.interfaces.end0 = {
    ipv4.addresses = [{
      address = layout.machines.pi.interfaces.eth.ip;
      prefixLength = layout.network.prefixLength;
    }];
  };
  # HiLink modem interface - static IP to access modem API at 192.168.8.1
  # No gateway set, so internet traffic stays on end0
  networking.interfaces.enu2 = {
    ipv4.addresses = [{
      address = "192.168.8.100";
      prefixLength = 24;
    }];
  };
  networking.defaultGateway = layout.network.defaultGateway;
  networking.nameservers = [ "127.0.0.1" "1.1.1.1" ];  # Use itself for DNS

  # Allow forwarding to modem interface
  networking.firewall.trustedInterfaces = [ "enu2" ];

  # NAT for modem access - masquerade traffic going to modem
  # so modem sees requests from Pi's IP (192.168.8.100) instead of client IPs
  networking.nat = {
    enable = true;
    externalInterface = "enu2";
    internalInterfaces = [ "end0" ];
  };

  services.openssh.enable = true;

  # NTP server for the local network
  services.chrony = {
    enable = true;
    servers = [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
    ];
    extraConfig = ''
      allow ${layout.network.prefix}.0/24
      local stratum 10
    '';
  };
  networking.firewall.allowedUDPPorts = [ 123 ];

  users.users.mingaleg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../ssh-keys/mingaleg-masterkey.pub)
    ];
    hashedPassword = "$6$MTF1jg6OQAMoJ4t9$hR1aan5eu/g0YDlp7CDVCXlnJmmau4nIExDPOaOACJFhpBPCvRNYMi.RwI5ktJgJZWlt6APujxccrYpqutXAq/";
  };

  environment.systemPackages = with pkgs; [
    vim git htop tmux ntfs3g
    ethtool iproute2 pciutils usbutils
    iperf3 curl wget bind speedtest-cli
    # strongswan  # Disabled in favor of WireGuard (kept for rollback)
    wireguard-tools
  ];

  # Force CPU to performance governor
  powerManagement.cpuFreqGovernor = "performance";  
  # Alternatively, use ondemand but with better settings
  # powerManagement.cpuFreqGovernor = "ondemand";

  boot.loader.raspberry-pi.bootloader = "kernel";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "Europe/London";
  system.stateVersion = "25.11";
}
