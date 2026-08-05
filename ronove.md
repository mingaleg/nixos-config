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
