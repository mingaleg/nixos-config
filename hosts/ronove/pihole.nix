{ ... }:

{
  imports = [ ../../modules/pihole.nix ];

  pihole.interface = "enp2s0";
  # DHCP cut over from pi to ronove. Only one instance on the LAN may run
  # DHCP at a time.
  pihole.dhcpActive = true;

  # Services on ronove get their own names (fleet-deployer.ronove,
  # pegasus.ronove), told apart by nginx on port 80 - see web-proxy.nix,
  # which also fronts the Pi-hole web interface itself.
  pihole.wildcardMachines = [ "ronove" ];
  pihole.webProxied = true;
}
