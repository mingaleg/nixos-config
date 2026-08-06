Preamble (Stage 1)
===

We will set up a new nixos server machine called `ronove`. The machine is currently a fresh NixOS installation available via 172.26.249.180.
The machine has a user `mingaleg` available via ssh with no certificate yet (only passphrase yet).

The machine will need to get address 172.26.249.251.
Ultimatelly, it will take from all the services from pi host and replace it.
For now, we do not move any network-related services, we will do it later, but we need to plan in advance.
Think through how to sequence with corresponding changes in `pi`, on the network router, and on `vps` when moving existing network-related
services from `pi`.

We will set up core-server module which will be used for this host. Relevant parts of existing core-desktop module
should be factotored out to avoid code duplication.
Among other things, we should carry over mingaleg user and ssh access via existing certificate.

Services we can already carry over (may be an incomplete list):
* nginix
* samba (we will ned to mount connected NAS as /mnt/pegasus)

Minimize the amount of times I will need to make manual changes (including manually typing the password).

Stage 1 status: done
===

- `modules/core-common` factored out (user/ssh/nix settings shared by desktop and server
  hosts); `modules/core-server` built on top of it (key-only SSH, passwordless sudo for
  remote deploys, agenix identity path, nix gc/optimise); `modules/core-desktop` refactored
  to use `core-common` too.
- `hosts/ronove` created (`core-server` + `nginx-www.nix` + `samba-server.nix`, both ported
  from `pi`'s modules) and wired into `flake.nix`.
- `mingaleg` SSH access carried over via the existing `ssh-keys/mingaleg-masterkey.pub`
  (bootstrapped once with `ssh-copy-id`, no password typed into any tool).
- `ronove` given a DHCP static reservation at `172.26.249.251` via
  `home-network/layout.nix` (served by `pi`'s pihole - no change needed on the router).
- `pegasus` NAS disk physically moved from `pi` to `ronove` (same ext4 filesystem/UUID,
  `/mnt/pegasus`); Samba re-created there (`smbpasswd -a mingaleg`) and `nginx` serving
  `/mnt/pegasus/www` on port 6278, mirroring `pi`'s old setup.
- Desktop clients (`minganix`, `mingamini` - both use `core-desktop`) repointed their CIFS
  mount from `//pi/pegasus` to `//ronove/pegasus`. Verified working.

Stage 2 status: done
===

- CIFS mount factored out of `core-desktop` into a shared `modules/pegasus-mount.nix`
  (device, credentials, `cache=loose`, etc.), used by both `core-desktop` and `pi`. Exposes
  a `pegasusMount.host` option (default `"ronove"`) so individual hosts can override how
  they address the share.
- `pi`'s now-redundant static-file roles decommissioned: `samba-server.nix` deleted (`pi` is
  no longer a Samba server - `ronove` is), and the stale local `fileSystems."/mnt/pegasus"`
  ext4 entry removed (that disk physically moved to `ronove` in Stage 1, so the UUID no
  longer existed on `pi`). `pi`'s `nginx-www.nix` was kept and now serves `/mnt/pegasus/www`
  over the same CIFS mount as everyone else.
- `ronove`'s `samba-server.nix` performance tuning cleaned up: dropped a stale 128KB
  `SO_RCVBUF`/`SO_SNDBUF` socket-options cap and SMB1-era `read raw`/`write raw`/`aio *`
  settings (dead weight under `server min protocol = SMB3`), and disabled SMB signing
  (LAN/VPN-only, signing overhead not needed). Confirmed CIFS throughput now rides the
  network ceiling on both WiFi (mingamini, ~43->~70 MB/s) and gigabit Ethernet (pi, ~115
  MB/s, matching iperf3's ~940 Mbit/s raw ceiling).
- `smb-credentials-pegasus` moved from a manually-placed `/etc/nixos/smb-credentials-pegasus`
  file to an agenix secret (`secrets/smb-credentials-pegasus.age`), decrypted to
  `config.age.secrets.smb-credentials-pegasus.path` at activation. Encrypted directly on
  `mingamini` from its existing in-use credentials file, without the plaintext passing
  through the assistant.
- Fixed a `pi`-specific mount failure (`mount error: could not resolve address for ronove`):
  `pi` is itself the DNS server, and `systemd-resolved` there didn't reliably route
  unqualified-hostname lookups back through its own Pi-hole (global "Current DNS Server" was
  landing on `1.1.1.1`, which has no idea about local hosts). Fixed by overriding
  `pegasusMount.host` to `layout.machines.ronove.interfaces.eth.ip` on `pi` only, rather than
  depending on its own DNS resolution for this mount.
- `minganix` host removed entirely (unused) rather than wired into agenix, since it was the
  only `core-desktop` consumer without an agenix identity configured.

Stage 3 status: in progress
===

- **Pi-hole (DNS + DHCP) - step 1/4 done, deployed and validated**: `pihole-ftl`/`pihole-web`
  config factored out of `hosts/pi/pihole.nix` into a shared `modules/pihole.nix` (takes a
  `pihole.interface` option for the RA/DHCP interface and a `pihole.dhcpActive` option so only
  one instance runs DHCP at a time). `hosts/ronove/pihole.nix` added and wired into
  `hosts/ronove/default.nix`, standing up DNS + web on `ronove` in parallel with
  `pihole.interface = "enp2s0"`. Validated after deploy: local records resolve correctly
  (`pi.home.mingalev.net` -> `172.26.249.253` queried from `ronove`), upstream forwarding
  works, and `ronove.home.mingalev.net` resolves correctly to `172.26.249.251` when queried
  from another host. (A host's own pihole always resolves its own hostname to loopback when
  queried from itself - confirmed as a pre-existing dnsmasq quirk present on `pi` too, not a
  regression; doesn't affect other clients.)

- **Pi-hole DHCP cutover - steps 2-4 done, not yet deployed**: `pihole.dhcpActive` flipped to
  `false` on `pi` and `true` on `ronove` (`hosts/pi/pihole.nix`, `hosts/ronove/pihole.nix`) -
  `openFirewallDHCP` in `modules/pihole.nix` follows the same flag, so firewall ports move
  automatically. Also gave `ronove` a static IP (`hosts/ronove/default.nix`,
  `networking.useDHCP = false` + static `enp2s0` config mirroring `pi`'s pattern, driven by
  `home-network/layout.nix`), replacing the old NetworkManager-DHCP setup - now that `ronove`
  is meant to run the DHCP server, it can't depend on DHCP (from itself or `pi`) to get its
  own address at boot. No router change needed (step 3 - router is only the default gateway).
  Step 4 (clients picking up the new server) is automatic once deployed, either on next lease
  renewal or forced per-device.

Remaining steps (Stage 3+)
===

### 1. Network-related services still on pi (deferred by design)

These all stay on `pi` for now. Moving each has different blast radius and different
external dependencies:

- **Pi-hole (DNS + DHCP)** - [done, see Stage 3 status above] fully implemented (DNS stood up
  on `ronove` in parallel, then DHCP cut over from `pi`); pending your deploy + confirmation
  that clients pick up the new DHCP/DNS server correctly.

- **WireGuard endpoint (`wg0`) + NAT to the cellular modem (`enu2`)** - tightly coupled to
  the HiLink modem being *physically* attached to `pi` (this is `pi`'s CGNAT workaround for
  internet uplink). This cannot move to `ronove` without also moving the modem hardware.
  Decide explicitly whether that's ever wanted; if not, this role is permanent on `pi`
  (or whatever box the modem is plugged into) regardless of everything else moving off.
  If the modem *does* move later:
  1. Generate a new WireGuard keypair for `ronove`, add it as `vps`'s `wg-pi` peer
     (`hosts/vps/wireguard.nix`), update `allowedIPs`/routes there.
  2. Update the router's port-forward for UDP 51821 to point at `ronove`
     (`172.26.249.251`) instead of `pi` (`172.26.249.253`) - manual, out-of-band, not
     managed by this repo.
  3. Only then decommission `pi`'s `wireguard-vpn.nix`.

- **Chrony NTP server** - low risk, no external dependents besides LAN clients pointing at
  `pi` for time. Can move to `ronove` independently of the above, whenever convenient.

- **`strongswan.nix`** (already disabled, kept for rollback) - delete once confident the
  WireGuard-only VPN has been stable for a while. No coordination needed.

### 2. Final pi decommission

Once Pi-hole and (if ever) the VPN/NAT/modem role have moved off, `pi` can be powered down.
Until then it remains the home network's DNS/DHCP/VPN/NAT appliance - do not remove those
roles from `hosts/pi` until their replacements are confirmed stable on `ronove`.
