{ lib, ... }:

let
  layout = import ../home-network/layout.nix;

  # Same shape as the DNS records pihole serves (modules/pihole.nix's
  # `dnsHosts`): every address a machine has - each LAN/WLAN interface plus a
  # `vpn` pseudo-interface for roamers - resolves both the FQDN and the short
  # name. Hosts with several interfaces therefore appear once per address, and
  # glibc returns all of them.
  addressesOf = m: lib.mapAttrsToList (_: iface: iface.ip) (
    (m.interfaces or { }) // (lib.optionalAttrs (m ? vpn) { vpn = m.vpn; })
  );

  entries = lib.concatLists (lib.mapAttrsToList (name: m:
    map (ip: { ${ip} = [ "${name}.${layout.domain}" name ]; }) (addressesOf m)
  ) layout.machines);
in
{
  # Static /etc/hosts entries for the whole fleet, so name lookups keep working
  # when pihole is down, being rebuilt, or (on vps) simply not the resolver.
  # This is a superset of what DNS serves, not a replacement: it is only
  # authoritative for the machines declared in home-network/layout.nix.
  networking.hosts = lib.mkMerge entries;
}
