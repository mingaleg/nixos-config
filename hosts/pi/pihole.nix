{ ... }:

{
  imports = [ ../../modules/pihole.nix ];

  pihole.interface = "end0";
  # DHCP moved to ronove; pi keeps serving DNS.
  pihole.dhcpActive = false;
}
