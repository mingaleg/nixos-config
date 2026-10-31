---
name: ship
description: Deploy (ship) nixos-config changes to fleet hosts through ronove's fleet-deployer API. Use when the user asks to deploy, ship, roll out, release, or apply a change to ronove, vps, mingamini or foreign-agent, or asks what a host is running or whether it is behind main. It replaces running deploy_remote by hand.
---

# Shipping nixos-config through ronove

ronove runs fleet-deployer (see `fleet-deployer.md`, and the code in
`~/projects/fleet-deployer`).
- It builds **`main` of github.com/mingaleg/nixos-config**, so only pushed commits can be shipped.
- It compares, per host, the system `main` would build with what the host runs.
- It deploys with `nixos-rebuild <mode> --target-host` when asked.
- Dashboard: http://ronove.home.mingalev.net:8090. The API is under `/api`.

## When to deploy

Deploy only when the user asks for a deploy or ship in the current request. Otherwise commit,
push, and stop: the user decides when changes go live. Never deploy a host the user didn't
name. Saying "push" doesn't mean "deploy".

## Hosts

| Host | Deployable | Notes |
|---|---|---|
| ronove | yes | The hub. Deploying it restarts the deployer itself, so the API is down for a few seconds and the helper waits it out. |
| vps | yes | The WireGuard relay. A restart briefly drops the home tunnel and the VPN (about 2–3 min to reconnect). |
| foreign-agent | yes, `test` first | Remote, at the user's parents'. Hard to recover if broken, though a power cycle undoes a `test`. |
| mingamini | yes, as `root` | The user's laptop, possibly in use. It may be asleep or away; away from home it's only reachable while its `wg-home` VPN is up. For display, graphics, desktop or kernel changes, use `boot` (or `test`) rather than a live `switch`. Tell the user before shipping there. |

## Modes

- `test`: activate now, but a reboot returns to the previous system.
- `switch`: activate now and keep after reboots. This is the default.
- `boot`: activate at the next reboot only.

Use **`test` first, then `switch`**, for anything touching networking, WireGuard, SSH, the
firewall, or foreign-agent at all. For mingamini, prefer `boot` for anything that would
disturb a running desktop session. After a `test`, the host shows the `boot_differs` flag until
it gets a `switch`.

## Procedure

1. Commit and push the change to `main` with jj (`jj describe`,
   `jj bookmark set main -r @`, `jj git push -b main`). Check it evaluates first
   (`nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`).
2. Ship it with the helper, from the repo root:
   ```
   python3 .claude/skills/ship/ship.py <host> [--mode test|switch|boot]
   ```
   It does the following:
   - Asks the deployer to fetch `main`.
   - Waits until the deployer has evaluated the commit you just pushed. It takes the local
     `main` bookmark's sha, or `--rev`. Evaluation can take minutes on ronove.
   - Shows the host's state. It stops early if the host is already in sync, unless you pass
     `--force`.
   - Queues the deploy, streams the job log, and waits until the host reports the expected
     system.
   - Exits 0 only if the job succeeded and the host runs what `main` builds.
3. For several hosts, ship them one at a time: the deployer only runs one job at a time anyway.
   Put risky hosts last and use `test` on them first.
4. Report to the user:
   - the job id and its result;
   - the host's final state and commit;
   - anything odd in the log (failed units, warnings).

   On failure, show the end of the log; don't retry blindly.

Status only, without deploying: `python3 .claude/skills/ship/ship.py --status`.

## Auth

From the home LAN (`172.26.249.0/24`), the WireGuard VPN (`10.100.0.0/24`) or ronove itself,
no token is needed. From anywhere else, the helper reads the token from
`/mnt/pegasus/secrets/fleet-deployer/api-token`, or from `$FLEET_TOKEN`. Never print the token.

## Reading states

| State | Meaning |
|---|---|
| `in_sync` | Runs exactly what `main` builds. A change that doesn't affect a host leaves it in sync, because comparison is by built system, not by commit. |
| `behind` | `main` would build something different. |
| `unknown` | `main` hasn't been evaluated for it yet, or the evaluation failed (see `expected_error`). |
| `unreachable` | The poll failed. A `Permission denied` error means the deployer's key isn't on the host yet: deploy it once with `./deploy_remote --test <host>` from mingamini. |

Flags:
- `boot_differs`: a `test` deploy is live, or a `boot` deploy is waiting for a reboot.
- `reboot_pending`: the host runs a new kernel that only takes effect after a reboot.

## Fallback

If the deployer itself is broken, use `./deploy_remote [--test] <host> [target]`. Run it from
mingamini, the only machine with aarch64 emulation besides ronove: e.g.
`ssh mingamini 'cd ~/nixos-config && jj git fetch && jj new main@origin && echo | ./deploy_remote ronove'`.
