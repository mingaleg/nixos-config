let
  # Your user SSH public key (for managing secrets)
  mingaleg = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdGlOYUp5OVA31vFPBYtMRZwbqFqFNOuv2JN3mwDZcc mingaleg@mingapred";

  # Global host key (deployed to all NixOS machines for decryption)
  allHosts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIcZhxyhWjJzfD+i71YssKqUbwG+cAw/ZCrxLvuxmUM agenix-hosts";
in
{
  # WireGuard VPN private keys
  "wireguard-vps-private.age".publicKeys = [ mingaleg allHosts ];
  "wireguard-pi-private.age".publicKeys = [ mingaleg allHosts ];
  "wireguard-mingamini.age".publicKeys = [ mingaleg allHosts ];
}
