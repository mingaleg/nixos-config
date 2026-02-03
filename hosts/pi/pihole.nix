{ config, pkgs, lib, ... }:

{
  services.pihole-web.enable = true;

  services.pihole-ftl = {
    enable = true;

    # Open firewall ports
    openFirewallDNS = true;        # Port 53 for DNS
    openFirewallWebserver = true;  # Port 80 for web interface

    settings = {
      dns = {
        upstreams = [
          "1.1.1.1"
          "1.0.0.1"
          "8.8.8.8"
        ];
        domainNeeded = true;
        expandHosts = true;
        domain.name = "home.mingalev.net";
        hosts = [
          "172.26.249.1 mingapred"
          "172.26.249.253 pi"
          "172.26.249.254 syslink"
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
