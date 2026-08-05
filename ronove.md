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

Remaining steps (Stage 2+)
===

### 1. Decommission pi's now-redundant static-file roles

`pi` still has `nginx-www.nix`, `samba-server.nix`, and a `fileSystems."/mnt/pegasus"` entry
pointing at a disk that is no longer physically attached (mitigated by the `nofail` mount
option, so it fails silently rather than blocking boot). Low-risk cleanup, no coordination
with router/vps needed:

- Remove the `samba-server.nix` / `nginx-www.nix` imports and the stale `/mnt/pegasus`
  `fileSystems` entry from `hosts/pi/default.nix`.
- Double check nothing else on the LAN still points at `pi` for these (bookmarks, other
  fstabs) before actually pulling the imports.

### 2. Network-related services still on pi (deferred by design)

These all stay on `pi` for now. Moving each has different blast radius and different
external dependencies:

- **Pi-hole (DNS + DHCP)** - highest blast radius: every device on the LAN depends on it.
  Sequencing if/when moved to `ronove`:
  1. Stand up `pihole-ftl`/`pihole-web` on `ronove` in parallel (reuse `pi/pihole.nix`
     almost verbatim - it's already fully driven by `home-network/layout.nix`).
  2. Disable Pi-hole's DHCP server on `pi`, enable it on `ronove` in the same
     `nixos-rebuild switch` (or accept a short window with no DHCP server - existing leases
     keep working until they expire, `leaseTime = "7h"` in `layout.nix`).
  3. No router change required - the router (`linksys`, `172.26.249.254`) is only the
     default gateway, not the DHCP/DNS server, so it doesn't need to know which host is
     running Pi-hole.
  4. Clients pick up the new DHCP/DNS server automatically on next lease renewal; can force
     it sooner per-device if needed.

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

### 3. Final pi decommission

Once Pi-hole and (if ever) the VPN/NAT/modem role have moved off, `pi` can be powered down.
Until then it remains the home network's DNS/DHCP/VPN/NAT appliance - do not remove those
roles from `hosts/pi` until their replacements are confirmed stable on `ronove`.
