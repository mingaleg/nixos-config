{ ... }:

{
  imports = [ ../../modules/pihole.nix ];

  pihole.interface = "enp2s0";
  # DHCP cut over from pi to ronove. Only one instance on the LAN may run
  # DHCP at a time.
  pihole.dhcpActive = true;
}
