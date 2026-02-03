{ config, pkgs, lib, ... }:

let
  layout = import ../../home-network/layout.nix;

  # Generate DNS host entries: "IP FQDN shortname"
  dnsHosts = lib.mapAttrsToList (name: m:
    "${m.ip} ${name}.${layout.domain} ${name}"
  ) layout.machines;

  # Generate DHCP static leases for machines with MAC addresses: "MAC,IP,hostname"
  dhcpHosts = lib.mapAttrsToList (name: m:
    "${m.mac},${m.ip},${name}"
  ) (lib.filterAttrs (_: m: m ? mac) layout.machines);
in
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
        domain.name = layout.domain;
        domain.local = true;  # Don't forward queries for this domain upstream
        hosts = dnsHosts;
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
          "local=/${layout.domain}/"
          "domain=${layout.domain}"  # Send domain to DHCP clients
        ];
      };
      dhcp = {
        active = true;
        start = layout.network.dhcp.start;
        end = layout.network.dhcp.end;
        router = layout.network.router;
        netmask = layout.network.netmask;
        leaseTime = layout.network.dhcp.leaseTime;
        hosts = dhcpHosts;
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
