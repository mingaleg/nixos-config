{ lib, ... }:

let
  layout = import ../home-network/layout.nix;

  # Same shape as the DNS records pihole serves (modules/pihole.nix's
  # `dnsHosts`): every address a machine has - each LAN/WLAN interface plus a
  # `vpn` pseudo-interface for roamers - resolves the FQDN and the short name.
  # Hosts with several interfaces therefore appear once per address, and glibc
  # returns all of them.
  #
  # The root-anchored "fqdn." alias is not redundant. glibc's `files` backend
  # compares names literally and does not strip a trailing dot, while ssh's
  # CanonicalizeHostname builds its candidate as "%s.%s." precisely to anchor
  # it - so without this alias canonicalization only ever works via DNS, and
  # `ssh ronove` fails on a host that resolves `ronove` from /etc/hosts fine.
  # (systemd-resolved normalises the dot away, which masks this on hosts that
  # run it, e.g. ronove but not vps.)
  addressesOf = m: lib.mapAttrsToList (_: iface: iface.ip) (
    (m.interfaces or { }) // (lib.optionalAttrs (m ? vpn) { vpn = m.vpn; })
  );

  entries = lib.concatLists (lib.mapAttrsToList (name: m:
    map (ip: {
      ${ip} = [
        "${name}.${layout.domain}"
        "${name}.${layout.domain}."
        name
      ];
    }) (addressesOf m)
  ) layout.machines);
in
{
  # Static /etc/hosts entries for the whole fleet, so name lookups keep working
  # when pihole is down, being rebuilt, or (on vps) simply not the resolver.
  # This is a superset of what DNS serves, not a replacement: it is only
  # authoritative for the machines declared in home-network/layout.nix.
  networking.hosts = lib.mkMerge entries;
}
