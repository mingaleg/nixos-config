foreign-agent
===

The Raspberry Pi 5 formerly known as `pi`, repurposed after its home-network roles moved to
`ronove` (see ronove.md). It lives at Igor and Tanya's house as a foothold into their network.

- **Reachability**: it dials out to `vps` as a road-warrior peer on `wg-clients`
  (`10.100.0.33`, `layout.machines.foreign-agent.vpn`). `ssh foreign-agent` works from any VPN
  client and from the home LAN (via `ronove`'s `wg0`). There is no inbound port on their side.
- **Their LAN**: SSH only for now. Use `ssh -J foreign-agent <host>` or `ssh -D 1080 foreign-agent`.
- **Networking** (`hosts/foreign-agent/network.nix`): NetworkManager uses ethernet (`end0`)
  whenever a cable is plugged in, otherwise Wi-Fi `Solnd082`, then `mingahome`. The PSKs live
  in `secrets/foreign-agent-wifi.age`.
- **Identity**: its own ed25519 SSH host key doubles as its agenix identity. Its secrets are
  encrypted to `[ mingaleg foreignAgent ]` only, never to `allHosts`, because the key also
  lives on the recovery stick in their house. Plaintext is kept in
  `/mnt/pegasus/secrets/foreign-agent/`.
- **Self-healing**: a hardware watchdog (`RuntimeWatchdogSec=30s`), plus
  `wg-handshake-watchdog`, which reboots the box if `vps` hasn't handshaken for an hour.

Recovery stick (break-glass)
---

The stick can reset the box to a known-good config that has the VPN, Wi-Fi and SSH set up,
however badly a deploy went.

- The EEPROM boot order is `0xf14`: USB first, then SD.
- Booting the stick (`hosts/foreign-agent-recovery`) does the following:
  1. Reflashes `/dev/mmcblk0` with `images.foreign-agent`, which is embedded in the stick's
     closure.
  2. Copies the host key from `/recovery` on the stick onto the new root.
  3. Powers off.
  The ACT LED blinks steadily while working. On failure it shows a heartbeat pattern and the
  box stays up; SSH is open on ethernet DHCP and console login works.
- Plugging the stick into a *running* box (uptime over 5 min) triggers a reboot into it
  (`hosts/foreign-agent/recovery.nix`). The uptime guard stops a coldplug reboot loop if USB
  boot ever falls through to SD.
- The stick restores the config **as of when the stick was written**. After a reset, redeploy
  the current config with `./deploy_remote foreign-agent`.
- For changes that could cut off access (networking, WireGuard, SSH, firewall), deploy with
  `./deploy_remote --test foreign-agent` first. That activates the change without making it the
  boot default, so if it breaks access, a power cycle by Igor or Tanya brings back the previous
  generation. Run it again without `--test` once confirmed. Rewrite the stick whenever a change
  matters for reachability (VPN, Wi-Fi, SSH).
- Instructions for Igor and Tanya, in Russian: `docs/foreign-agent-recovery-ru.html` (print it,
  keep it with the stick).

Writing the stick (the image is aarch64, so it needs an aarch64 builder):

```
nix build .#images.foreign-agent-recovery --builders 'ssh://<aarch64-host> aarch64-linux' --no-link --print-out-paths
scripts/make-foreign-agent-recovery.sh [--image <out>/sd-image/*.img.zst] /dev/sdX
```

EEPROM setup (once per Pi)
---

The recovery stick only works if the Pi's bootloader EEPROM says so. These settings live on the
EEPROM chip, not the SD card, so they survive reflashes and deploys and are deliberately not in
the nix config. Redo them on any replacement Pi:

- `BOOT_ORDER=0xf14`: try USB first, then SD.
- `PSU_MAX_CURRENT=5000`: a Pi 5 on a supply that doesn't advertise 5A (anything but the
  official 27W PSU; pi's negotiates 3A) silently skips USB boot. This tells the bootloader to
  treat the supply as 5A-capable. It also raises the USB ports' total current limit from 600mA
  to 1.6A, which is fine with only the stick attached.

```
nix shell nixpkgs#raspberrypi-eeprom
sudo rpi-eeprom-config > boot.conf     # edit/add the two lines above
sudo BOOTFS=/boot/firmware rpi-eeprom-config --apply boot.conf \
  <raspberrypi-eeprom>/lib/firmware/raspberrypi/bootloader-2712/default/pieeprom-<date>.bin
sudo reboot
```

On a Pi 5 this flashes immediately via flashrom (`VERIFY: SUCCESS`). Applying a config always
writes a whole bootloader image; give the `default` (stable) one explicitly. pi went from
2024-09-23 to 2025-11-05 this way.

Migration from `pi`
---

Status (2026-10-30): done and verified at home, not yet shipped.

- vps and ronove deployed. ronove no longer reserves pi's old `172.26.249.251`.
- EEPROM set up as above (2025-11-05 bootloader).
- Recovery image built on mingamini (aarch64 via binfmt). Stick written: a Transcend 4GB.
- First install done **with the stick**: about 12 min, mostly the SD card's ~5MB/s writes. This
  also wiped the fleet-wide `agenix-hosts` key from the old SD card.
- Verified after the reinstall:
  - Host key unchanged, and the secrets decrypt.
  - On ethernet: tunnel up, vps sees handshakes.
  - Wi-Fi works with only the Pi's own firmware blob. With a fake `Solnd082` present it
    prefers that over `mingahome`, and is reachable as `foreign-agent` over the VPN.
- Not tested: hot-plug reset (inserting the stick into a running box), and the coldplug guard.

Known quirk while it sits on the home LAN: home-LAN clients can't reach it over the VPN
(`ssh foreign-agent` times out). Their source address is on its `end0` subnet, so the NixOS
reverse-path filter drops those packets when they arrive on `wg-home`. Use its LAN address at
home. It doesn't occur on any other network.

Left before shipping: print `docs/foreign-agent-recovery-ru.html`, write your number on it, and
pack it with the stick.

TODO once on site
---

- Look at their network and decide whether to route their subnet. If so: masquerade on
  foreign-agent, add `allowedIPs`/routes on vps, ronove `wg0` and the pihole classless routes.
- Watch for subnet collisions with VPN clients' own networks.
