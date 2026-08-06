{ config, pkgs, lib, ... }:

let
  layout = import ../home-network/layout.nix;

  # Machines without a LAN `interfaces` block (e.g. VPN-only roamers) don't
  # get DHCP leases (DHCP doesn't apply to them - see dhcpHosts below).
  lanMachines = lib.filterAttrs (_: m: m ? interfaces) layout.machines;

  # Generate DNS host entries: "IP FQDN shortname" (one entry per interface,
  # plus a "vpn" pseudo-interface for machines with a vpn.ip)
  dnsHosts = lib.concatLists (lib.mapAttrsToList (name: m:
    lib.mapAttrsToList (_ifaceName: iface:
      "${iface.ip} ${name}.${layout.domain} ${name}"
    ) ((m.interfaces or { }) // (lib.optionalAttrs (m ? vpn) { vpn = m.vpn; }))
  ) layout.machines);

  # Generate DHCP static leases for all interfaces with MAC addresses: "MAC,IP,hostname"
  dhcpHosts = lib.concatLists (lib.mapAttrsToList (name: m:
    lib.mapAttrsToList (_ifaceName: iface:
      "${iface.mac},${iface.ip},${name}"
    ) (lib.filterAttrs (_: iface: iface ? mac) m.interfaces)
  ) lanMachines);

  # Build a DHCP option 121 (classless static route) value from a list of
  # { destination, gateway } pairs, e.g. { destination = "10.200.0.0/24"; gateway = ...; }.
  # When option 121 is present, it overrides the default gateway (option 3).
  classlessStaticRoutes = routes:
    "dhcp-option=option:classless-static-route,"
    + lib.concatStringsSep "," (lib.concatMap (r: [ r.destination r.gateway ]) routes);
in
{
  options.pihole = {
    interface = lib.mkOption {
      type = lib.types.str;
      description = "LAN interface pihole-ftl listens on for DHCP/router advertisements.";
    };

    dhcpActive = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether this pihole instance runs the DHCP server. Only one instance
        on the LAN should have this enabled at a time.
      '';
    };
  };

  config = {
    services.pihole-web = {
      enable = true;
      ports = [80];
    };

    services.pihole-ftl = {
      enable = true;

      # Open firewall ports
      openFirewallDNS = true;                      # Port 53 for DNS
      openFirewallDHCP = config.pihole.dhcpActive;  # Ports 67/68 for DHCP
      openFirewallWebserver = true;                 # Port 80 for web interface

      settings = {
        dns = {
          listeningMode = "all";
          upstreams = [
            "1.1.1.1"
            "1.0.0.1"
            "8.8.8.8"
          ];
          domainNeeded = true;
          expandHosts = true;
          domain.name = layout.domain;
          domain.local = true;  # Don't forward queries for this domain upstream
          localise = false;
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

            # IPv6 Router Advertisement - fixes missing on-link flag from Linksys
            "enable-ra"
            "ra-param=${config.pihole.interface},0,0"  # interface, mtu (0=default), router-lifetime (0=not a default gateway)

            # Filter all AAAA records to avoid IPv6 MTU issues on direct path
            # IPv6 DHCP/SLAAC and router advertisements still work for local connectivity
            "filter-AAAA"

            # Default route, WireGuard networks + modem host (all via ronove)
            (let
              ronove = layout.machines.ronove.interfaces.eth.ip;
              modem = layout.machines.modem.interfaces.usb.ip;
            in classlessStaticRoutes [
              { destination = "0.0.0.0/0"; gateway = layout.network.defaultGateway; }
              { destination = "10.200.0.0/24"; gateway = ronove; }
              { destination = "10.100.0.0/24"; gateway = ronove; }
              { destination = "${modem}/32"; gateway = ronove; }
            ])
          ];
        };
        dhcp = {
          active = config.pihole.dhcpActive;
          start = layout.network.dhcp.start;
          end = layout.network.dhcp.end;
          router = layout.network.defaultGateway;
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
  };
}
