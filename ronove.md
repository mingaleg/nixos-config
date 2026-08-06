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
  renewal or forced per-device. Confirmed working: `ronove`'s DHCP listener is live (`pi`'s is
  gone), `mingapred` renewed and received its reserved lease (`172.26.249.2`) from `ronove`'s
  `/etc/pihole/dhcp.leases`. Pi-hole migration (DNS + DHCP) fully done and validated.

- **WireGuard endpoint (`wg0`) - done, deployed and working**: moved to `ronove` entirely
  (decided to *not* carry the modem/NAT role along - "not mission critical", can move later
  independently). `hosts/ronove/wireguard-vpn.nix` added (new `wg0`, NAT for VPN clients
  reaching the home network via `enp2s0`, no modem/`enu2` role) and wired into
  `hosts/ronove/default.nix`. `hosts/pi/wireguard-vpn.nix`'s import commented out (kept for
  rollback, same pattern as `strongswan.nix`); `pi`'s now-stale `wg0` entry dropped from its
  `networking.nat.internalInterfaces`. `hosts/vps/wireguard.nix`'s `wg-pi` peer now points at
  `ronove`'s public key; its `allowedIPs`/routes for the modem subnet (`192.168.8.0/24`)
  dropped from both the `wg-pi` peer and `wg-clients`' routes, since that's not moving.
  Keypair generated by the user under `/mnt/pegasus/secrets/wireguard/`, encrypted via agenix
  on `mingamini` and committed as `secrets/wireguard-ronove-private.age` (round-trip-verified
  without the plaintext passing through the assistant).
  - Hit one deploy-time snag: `ronove` had *never* needed to decrypt an agenix secret before
    (`wireguard-ronove-private` was its first one), so it was missing the shared agenix host
    identity at `/root/.ssh/agenix-hosts` entirely - agenix logged
    `WARNING: config.age.identityPaths entry /root/.ssh/agenix-hosts not present!` and silently
    failed to decrypt anything (not just the WireGuard key), so `wireguard-wg0.service` failed
    with `fopen: No such file or directory`. Fixed by copying the identity file from `pi`
    (which already had it) directly to `ronove` over SSH, verified by checksum match without
    the key content ever appearing in the assistant's context. Note: agenix only decrypts at
    *activation* time, so a service restart alone doesn't pick up a newly-arrived identity file
    - required a redeploy to re-run activation. After that, confirmed working end-to-end.
  - **Still needed from you**: the router's UDP 51821 port-forward, if one exists pointed at
    `pi`, should move to `ronove` - out-of-band, not managed by this repo.

- **`pi`/`ronove` IP addresses swapped** in `home-network/layout.nix`: `ronove` is now
  `172.26.249.253` (pi's old address) and `pi` is now `172.26.249.251` (ronove's old address).
  Both hosts pick this up automatically since their static-IP config reads from `layout.nix`
  symbolically. This also exposed a real bug: `modules/pihole.nix`'s DHCP classless-static-route
  (option 121) had `172.26.249.253` hardcoded as the gateway for *all* of the WireGuard subnets,
  the strongswan VPN subnet, and the modem subnet - which was simply wrong now that WireGuard
  lives on `ronove` while strongswan and the modem stay on `pi`. Rewrote it to derive each
  gateway from `layout.machines.<host>.interfaces.eth.ip` instead of a hardcoded literal, so it
  no longer depends on which literal IP either host holds. Deployed and validated: clients'
  live DNS server (`resolvectl status` per-link) correctly moved to the new `.253`. (One
  client's `/etc/resolv.conf` lagged behind as a stale static snapshot after the swap - a
  local Arch-desktop DHCP-hook quirk unrelated to this repo, not a sign the swap itself didn't
  propagate correctly.)

- **Network throughput tuning factored out** into a shared `modules/network-tuning.nix`
  (`net.ipv4.ip_forward`, TCP buffer/window sysctls, and the ring-buffer/interrupt-coalescing
  `network-optimization` systemd service - all previously `pi`-only), taking a
  `networkTuning.interface` option. Applied to both `pi` (`end0`) and `ronove` (`enp2s0`), since
  `ronove` now also does WireGuard forwarding, DHCP/DNS, and Samba traffic that benefit from the
  same tuning.

Remaining steps (Stage 3+)
===

### 1. Network-related services still on pi (deferred by design)

These all stay on `pi` for now. Moving each has different blast radius and different
external dependencies:

- **Pi-hole (DNS + DHCP)** - [done, see Stage 3 status above] fully implemented (DNS stood up
  on `ronove` in parallel, then DHCP cut over from `pi`); pending your deploy + confirmation
  that clients pick up the new DHCP/DNS server correctly.

- **WireGuard endpoint** - [done, see Stage 3 status above] moved to `ronove`, deployed and
  confirmed working; router UDP 51821 port-forward still to be checked/moved by you if it
  exists.

- **NAT to the cellular modem** - [done] modem physically moved from `pi` to `ronove`.
  Cold-plugging it exposed a real nixpkgs bug: the packaged `usb_modeswitch` udev rule
  dispatches to a templated systemd service whose compiled dispatcher binary errors out
  (Tcl arg-parsing bug) instead of actually switching the HiLink stick out of mass-storage
  mode. Worked around with a custom udev rule in `hosts/ronove/default.nix` that calls
  `usb_modeswitch` directly - verified live (mode-switch, interface `enp0s20u10` comes up,
  modem UI reachable). Added static IP (`192.168.8.100/24`, no gateway) for that interface,
  plus `networking.nat` (external `enp0s20u10`, internal `enp2s0` + `wg0`) so both LAN and
  VPN clients get masqueraded to `ronove`'s modem-side IP when reaching it - mirrors what
  `pi` used to do. `modules/pihole.nix`'s classless-static-route and `hosts/vps/wireguard.nix`
  (`wg-pi` + `wg-clients`) both updated to route the modem host via `ronove`, using a `/32`
  (not the full `/24`) sourced from `layout.machines.modem.interfaces.usb.ip` to minimize
  collision risk with VPN clients' own local networks. Deployed on `ronove` + `vps` and
  confirmed working end-to-end: modem UI reachable both from the LAN and through the VPN
  (`wg-clients`) tunnel. One red herring while debugging: pinging `192.168.8.1` directly
  *from `vps` itself* failed with `sendmsg: Destination address required` - a source-address
  quirk specific to locally-originated sockets on a NOARP point-to-point WireGuard interface,
  unrelated to actual forwarded VPN-client traffic (confirmed via `ping -I wg-pi`, which
  worked fine, and `ip route get ... from 10.100.0.80 iif wg-clients`, which resolved
  correctly). Not a sign of any config problem.

- **pi now uses DHCP for networking** - [done] `pi` no longer statically configures its IP;
  `hosts/pi/default.nix` dropped `networking.useDHCP = false` and the static `end0` address, so
  `pi` picks up its IP and DNS from `ronove`'s DHCP/Pi-hole (still pinned to
  `172.26.249.251` via the existing MAC-based static reservation in `modules/pihole.nix`).
  `networking.nameservers` override removed too, so `pi` uses the DHCP-announced DNS
  (`ronove`) instead of pointing at itself. Pending your deploy + confirmation.

- **Chrony NTP server** - [done] moved wholesale from `hosts/pi/default.nix` to
  `hosts/ronove/default.nix` (same config: upstream pool servers, `allow`/`local stratum 10`
  for the LAN, UDP 123 opened). Not paralleled first like Pi-hole was - low risk enough for a
  straight cutover. Deploy pending on both hosts (remove from `pi`, add on `ronove`).

- **`strongswan.nix` and `wireguard-vpn.nix` on `pi`** - [done] both deleted (previously
  disabled/commented out, kept for rollback; WireGuard-only VPN has been stable). Also
  removed their now-unused secrets (`wireguard-pi-private.age`, `vpn-users.age`,
  `gcp-dns-credentials.age`) from `secrets/wireguard.nix`/`secrets/secrets.nix`, and dropped
  the now-dead `172.26.249.160/28` (strongswan's old VPN pool) route from
  `modules/pihole.nix`'s classless-static-route - only the default route, WireGuard networks,
  and the modem host remain, all via `ronove`. Deploy pending on `pi` + `ronove`.

### 2. Final pi decommission

Once Pi-hole and (if ever) the VPN/NAT/modem role have moved off, `pi` can be powered down.
Until then it remains the home network's DNS/DHCP/VPN/NAT appliance - do not remove those
roles from `hosts/pi` until their replacements are confirmed stable on `ronove`.
