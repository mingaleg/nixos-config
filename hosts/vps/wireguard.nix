{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;

  # Road-warrior WireGuard peers are auto-derived from any machine in
  # layout.nix that has a `vpn = { ip; publicKey; }` block.
  vpnPeers = lib.filterAttrs (_: m: m ? vpn) layout.machines;
  clientPeers = lib.mapAttrsToList (_: m: {
    publicKey = m.vpn.publicKey;
    allowedIPs = [ "${m.vpn.ip}/32" ];
  }) vpnPeers;
in
{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-vps-private = {
    file = ../../secrets/wireguard-vps-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wireguard.interfaces = {
    # Tunnel to ronove (home network gateway)
    wg-pi = {
      ips = [ "10.200.0.1/24" ];
      listenPort = 51821;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;
      mtu = 1380;

      peers = [
        {
          # ronove
          publicKey = "CPD60Ky/T0u5LAOlE3ceTbJGHDNQV1jhJEGZcIlRYAE=";
          allowedIPs = [
            "10.200.0.2/32"                                # ronove's tunnel IP
            "172.26.249.0/24"                               # Home network
            "${layout.machines.modem.interfaces.usb.ip}/32" # Cellular modem, routed via ronove
          ];
          persistentKeepalive = 25;
        }
      ];

      # Fix the route to use ronove as gateway
      postSetup = ''
        ${pkgs.iproute2}/bin/ip route replace 172.26.249.0/24 via 10.200.0.2 dev wg-pi
        ${pkgs.iproute2}/bin/ip route replace ${layout.machines.modem.interfaces.usb.ip}/32 via 10.200.0.2 dev wg-pi

        # Clamp MSS for TCP packets traversing the 1380 MTU tunnel
        ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -o wg-pi -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD -i wg-pi -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
      '';

      postShutdown = ''
        ${pkgs.iproute2}/bin/ip route del 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
        ${pkgs.iproute2}/bin/ip route del ${layout.machines.modem.interfaces.usb.ip}/32 via 10.200.0.2 dev wg-pi || true

        # Remove MSS clamping rules
        ${pkgs.iptables}/bin/iptables -t mangle -D FORWARD -o wg-pi -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
        ${pkgs.iptables}/bin/iptables -t mangle -D FORWARD -i wg-pi -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
      '';
    };

    # VPN for clients (laptops, phones, etc.)
    wg-clients = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;
      mtu = 1380;

      # Auto-derived from layout.nix - see vpnPeers/clientPeers above.
      peers = clientPeers;

      # Route client traffic to home network through the ronove tunnel
      # (|| true makes it non-fatal if ronove isn't connected yet)
      postSetup = ''
        ${pkgs.iproute2}/bin/ip route replace 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
        ${pkgs.iproute2}/bin/ip route replace ${layout.machines.modem.interfaces.usb.ip}/32 via 10.200.0.2 dev wg-pi || true
      '';

      postShutdown = ''
        ${pkgs.iproute2}/bin/ip route del 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
        ${pkgs.iproute2}/bin/ip route del ${layout.machines.modem.interfaces.usb.ip}/32 via 10.200.0.2 dev wg-pi || true
      '';
    };
  };
}
