{ config, pkgs, lib, ... }:

{
  services.pihole-web = {
    enable = true;
    ports = [80];
  };

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
        domain.local = true;  # Don't forward queries for this domain upstream
        hosts = [
          "172.26.249.1 mingapred.home.mingalev.net mingapred"
          "172.26.249.253 pi.home.mingalev.net pi"
          "172.26.249.254 syslink.home.mingalev.net syslink"
        ];
      };
      webserver = {
        port = "80";
        api = {
          pwhash = "$BALLOON-SHA256$v=1$s=1024,t=32$aEOQdLB2YJE+JonvYAkS8w==$1Rrlzx4qKDP8c+G+3FAHbMc7BKym5ZK+1h9SFOYSsKI=";
        };
        session = {
          timeout = 43200; # 12h
        };
      };
      misc = {
        # Explicitly tell dnsmasq to resolve this domain locally, never forward upstream
        dnsmasq_lines = [ "local=/home.mingalev.net/" ];
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
