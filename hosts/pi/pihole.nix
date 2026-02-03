{ config, pkgs, lib, ... }:

{
  services.pihole-ftl = {
    enable = true;

    # Open firewall ports
    openFirewallDNS = true;        # Port 53 for DNS
    openFirewallWebserver = true;  # Port 80 for web interface

    # Upstream DNS servers
    settings = {
      dns = {
        upstreams = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
        ];
      };
      webserver = {
        port = "80";
      };
    };

    # Blocklists - Steven Black's unified hosts
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        type = "block";
        enabled = true;
        description = "Steven Black's HOSTS";
      }
    ];
  };

  # Disable systemd-resolved DNS stub listener to avoid port 53 conflict
  services.resolved = {
    enable = true;
    extraConfig = ''
      DNSStubListener=no
    '';
  };
}
