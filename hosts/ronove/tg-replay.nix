{ tg-replay, ... }:

# tg-replay (github:mingaleg/tg-replay): ranks an old Telegram channel's posts
# and reposts the best ones on a schedule. Served as http://tg-replay.ronove by
# web-proxy.nix, LAN and VPN only. Everything it knows - credentials, the
# Telegram session, channels, the schedule - lives in /var/lib/tg-replay and is
# set up on its own settings page.
#
# Only one instance may ever use that data: two would share one Telegram
# session (which Telegram may revoke) and both would post.
{
  imports = [ tg-replay.nixosModules.default ];

  services.tg-replay.enable = true;
}
