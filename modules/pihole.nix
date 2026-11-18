{ config, options, pkgs, lib, ... }:

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

  # `services.pihole-ftl.lists` is not idempotent on this channel. The generated
  # pihole-ftl-setup script POSTs every declared list to FTL's API and treats any
  # API error as fatal, but the adlist row a successful POST writes lives in
  # gravity.db and outlives reboots - so from the second start onwards FTL
  # answers "The item is already present" and the oneshot exits 1. pihole-ftl
  # `wants` that unit, so it is a permanently failed unit (and a non-zero
  # `nixos-rebuild switch`) for a declaration that is already satisfied.
  #
  # Fixed upstream in nixpkgs PR #551979, merged to master 2026-08-16 but not
  # backported to release-26.05. Cherry-pick the same guard here; `needsSetupPatch`
  # turns this into a no-op once the channel carries the fix, at which point the
  # whole block can be deleted.
  setupScriptModule = "${pkgs.path}/nixos/modules/services/networking/pihole-ftl-setup-script.nix";

  upstreamSetupScript = import setupScriptModule {
    inherit config lib pkgs;
    cfg = config.services.pihole-ftl;
  };

  # Anchored on the single line that extracts the API error, so the guard lands
  # in front of the blanket "any error is fatal" branch that follows it.
  errorProbe = ''error="$($jq '.error' <<< "$result")"'';

  idempotentErrorProbe = ''
    error="$($jq '.error' <<< "$result")"
    if $jq -e '.error.key == "database_error" and .error.hint == "The item is already present"' <<< "$result" > /dev/null; then
        echo "List already present"
        return
    fi'';

  patchedSetupScript =
    builtins.replaceStrings [ errorProbe ] [ idempotentErrorProbe ] upstreamSetupScript;

  needsSetupPatch =
    builtins.pathExists setupScriptModule
    && !(lib.hasInfix "already present" upstreamSetupScript);

  # Where FTL's webserver listens when a reverse proxy owns port 80.
  webBackend = "127.0.0.1:8081";

  # The address a machine's bare name means: its `primary` interface, or its
  # only one. Mirrors the choice modules/hosts-file.nix makes for /etc/hosts.
  primaryIfaces = m:
    let
      ifaces = lib.attrValues (m.interfaces or { });
      marked = lib.filter (i: i.primary or false) ifaces;
    in
    if marked != [ ] then marked else ifaces;

  # "*.<name>" and "*.<name>.<domain>" -> the machine, so services on it can
  # have their own names (fleet-deployer.ronove). Clients' search domains don't
  # help here: systemd-resolved only appends them to single-label names, so
  # "<name>" has to be a zone Pi-hole answers itself.
  # Invalid names are skipped here and reported by the assertion below.
  wildcardIpOf = name:
    let ifaces = primaryIfaces (layout.machines.${name} or { }); in
    if lib.length ifaces == 1 then (lib.head ifaces).ip else null;

  wildcardLines = lib.concatMap (name:
    let ip = wildcardIpOf name; in lib.optionals (ip != null) [
      "local=/${name}/"
      "address=/${name}/${ip}"
      "address=/${name}.${layout.domain}/${ip}"
    ]
  ) config.pihole.wildcardMachines;
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

    wildcardMachines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ronove" ];
      description = ''
        Machines from home-network/layout.nix whose every subdomain resolves to
        them, e.g. fleet-deployer.ronove and fleet-deployer.ronove.<domain>.
      '';
    };

    webProxied = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve the web interface on loopback only (`pihole.webBackend`) for a
        reverse proxy to expose, instead of on port 80 directly.
      '';
    };

    webBackend = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = webBackend;
      description = "host:port of the web interface when `webProxied` is set.";
    };
  };

  config = {
    services.pihole-web = {
      enable = true;
      ports = if config.pihole.webProxied then [ webBackend ] else [ 80 ];
    };

    services.pihole-ftl = {
      enable = true;

      # Open firewall ports
      openFirewallDNS = true;                      # Port 53 for DNS
      openFirewallDHCP = config.pihole.dhcpActive;  # Ports 67/68 for DHCP
      # Port 80 for web interface. When proxied the port is loopback-only (and
      # upstream's port parser can't read an "addr:port" anyway).
      openFirewallWebserver = !config.pihole.webProxied;

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
        # The port comes from services.pihole-web.ports above.
        webserver = {
          api = {
            pwhash = "$BALLOON-SHA256$v=1$s=1024,t=32$aEOQdLB2YJE+JonvYAkS8w==$1Rrlzx4qKDP8c+G+3FAHbMc7BKym5ZK+1h9SFOYSsKI=";
            # Behind a reverse proxy every request arrives from 127.0.0.1, so
            # "local clients skip the login" would mean everyone does. This is
            # FTL's default; pinned so it can't silently flip.
            localAPIauth = true;
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
          ] ++ wildcardLines;
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

    # See `needsSetupPatch` above - re-adding an already-registered blocklist is
    # a no-op, not a failure. Every other API error still fails the unit.
    systemd.services.pihole-ftl-setup.script =
      lib.mkIf needsSetupPatch (lib.mkForce patchedSetupScript);

    # pihole-ftl is Type=simple, so this unit starts while FTL is still starting
    # up. Its closing `pihole -g` then rebuilds gravity.db (holding the lock)
    # just as FTL first opens it: FTL logs "database is locked", gives up, and
    # runs with no blocklists until its next restart - and upstream only signals
    # FTL to reload after the *initial* gravity build, not this one. So always
    # make FTL reopen gravity once setup is over, whether it succeeded or not.
    systemd.services.pihole-ftl-setup.serviceConfig.ExecStopPost =
      pkgs.writeShellScript "pihole-ftl-reload-gravity" ''
        pid=$(${pkgs.systemd}/bin/systemctl show --property MainPID --value pihole-ftl.service)
        [ "''${pid:-0}" -gt 0 ] && ${pkgs.procps}/bin/kill -s SIGRTMIN "$pid"
        exit 0
      '';

    # The gravity run downloads blocklists over HTTPS, which fails while the
    # clock is still wrong after boot (ronove's RTC battery is dead), leaving
    # gravity on the stale cached copy until the next restart. Only the setup
    # waits - pihole-ftl itself must not, since chrony resolves its NTP
    # servers through it.
    systemd.services.pihole-ftl-setup = {
      wants = [ "time-sync.target" ];
      after = [ "time-sync.target" ];
    };

    # Upstream only rotates FTL.log; the dnsmasq query log (pihole.log) grows
    # forever - it had reached 4.6 GB on ronove. FTL keeps it open, hence
    # copytruncate. Queries are kept in pihole-FTL.db anyway, so a week of the
    # text log is plenty.
    services.logrotate.settings.pihole-ftl-dnsmasq = {
      files = [
        "${config.services.pihole-ftl.logDirectory}/pihole.log"
        "${config.services.pihole-ftl.logDirectory}/webserver.log"
      ];
      frequency = "daily";
      rotate = 7;
      compress = true;
      delaycompress = true;
      copytruncate = true;
      su = "pihole pihole";
    };

    assertions = (map (name: {
      assertion = wildcardIpOf name != null;
      message =
        "pihole.wildcardMachines: ${name} must be a machine in"
        + " home-network/layout.nix with one interface, or one marked"
        + " `primary = true`.";
    }) config.pihole.wildcardMachines) ++ [
      {
        assertion = !needsSetupPatch || patchedSetupScript != upstreamSetupScript;
        message = ''
          modules/pihole.nix: pihole-ftl-setup's addList no longer contains the
          error probe this module patches, but it also lacks the upstream
          idempotency fix - re-check the setup script in nixpkgs.
        '';
      }
    ];

    # Disable systemd-resolved DNS stub listener to avoid port 53 conflict.
    # This module is shared across hosts on different nixpkgs channels:
    # services.resolved.settings only exists from ~26.05 onward (extraConfig
    # is removed there); older channels (e.g. pi on 25.11) only have
    # extraConfig. Pick whichever the current channel actually supports.
    services.resolved = {
      enable = true;
    } // (
      if options.services.resolved ? settings
      then { settings.Resolve.DNSStubListener = false; }
      else { extraConfig = "DNSStubListener=no\n"; }
    );
  };
}
