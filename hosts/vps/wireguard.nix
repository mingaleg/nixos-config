{ config, pkgs, ... }:

{
  # Agenix secret for WireGuard private key
  age.secrets.wireguard-vps-private = {
    file = ../../secrets/wireguard-vps-private.age;
    owner = "root";
    group = "systemd-network";
    mode = "0440";
  };

  networking.wireguard.interfaces = {
    # Tunnel to Pi (permanent connection through CGNAT)
    wg-pi = {
      ips = [ "10.200.0.1/24" ];
      listenPort = 51821;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;

      peers = [
        {
          # Pi
          publicKey = "vCE5wvOPRlHj2ts6d5t7gKxHB2bULtweDpM/B/6shCM=";
          allowedIPs = [
            "10.200.0.2/32"           # Pi's tunnel IP
            "172.26.249.0/24"         # Home network
          ];
          persistentKeepalive = 25;
        }
      ];

      # Fix the route to use Pi as gateway
      postSetup = ''
        ${pkgs.iproute2}/bin/ip route replace 172.26.249.0/24 via 10.200.0.2 dev wg-pi
      '';

      postShutdown = ''
        ${pkgs.iproute2}/bin/ip route del 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
      '';
    };

    # VPN for clients (laptops, phones, etc.)
    wg-clients = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = config.age.secrets.wireguard-vps-private.path;

      # Clients will be added here
      peers = [
        {
          # Pixel10
          publicKey = "WzQNq6q9JlWsTz7L1ejHHII1SFoHYhQAy/XNahwKClU=";
          allowedIPs = [ "10.100.0.10/32" ];
        }
        {
          # Igor
          publicKey = "oOkMYPF/12FDQOPcCLWYrW+vCXkivl5LNzqax1U2YE8=";
          allowedIPs = [ "10.100.0.11/32" ];
        }
        {
          # Tanya
          publicKey = "QV2Bdze5tUj5Q0JFU4FZeG6RE1G5EaGbx3jFaJCvElg=";
          allowedIPs = [ "10.100.0.12/32" ];
        }
        # Add more clients as needed with IPs 10.100.0.13, .14, .15, etc.
      ];

      # Route client traffic to home network through Pi tunnel
      # (|| true makes it non-fatal if Pi isn't connected yet)
      postSetup = ''
        ${pkgs.iproute2}/bin/ip route replace 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
      '';

      postShutdown = ''
        ${pkgs.iproute2}/bin/ip route del 172.26.249.0/24 via 10.200.0.2 dev wg-pi || true
      '';
    };
  };
}
