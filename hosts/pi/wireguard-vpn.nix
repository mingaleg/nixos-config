{ config, pkgs, ... }:

let
  layout = import ../../home-network/layout.nix;
in
{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-pi-private = {
    file = ../../secrets/wireguard-pi-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.200.0.2/24" ];
      listenPort = 51821;
      privateKeyFile = config.age.secrets.wireguard-pi-private.path;

      peers = [
        {
          # VPS
          publicKey = "TnZpPk/diUblm/aQG/dm9yqFPCnfjQrZ/g5xwoAcChU=";
          allowedIPs = [
            "10.200.0.1/32"    # VPS tunnel IP
            "10.100.0.0/24"    # VPN clients
          ];
          endpoint = "34.39.81.90:51821";
          persistentKeepalive = 25;
        }
      ];

      # NAT for VPN clients accessing home network
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o end0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -o end0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
      '';

      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o end0 -j MASQUERADE || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -o end0 -j ACCEPT || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT || true
      '';
    };
  };

  # Open WireGuard port
  networking.firewall.allowedUDPPorts = [ 51821 ];
}
