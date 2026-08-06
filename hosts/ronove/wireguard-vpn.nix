{ config, pkgs, ... }:

{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-ronove-private = {
    file = ../../secrets/wireguard-ronove-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.200.0.2/24" ];
      listenPort = 51821;
      privateKeyFile = config.age.secrets.wireguard-ronove-private.path;
      mtu = 1380;

      peers = [
        {
          # VPS
          publicKey = "TnZpPk/diUblm/aQG/dm9yqFPCnfjQrZ/g5xwoAcChU=";
          allowedIPs = [
            "10.200.0.1/32"    # VPS tunnel IP
            "10.100.0.0/24"    # VPN clients
          ];
          endpoint = "home-gw.mingalev.net:51821";
          persistentKeepalive = 25;
        }
      ];

      # NAT for VPN clients accessing the home network.
      # (No modem/enu2 role here - that stays on pi for now.)
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o enp2s0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -o enp2s0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -i enp2s0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
      '';

      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o enp2s0 -j MASQUERADE || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -o enp2s0 -j ACCEPT || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i enp2s0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT || true
      '';
    };
  };

  # Open WireGuard port
  networking.firewall.allowedUDPPorts = [ 51821 ];

  # Trust VPN clients coming through wg0 (allows DNS and other services)
  networking.firewall.trustedInterfaces = [ "wg0" ];

  # net.ipv4.ip_forward is enabled by modules/network-tuning.nix
}
