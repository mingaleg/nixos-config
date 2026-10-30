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
  the current config with `./deploy_remote foreign-agent`. Rewrite the stick whenever a change
  matters for reachability (VPN, Wi-Fi, SSH).
- Instructions for Igor and Tanya, in Russian: `docs/foreign-agent-recovery-ru.html` (print it,
  keep it with the stick).

Writing the stick (the image is aarch64, so it needs an aarch64 builder):

```
nix build .#images.foreign-agent-recovery --builders 'ssh://<aarch64-host> aarch64-linux' --no-link --print-out-paths
scripts/make-foreign-agent-recovery.sh [--image <out>/sd-image/*.img.zst] /dev/sdX
```

Migration from `pi`
---

Status: code written and `nix flake check --no-build` passes. Nothing below is deployed yet.

1. Deploy `vps`, so it knows the new peer. Optionally deploy `ronove`, which drops `pi`'s DHCP
   reservation and DNS records.
2. On the old `pi`, still at home, set the boot order and reboot once. It should still come up
   from SD:
   ```
   nix shell nixpkgs#raspberrypi-eeprom
   sudo rpi-eeprom-config > boot.conf     # set BOOT_ORDER=0xf14
   sudo BOOTFS=/boot/firmware rpi-eeprom-config --apply boot.conf
   sudo reboot
   ```
3. Build the recovery image on an aarch64 builder. The old `pi` itself works while it is still
   running. Then write the stick with `scripts/make-foreign-agent-recovery.sh`.
4. Do the first install **with the stick**. This tests the break-glass path and wipes the
   fleet-wide `agenix-hosts` key that is still on the old SD card. The sequence: insert stick →
   power on → wait for power-off → remove stick → power on.
5. Verify at home before shipping:
   - **Ethernet**: `ssh foreign-agent` works; `wg show wg-clients` on vps shows a handshake.
   - **Wi-Fi**: unplug the cable → it joins `mingahome` and SSH recovers within about a minute.
   - **Hot-plug**: insert the stick into the running box (uptime over 5 min) → it reboots into
     recovery → it powers off.
   - **Coldplug guard**: boot with a disarmed stick (rename `config.txt` on `FA_RECFW`) → it
     does not reboot-loop.
6. Ship with the stick and the printed Russian instructions.

TODO once on site
---

- Look at their network and decide whether to route their subnet. If so: masquerade on
  foreign-agent, add `allowedIPs`/routes on vps, ronove `wg0` and the pihole classless routes.
- Watch for subnet collisions with VPN clients' own networks.
