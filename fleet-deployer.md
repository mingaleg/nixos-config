fleet-deployer
===

ronove is the fleet's build and release hub. It runs
[fleet-deployer](https://github.com/mingaleg/fleet-deployer) (`hosts/ronove/fleet-deployer.nix`):
- It tracks `main` of this repo.
- It evaluates what each host would run and polls every host over SSH, every 5 minutes.
- It deploys only when asked. It never deploys on its own.

- **Dashboard:** http://ronove.home.mingalev.net:8090, readable from the LAN and the VPN.
- **Actions** (deploy, refresh) need no token from the home LAN or the WireGuard VPN
  (`trustedNetworks`). From anywhere else they need the API token. The plaintext is in
  `/mnt/pegasus/secrets/fleet-deployer/api-token`; it's stored as
  `secrets/fleet-deployer-token.age`. It's long-lived and never needs rotating.
- **API** (see the repo's README), e.g.:
  ```
  curl -X POST -H "Authorization: Bearer $(cat /mnt/pegasus/secrets/fleet-deployer/api-token)" \
    -H 'Content-Type: application/json' -d '{"host":"vps","mode":"test"}' \
    http://ronove.home.mingalev.net:8090/api/deploy
  ```

Hosts
---

| Host | Deploy | How the deployer gets in |
|---|---|---|
| ronove | yes, to itself via `localhost` | `fleet-deployer.pub` authorized for `mingaleg` (core-server) |
| vps | yes, via `home-gw.mingalev.net` | same |
| foreign-agent | yes, over the VPN | same. It only arrives with foreign-agent's next deploy, so until then the dashboard shows it unreachable. |
| mingamini | yes, as `root` | the key is authorized for root, and only from ronove's addresses (`from="172.26.249.253,10.200.0.2"`); mingaleg keeps its sudo password (`hosts/mingamini`) |

- **Building foreign-agent:** ronove builds it under aarch64 emulation (`boot.binfmt`).
- **Host keys:** checked strictly against `programs.ssh.knownHosts` in the module file.
- **Deploy key:** the plaintext is in `/mnt/pegasus/secrets/fleet-deployer/id_ed25519`; it's
  stored as `secrets/fleet-deployer-ssh.age`.

Use **test** first for anything that touches networking, WireGuard, SSH or the firewall, then
**switch**. `./deploy_remote` from mingamini remains the manual fallback.
