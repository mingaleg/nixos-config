let
  # Your user SSH public key (for managing secrets)
  mingaleg = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdGlOYUp5OVA31vFPBYtMRZwbqFqFNOuv2JN3mwDZcc mingaleg@mingapred";

  # Global host key (deployed to all NixOS machines for decryption)
  allHosts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIcZhxyhWjJzfD+i71YssKqUbwG+cAw/ZCrxLvuxmUM agenix-hosts";

  # Import WireGuard secrets from separate file
  wireguardSecrets = import ./wireguard.nix;
in
wireguardSecrets // {
  # Murmur (Mumble server) environment: MURMUR_SERVER_PASSWORD and MURMUR_SUPW
  "murmur-env.age".publicKeys = [ mingaleg allHosts ];

  # VPN user credentials (EAP-MSCHAPv2 passwords)
  "vpn-users.age".publicKeys = [ mingaleg allHosts ];

  # Google Cloud Platform DNS service account credentials (JSON key)
  "gcp-dns-credentials.age".publicKeys = [ mingaleg allHosts ];
}
