{ lib, ... }:

let
  layout = import ../home-network/layout.nix;

  # Each label resolves in three forms. The root-anchored "fqdn." is not
  # redundant: glibc's `files` backend compares names literally and does not
  # strip a trailing dot, while ssh's CanonicalizeHostname builds its candidate
  # as "%s.%s." precisely to anchor it - so without it `ssh ronove` fails on a
  # host that resolves `ronove` from /etc/hosts fine. (systemd-resolved
  # normalises the dot away, which masks this on hosts that run it, e.g. ronove
  # but not vps.)
  namesFor = label: [
    "${label}.${layout.domain}"
    "${label}.${layout.domain}."
    label
  ];

  # Every address a machine has: its real interfaces plus, for roamers, a `vpn`
  # pseudo-interface. Mirrors modules/pihole.nix's `dnsHosts`.
  ifacesOf = m: (m.interfaces or { }) // (lib.optionalAttrs (m ? vpn) { vpn = m.vpn; });

  realIfacesOf = m: m.interfaces or { };

  # A multi-homed machine needs to say which interface its bare name means -
  # /etc/hosts cannot express "whichever is currently up", and listing several
  # addresses under one name just hands out the first one in file order whether
  # or not it answers. The VPN address is never the default while a real
  # interface exists, so roamers like pixel10 need no marker; only a machine
  # with several real interfaces does.
  ambiguous = lib.filterAttrs (_: m:
    let reals = realIfacesOf m; in
    lib.length (lib.attrNames reals) > 1
    && lib.filterAttrs (_: i: i.primary or false) reals == { }
  ) layout.machines;

  primaryIfaceOf = m:
    let
      reals = realIfacesOf m;
      marked = lib.attrNames (lib.filterAttrs (_: i: i.primary or false) reals);
      realNames = lib.attrNames reals;
    in
    if marked != [ ] then lib.head marked
    else if realNames != [ ] then lib.head realNames # single interface, or caught by the assertion below
    else "vpn"; # VPN-only roamer

  entriesFor = name: m:
    let primary = primaryIfaceOf m; in
    lib.mapAttrsToList (ifaceName: iface: {
      # The bare/FQDN names lead so they stay the canonical name in reverse
      # lookups; <host>-<iface> always works as an explicit second address.
      ${iface.ip} =
        lib.optionals (ifaceName == primary) (namesFor name)
        ++ namesFor "${name}-${ifaceName}";
    }) (ifacesOf m);

  entries = lib.concatLists (lib.mapAttrsToList entriesFor layout.machines);
in
{
  # Static /etc/hosts entries for the whole fleet, so name lookups keep working
  # when pihole is down, being rebuilt, or (on vps) simply not the resolver.
  # This is not a replacement for DNS: it is only authoritative for the machines
  # declared in home-network/layout.nix.
  networking.hosts = lib.mkMerge entries;

  assertions = [
    {
      assertion = ambiguous == { };
      message =
        let
          names = lib.attrNames ambiguous;
          verb = if lib.length names == 1 then "has" else "have";
        in
        "home-network/layout.nix: ${lib.concatStringsSep ", " names} ${verb}"
        + " several interfaces but no `primary = true` on any of them, so the"
        + " bare hostname would resolve to whichever address happens to sort"
        + " first. Mark the interface the bare name should point at.";
    }
  ];
}
