{ ... }:

{
  imports = [ ../../modules/pihole.nix ];

  pihole.interface = "enp2s0";
  # Stood up in parallel with pi's pihole for DNS validation; pi remains the
  # DHCP server until the cutover step. Only one instance on the LAN may run
  # DHCP at a time.
  pihole.dhcpActive = false;
}
