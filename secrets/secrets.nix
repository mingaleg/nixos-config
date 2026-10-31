let
  # Your user SSH public key (for managing secrets)
  mingaleg = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdGlOYUp5OVA31vFPBYtMRZwbqFqFNOuv2JN3mwDZcc mingaleg@mingapred";

  # Global host key (deployed to all NixOS machines for decryption)
  allHosts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIcZhxyhWjJzfD+i71YssKqUbwG+cAw/ZCrxLvuxmUM agenix-hosts";

  # foreign-agent's own SSH host key, which doubles as its agenix identity.
  # Its secrets are encrypted to it alone (not allHosts) because the key also
  # ships on the recovery USB stick kept at Igor and Tanya's house.
  foreignAgent = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHhd0gkmCKyDbeKV94CaAX/OeFYW4Aq+S/MAq92rfNNy root@foreign-agent";

  # Import WireGuard secrets from separate file
  wireguardSecrets = import ./wireguard.nix;
in
wireguardSecrets // {
  # Murmur (Mumble server) environment: MURMUR_SERVER_PASSWORD and MURMUR_SUPW
  "murmur-env.age".publicKeys = [ mingaleg allHosts ];

  # CIFS credentials for mounting //ronove/pegasus
  "smb-credentials-pegasus.age".publicKeys = [ mingaleg allHosts ];

  # HTTP basic-auth password for the ttyd web terminal on vps
  "ttyd-password.age".publicKeys = [ mingaleg allHosts ];

  # ronove's fleet-deployer: SSH key it deploys with, and its API bearer token
  "fleet-deployer-ssh.age".publicKeys = [ mingaleg allHosts ];
  "fleet-deployer-token.age".publicKeys = [ mingaleg allHosts ];

  # foreign-agent: WireGuard key and Wi-Fi PSKs (SOLND082_PSK, MINGAHOME_PSK)
  "wireguard-foreign-agent-private.age".publicKeys = [ mingaleg foreignAgent ];
  "foreign-agent-wifi.age".publicKeys = [ mingaleg foreignAgent ];
}
