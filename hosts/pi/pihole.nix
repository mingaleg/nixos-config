{ ... }:

{
  imports = [ ../../modules/pihole.nix ];

  pihole.interface = "end0";
  pihole.dhcpActive = true;
}
