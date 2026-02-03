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
    openFirewallDHCP = true;       # Ports 67/68 for DHCP
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
          "172.26.249.254 linksys.home.mingalev.net linksys"
          "172.26.249.11 mingamini.home.mingalev.net mingamini"
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
        dnsmasq_lines = [
          "local=/home.mingalev.net/"
          "domain=home.mingalev.net"  # Send domain to DHCP clients
        ];
      };
      dhcp = {
        active = true;
        start = "172.26.249.100";
        end = "172.26.249.149";
        router = "172.26.249.254";
        netmask = "255.255.255.0";
        leaseTime = "7h";
        # Static leases: "MAC,IP,hostname,lease_time"
        hosts = [
          "00:f6:20:79:3d:4f,172.26.249.159,chromecast-ultra"
          "2c:cf:67:cc:55:39,172.26.249.253,pi"
          "28:d0:ea:c9:d0:a1,172.26.249.1,mingapred"
          "f4:5c:89:8a:82:8f,172.26.249.10,mingamac"
          "f4:7b:09:f7:f0:1c,172.26.249.11,mingamini"
        ];
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
